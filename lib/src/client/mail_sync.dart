import 'dart:async';

import 'package:blossom_cache/blossom_cache.dart';
import 'package:ndk/ndk.dart';
import 'package:sync_engine_shim_for_ndk/sync_engine_shim_for_ndk.dart';

import '../constants.dart';
import '../exceptions.dart';
import '../models/gift_wrap_state.dart';
import '../models/mail_event.dart';
import '../models/unwrapped_gift_wrap.dart';
import '../storage/email_repository.dart';
import '../storage/gift_wrap_repository.dart';
import '../storage/label_repository.dart';
import '../storage/models/email_record.dart';
import '../storage/tombstone_repository.dart';
import '../utils/throttle.dart';
import 'cache_window.dart';
import 'relay_resolver.dart';
import 'replay_queue.dart';
import '../utils/event_email_parser.dart';
import 'event_bus.dart';
import 'filters.dart';

/// Orchestrates inbound synchronization from Nostr relays.
///
/// The [SyncEngine] shim keeps the NDK cache filled with everything this
/// account needs; the cache is then the source of truth for raw events, and
/// the local tables are a projection of it rebuilt by
/// [_processFromCache]. An event whose processing fails therefore stays in the
/// cache, and is retried whenever a round covers it again: the engine walking
/// its period a second time, or a [fetchRecent], which replays everything.
class MailSync {
  final Ndk _ndk;
  final SyncEngine _engine;
  final EmailRepository _emails;
  final LabelRepository _labels;
  final GiftWrapRepository _giftWraps;
  final TombstoneRepository _tombstones;
  final EventBus _bus;
  final RelayResolver _relays;
  final List<String> _defaultBlossomServers;
  final BlossomCache _blossomCache;

  /// One handle per scope of [_ensureHandles], held until the account changes
  /// or the client is disposed.
  final Map<String, SyncHandle> _handles = {};

  final Map<SyncHandle, StreamSubscription<SyncRequestStatus>> _watchers = {};

  StreamSubscription<Account?>? _account;

  /// The last page seen per handle. A status carries the page that landed, and
  /// is re-emitted on every phase change and replayed to every new listener,
  /// so the instance itself is what tells a new page from an echo.
  final Map<SyncHandle, SyncProgress> _lastProgress = {};

  Future<void>? _replaying;

  /// What the next round has to cover.
  final _owed = ReplayQueue();

  MailSync(
    this._ndk,
    this._engine,
    this._emails,
    this._labels,
    this._giftWraps,
    this._tombstones,
    this._bus,
    this._relays, {
    required this._blossomCache,
    List<String>? defaultBlossomServers,
  }) : _defaultBlossomServers =
           defaultBlossomServers ?? recommendedBlossomServers;

  String? get _pubkey => _ndk.accounts.getPublicKey();

  void _assertPubkey() {
    if (_pubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }
  }

  // ── Public API ──────────────────────────────────────────────────────────

  /// Goes to the relays now, however fresh the coverage is, then rebuilds the
  /// local stores. This is the pull-to-refresh gesture, and the only reason
  /// left to ask for anything: staying up to date needs no call at all.
  Future<void> fetchRecent() async {
    _assertPubkey();
    final handles = await _ensureHandles();
    await Future.wait(handles.map(_engine.refresh));
    await _replayCache();
  }

  /// Declares this account's requests, so the engine keeps them filled and
  /// revisits them on its own. Called on every account change; idempotent.
  Future<void> declare() async {
    if (_pubkey == null) {
      release();
      return;
    }
    await _ensureHandles();

    if (_rebuildOwed) {
      _rebuildOwed = false;
      _replayCache().ignore();
    }
  }

  /// Says the local stores were dropped and have to be rebuilt whole.
  ///
  /// Nothing else would ask: the engine's coverage did not move, so its rounds
  /// bring no page, and without this the mailbox stays empty until a
  /// [fetchRecent]. The pass itself needs no network, and no signer for a wrap
  /// whose decryption survived the drop.
  void oweRebuild() => _rebuildOwed = true;

  bool _rebuildOwed = false;

  /// Drops this client's interest in its sync requests, which stops the engine
  /// revisiting them. The coverage it persisted survives; the engine itself
  /// belongs to the caller and is never started, stopped or disposed here.
  void release() {
    for (final handle in _handles.values) {
      _drop(handle);
    }
    _handles.clear();
  }

  /// Follows the active account: what to sync is derived from its pubkey, so a
  /// login, a switch or a logout has to redraw every request. Without this the
  /// caller would have to remember to say so, and forgetting would look like a
  /// mailbox that simply stopped filling.
  void followActiveAccount() {
    _account ??= _ndk.accounts.authStateChanges.listen((_) {
      declare().ignore();
    });
  }

  /// Stops following the account and drops every request.
  void dispose() {
    _account?.cancel().ignore();
    _account = null;
    release();
  }

  // ── Sync requests ───────────────────────────────────────────────────────

  /// Declares everything this account needs locally, split by the relay set
  /// each filter belongs to. Reposts, settings and metadata are declared only
  /// to warm the NDK cache: nothing processes them here.
  Future<List<SyncHandle>> _ensureHandles() async {
    final pubkey = _pubkey!;

    final (dmRelays, writeRelays) = await (
      _relays.getDmRelays(pubkey),
      _relays.getWriteRelays(pubkey),
    ).wait;
    final allRelays = {...dmRelays, ...writeRelays}.toList();

    return [
      _ensure('emails', [emailFilter(pubkey)], dmRelays, authPubkey: pubkey),
      _ensure(
        'deletions',
        [deletionFilter(pubkey)],
        allRelays,
        authPubkey: pubkey,
      ),
      _ensure(
        'write',
        [
          publicEmailFilter(pubkey),
          labelFilter(pubkey),
          repostFilter(pubkey),
          settingsFilter(pubkey),
          metadataFilter(pubkey),
        ],
        writeRelays,
        authPubkey: pubkey,
      ),
    ];
  }

  /// The engine derives the request identity from the filters, the relay set
  /// and [authPubkey], all of which move here: switching account rewrites the
  /// filters, and [RelayResolver] hands back the fallback list until the kind
  /// 10050 lands. A hand-written id would pin whichever it saw first.
  ///
  /// [authPubkey] is passed rather than read back from ndk: the account can
  /// change while the relays resolve, and a request must not carry one
  /// account's filters under another's identity.
  SyncHandle _ensure(
    String scope,
    List<Filter> filters,
    List<String> relays, {
    required String authPubkey,
  }) {
    final handle = _engine.ensure(
      SyncRequest(filters: filters, relays: relays, authPubkey: authPubkey),
    );

    final held = _handles[scope];
    if (held == handle) {
      // ensure() counts one more holder per call; a scope only ever holds one.
      _engine.release(handle);
    } else {
      if (held != null) _drop(held);
      _handles[scope] = handle;
      _watch(handle);
    }

    return handle;
  }

  /// Replays the cache on every page [handle] brings in, for as long as it is
  /// held. A held request revisits its windows on its own every
  /// `maxStaleness`, so most pages land outside any call of ours: watching
  /// only during one would leave that mail sitting in the cache, unprojected.
  void _watch(SyncHandle handle) {
    _watchers[handle] = _engine.watchStatus(handle).listen((status) {
      final progress = status.progress;
      if (progress == null || identical(_lastProgress[handle], progress)) {
        return;
      }
      _lastProgress[handle] = progress;

      // A page that brought nothing cannot have changed the cache, and most
      // pages of a routine pass are empty ones closing a window.
      if (progress.eventCount == 0) return;

      // Best effort: nobody is awaiting this round, and the cache keeps what
      // failed, so a later round retries it.
      _replayCache(CacheWindow.of(progress)).ignore();
    });
  }

  void _drop(SyncHandle handle) {
    _engine.release(handle);
    _watchers.remove(handle)?.cancel().ignore();
    _lastProgress.remove(handle);
  }

  // ── Cache processing ────────────────────────────────────────────────────

  /// Replays the cache, one round at a time. Asking again while a round runs
  /// queues a single follow-up instead of racing it, so a walk landing twenty
  /// pages costs a handful of rounds rather than twenty, and two rounds never
  /// process the same event at once.
  ///
  /// [window] is the period to cover; null covers the whole cache. Everything
  /// asked for while a round runs is merged into the one that follows.
  Future<void> _replayCache([CacheWindow? window]) {
    _owed.owe(window);
    return _replaying ??= _replayRounds();
  }

  Future<void> _replayRounds() async {
    try {
      while (_owed.isPending) {
        final window = _owed.take();
        try {
          await _processFromCache(window);
        } catch (_) {
          // Nothing else covers this ground: the page that asked for it is
          // long acknowledged, and the engine will not walk its period again
          // until the coverage goes stale.
          _owed.owe(window);
          rethrow;
        }
      }
    } finally {
      _replaying = null;
    }
  }

  /// Rebuilds the local stores from the NDK cache, over [window] or over
  /// everything when it is null.
  ///
  /// Every handler is idempotent, so a round may cover ground already
  /// projected. It should still cover as little as possible: the cache hands
  /// back a decoded event per match, which is what a mailbox-sized replay
  /// spends its time on.
  Future<void> _processFromCache(CacheWindow? window) async {
    final pubkey = _pubkey;
    if (pubkey == null) return;

    // Gift wraps and public emails run in parallel, up to
    // [maxProcessingConcurrency] at a time. Deletions and labels stay
    // sequential to avoid races.
    //
    // A cancelled signer request ends the round: the only error that reaches
    // here, and the wraps left would each ask the user again.
    await forEachThrottled(
      await _fromCache(emailFilter(pubkey), window),
      maxProcessingConcurrency,
      onGiftWrap,
    );

    for (final event in await _fromCache(deletionFilter(pubkey), window)) {
      await onDeletion(event);
    }

    await forEachThrottled(
      await _fromCache(publicEmailFilter(pubkey), window),
      maxProcessingConcurrency,
      onPublicEmail,
    );

    for (final event in await _fromCache(labelFilter(pubkey), window)) {
      await onLabelAddition(event);
    }
  }

  Future<List<Nip01Event>> _fromCache(Filter filter, CacheWindow? window) =>
      _ndk.config.cache.loadEvents(
        ids: filter.ids,
        pubKeys: filter.authors,
        kinds: filter.kinds,
        tags: filter.tags,
        since: window?.since ?? filter.since,
        until: window?.until ?? filter.until,
      );

  /// Retry processing a single failed gift wrap.
  Future<bool> retry(String eventId) async {
    final pubkey = _pubkey;
    if (pubkey == null) return false;
    final event = await _giftWraps.getUnprocessed(
      eventId,
      recipientPubkey: pubkey,
    );
    if (event == null) return false;
    return _processEvent(event);
  }

  Future<int> getFailedCount() {
    final pubkey = _pubkey;
    if (pubkey == null) return Future.value(0);
    return _giftWraps.getFailedCount(recipientPubkey: pubkey);
  }

  Future<List<FailedGiftWrap>> getFailedGiftWraps() {
    final pubkey = _pubkey;
    if (pubkey == null) return Future.value(const []);
    return _giftWraps.getUnfinished(recipientPubkey: pubkey);
  }

  // ── Event processing ────────────────────────────────────────────────────

  Future<void> onGiftWrap(Nip01Event event) async {
    final owner = event.getFirstTag('p');
    if (owner == null || !_ndk.accounts.hasAccount(owner)) return;

    // A deleted email's wrap keeps being served, and dropping its row makes it
    // look new on every replay. Its own id is tombstoned alongside the rumor
    // id, so recognizing it here costs a lookup instead of two decryptions.
    if (await _tombstones.contains(event.id, recipientPubkey: owner)) return;

    // Stored under the wrap's own recipient, not the active account, so one
    // arriving mid account-switch stays retryable instead of being dropped.
    final progress = await _giftWraps.save(event, recipientPubkey: owner);
    if (owner != _pubkey) return;
    if (!_worthAttempting(progress)) return;
    await _processEvent(event);
  }

  /// Whether a wrap is worth an attempt.
  ///
  /// A permanent failure never turns into a success. A signer failure might,
  /// since a refusal and an impossible decryption reach us as the same error,
  /// but every attempt can cost the user an approval prompt: past
  /// [maxSignerAttempts] the wrap is parked, and only [retry] reopens it.
  bool _worthAttempting(GiftWrapProgress progress) {
    if (progress.stage == GiftWrapStage.stored) return false;
    return switch (progress.failure) {
      GiftWrapFailure.permanent => false,
      GiftWrapFailure.signer => progress.attempts < maxSignerAttempts,
      GiftWrapFailure.transient => true,
      null => true,
    };
  }

  Future<bool> _processEvent(Nip01Event event) async {
    final myPubkey = _pubkey;
    if (myPubkey == null) return false;

    final recipientTag = event.getFirstTag('p');
    if (recipientTag != myPubkey) return false;

    try {
      var unwrapped = await _giftWraps.getUnsealed(event.id);
      if (unwrapped == null) {
        unwrapped = await _unwrapGiftWrap(event);
        if (unwrapped == null) return false;
        await _giftWraps.updateUnsealed(
          giftWrapId: event.id,
          recipientPubkey: myPubkey,
          seal: unwrapped.seal,
          rumor: unwrapped.rumor,
        );
      }

      final rumor = unwrapped.rumor;

      if (rumor.kind != emailKind) {
        await _giftWraps.markStored(event.id);
        return false;
      }

      final isPublicRef = rumor.getFirstTag('public-ref') != null;

      // Skip emails the user already deleted locally. Gift wraps can be
      // re-served by relays that ignore NIP-09, while the tombstone is keyed
      // by the user-facing email id (the rumor id).
      if (await _tombstones.contains(rumor.id, recipientPubkey: myPubkey)) {
        await _tombstones.add(event.id, recipientPubkey: myPubkey);
        await _giftWraps.remove(event.id);
        return false;
      }

      // The recipient for storage purposes is always the active account —
      // gift wraps are addressed to us, so we own this row. Using the
      // rumor's first 'p' tag is wrong for cc/bcc, where it points at the
      // primary "to" recipient instead of us.
      final email = await parseEmailEvent(
        event: rumor,
        ndk: _ndk,
        recipientPubkey: myPubkey,
        isPublic: isPublicRef,
        defaultBlossomServers: _defaultBlossomServers,
        blossomCache: _blossomCache,
      );

      await _emails.save(EmailRecord.fromEmail(email));
      await _giftWraps.markStored(event.id);

      _bus.emit(EmailReceived(email: email, timestamp: email.date));
      return true;
    } on SignerRequestCancelledException {
      rethrow;
    } catch (error) {
      // Past the seal, what is left is the body: a malformed one will never
      // parse, anything else is a server we could not reach.
      await _giftWraps.recordFailure(
        giftWrapId: event.id,
        failure: error is EmailParseException || error is FormatException
            ? GiftWrapFailure.permanent
            : GiftWrapFailure.transient,
      );
      return false;
    }
  }

  Future<void> onPublicEmail(Nip01Event event) async {
    if (event.sig == null || event.sig!.isEmpty) return;
    if (event.kind != emailKind) return;

    final recipientPubkey = _pubkey;
    if (recipientPubkey == null) return;
    if (await _tombstones.contains(
      event.id,
      recipientPubkey: recipientPubkey,
    )) {
      return;
    }

    // Every sync replays the whole cache, and parsing pulls Blossom blobs.
    if (await _emails.getById(event.id, recipientPubkey: recipientPubkey) !=
        null) {
      return;
    }

    try {
      final email = await parseEmailEvent(
        event: event,
        ndk: _ndk,
        recipientPubkey: recipientPubkey,
        isPublic: true,
        defaultBlossomServers: _defaultBlossomServers,
        blossomCache: _blossomCache,
      );

      await _emails.save(EmailRecord.fromEmail(email));
      _bus.emit(EmailReceived(email: email, timestamp: email.date));
    } catch (_) {
      // Silently ignore malformed public emails
    }
  }

  Future<void> onDeletion(Nip01Event event) async {
    final pubkey = _pubkey;
    if (pubkey == null) return;
    if (event.pubKey != pubkey) return;

    for (final tag in event.tags) {
      if (tag.isNotEmpty && tag[0] == 'e') {
        final deletedEventId = tag[1];

        // Already tombstoned means this deletion was applied before, or the
        // local action that published it removed its rows itself. Skipping
        // spares a full label scan per tag on every replay of the cache.
        if (await _tombstones.contains(
          deletedEventId,
          recipientPubkey: pubkey,
        )) {
          continue;
        }

        // Record a tombstone unconditionally so the deleted event is not
        // re-applied if a relay re-serves it (or if a stale NDK cache
        // hands it back) before the relay has acted on this deletion.
        await _tombstones.add(deletedEventId, recipientPubkey: pubkey);

        // Try as email first (gift wrap or public email)
        final email = await _emails.getById(
          deletedEventId,
          recipientPubkey: pubkey,
        );
        if (email != null) {
          await _emails.delete(deletedEventId, recipientPubkey: pubkey);
          await _labels.deleteLabelsForEmail(
            deletedEventId,
            recipientPubkey: pubkey,
          );
          // Tombstone the wraps before dropping their rows, so a relay
          // re-serving them costs a lookup rather than a decryption.
          await _tombstones.addMany(
            await _giftWraps.getIdsByRumorIdsForRecipient([
              deletedEventId,
            ], recipientPubkey: pubkey),
            recipientPubkey: pubkey,
          );
          await _giftWraps.removeByRumorIdsForRecipient([
            deletedEventId,
          ], recipientPubkey: pubkey);
          _bus.emit(EmailDeleted(emailId: deletedEventId));
          continue;
        }

        // Try as label
        final allLabels = await _labels.getAllLabels(recipientPubkey: pubkey);
        var foundLabel = false;
        for (final labelRecord in allLabels) {
          if (labelRecord.labelEventId == deletedEventId) {
            final emailId = labelRecord.emailId;
            final label = labelRecord.label;
            await _labels.removeLabel(emailId, label, recipientPubkey: pubkey);
            _bus.emit(
              LabelRemoved(
                emailId: emailId,
                label: label,
                timestamp: DateTime.fromMillisecondsSinceEpoch(
                  event.createdAt * 1000,
                ),
              ),
            );
            foundLabel = true;
            break;
          }
        }
        if (foundLabel) continue;

        // Repost deletion — nothing local to delete
      }
    }
  }

  Future<void> onLabelAddition(Nip01Event event) async {
    final pubkey = _pubkey;
    if (pubkey == null) return;

    // A label event must be authored by the active account — labels are
    // published by the account that owns them, so a label whose author
    // differs from the active pubkey belongs to someone else.
    if (event.pubKey != pubkey) return;

    // Skip events the user has deleted: relays that don't honor NIP-09
    // and NDK's in-memory cache can both re-serve these.
    if (await _tombstones.contains(event.id, recipientPubkey: pubkey)) {
      return;
    }

    final namespaceTag = event.tags.firstWhere(
      (t) => t.isNotEmpty && t[0] == 'L' && t[1] == labelNamespace,
      orElse: () => [],
    );
    if (namespaceTag.isEmpty) return;

    final labelTag = event.tags.firstWhere(
      (t) => t.length >= 3 && t[0] == 'l' && t[2] == labelNamespace,
      orElse: () => [],
    );
    if (labelTag.isEmpty) return;
    final label = labelTag[1];

    final emailTag = event.tags.firstWhere(
      (t) => t.isNotEmpty && t[0] == 'e',
      orElse: () => [],
    );
    if (emailTag.isEmpty) return;
    final emailId = emailTag[1];

    if (await _labels.hasLabel(emailId, label, recipientPubkey: pubkey)) {
      return;
    }

    await _labels.saveLabel(
      emailId: emailId,
      label: label,
      labelEventId: event.id,
      timestamp: event.createdAt,
      recipientPubkey: pubkey,
    );

    _bus.emit(
      LabelAdded(
        emailId: emailId,
        label: label,
        labelEventId: event.id,
        timestamp: DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
      ),
    );
  }

  // ── Gift wrap helpers ───────────────────────────────────────────────────

  Future<UnwrappedGiftWrap?> _unwrapGiftWrap(Nip01Event giftWrapEvent) async {
    try {
      final seal = await _ndk.giftWrap.unwrapEvent(wrappedEvent: giftWrapEvent);
      final rumor = await _ndk.giftWrap.unsealRumor(sealedEvent: seal);
      return UnwrappedGiftWrap(seal: seal, rumor: rumor);
    } on SignerRequestCancelledException {
      rethrow;
    } catch (error) {
      await _giftWraps.recordFailure(
        giftWrapId: giftWrapEvent.id,
        failure: _decryptionFailure(error),
      );
      return null;
    }
  }

  /// A decryption that failed on a key we hold will fail the same way forever.
  /// A remote signer's answer says nothing: NIP-46 carries no error taxonomy,
  /// so a user refusing and a bunker unable to decrypt arrive identically.
  GiftWrapFailure _decryptionFailure(Object error) {
    if (error is FormatException) return GiftWrapFailure.permanent;
    return _ndk.accounts.getLoggedAccount()?.type == AccountType.privateKey
        ? GiftWrapFailure.permanent
        : GiftWrapFailure.signer;
  }
}
