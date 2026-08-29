import 'package:blossom_cache/blossom_cache.dart';
import 'package:ndk/ndk.dart';
import 'package:sync_engine_shim_for_ndk/sync_engine_shim_for_ndk.dart';

import '../constants.dart';
import '../exceptions.dart';
import '../models/mail_event.dart';
import '../models/unwrapped_gift_wrap.dart';
import '../storage/email_repository.dart';
import '../storage/gift_wrap_repository.dart';
import '../storage/label_repository.dart';
import '../storage/tombstone_repository.dart';
import '../utils/email_record_builder.dart';
import 'relay_resolver.dart';
import '../utils/event_email_parser.dart';
import 'event_bus.dart';
import 'filters.dart';

/// Orchestrates inbound synchronization from Nostr relays.
///
/// The [SyncEngine] shim keeps the NDK cache filled with everything this
/// account needs; the cache is then the source of truth for raw events, and
/// the local sembast stores are a projection of it rebuilt by
/// [_processFromCache]. An event whose processing fails therefore stays in the
/// cache and is retried on the next sync.
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

  /// Brings the NDK cache up to date, then rebuilds the local stores from it.
  ///
  /// Only what the sync engine considers missing or stale is fetched, so this
  /// is cheap to call repeatedly. Nothing bounds how far back it reaches: a
  /// mailbox is wanted whole, so the engine walks back until every relay has
  /// nothing older, once, and remembers it.
  Future<void> sync() async {
    _assertPubkey();
    final handles = await _ensureHandles();
    await Future.wait(handles.map(_awaitSynced));
    await _processFromCache();
  }

  /// Goes to the relays now, however fresh the coverage is, then rebuilds the
  /// local stores. This is the pull-to-refresh gesture.
  Future<void> resync() async {
    _assertPubkey();
    final handles = await _ensureHandles();
    await Future.wait(handles.map(_engine.refresh));
    await _processFromCache();
  }

  /// Alias of [resync] kept for backward compatibility.
  Future<void> fetchRecent() => resync();

  /// Drops this client's interest in its sync requests. The coverage the
  /// engine persisted survives; the engine itself belongs to the caller and is
  /// never started, stopped or disposed from here.
  void releaseHandles() {
    for (final handle in _handles.values) {
      _engine.release(handle);
    }
    _handles.clear();
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
      _ensure('emails', [emailFilter(pubkey)], dmRelays),
      _ensure('deletions', [deletionFilter(pubkey)], allRelays),
      _ensure('write', [
        publicEmailFilter(pubkey),
        labelFilter(pubkey),
        repostFilter(pubkey),
        settingsFilter(pubkey),
        metadataFilter(pubkey),
      ], writeRelays),
    ];
  }

  /// The engine derives the request identity from the filters and the relay
  /// set, both of which move here: switching account rewrites the filters, and
  /// [RelayResolver] hands back the fallback list until the kind 10050 lands.
  /// A hand-written id would pin whichever it saw first.
  SyncHandle _ensure(String scope, List<Filter> filters, List<String> relays) {
    final handle = _engine.ensure(
      SyncRequest(filters: filters, relays: relays),
    );

    final held = _handles[scope];
    if (held == handle) {
      // ensure() counts one more holder per call; a scope only ever holds one.
      _engine.release(handle);
    } else {
      if (held != null) _engine.release(held);
      _handles[scope] = handle;
    }

    return handle;
  }

  Future<void> _awaitSynced(SyncHandle handle) async {
    if (_engine.engineStatus.phase == SyncEnginePhase.stopped) return;

    await _engine
        .watchStatus(handle)
        .firstWhere(
          (status) =>
              status.phase == SyncRequestPhase.synced ||
              status.phase == SyncRequestPhase.failed,
        );
  }

  // ── Cache processing ────────────────────────────────────────────────────

  /// Rebuilds the local stores from the NDK cache. Every handler is idempotent,
  /// so replaying the whole cache only costs a lookup per already-known event.
  Future<void> _processFromCache() async {
    final pubkey = _pubkey;
    if (pubkey == null) return;

    // Gift wraps and public emails run in parallel: NDK PR #632 added
    // configurable signer concurrency (default 100), so decryption no longer
    // blocks sequentially. Deletions and labels stay sequential to avoid races.
    await Future.wait((await _fromCache(emailFilter(pubkey))).map(onGiftWrap));

    for (final event in await _fromCache(deletionFilter(pubkey))) {
      await onDeletion(event);
    }

    await Future.wait(
      (await _fromCache(publicEmailFilter(pubkey))).map(onPublicEmail),
    );

    for (final event in await _fromCache(labelFilter(pubkey))) {
      await onLabelAddition(event);
    }
  }

  Future<List<Nip01Event>> _fromCache(Filter filter) =>
      _ndk.config.cache.loadEvents(
        ids: filter.ids,
        pubKeys: filter.authors,
        kinds: filter.kinds,
        tags: filter.tags,
        since: filter.since,
        until: filter.until,
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

  Future<List<Nip01Event>> getFailedEvents() {
    final pubkey = _pubkey;
    if (pubkey == null) return Future.value(const []);
    return _giftWraps.getUnprocessedEvents(recipientPubkey: pubkey);
  }

  // ── Event processing ────────────────────────────────────────────────────

  Future<void> onGiftWrap(Nip01Event event) async {
    final owner = event.getFirstTag('p');
    if (owner == null || !_ndk.accounts.hasAccount(owner)) return;

    // Stored under the wrap's own recipient, not the active account, so one
    // arriving mid account-switch stays retryable instead of being dropped.
    final isNew = await _giftWraps.save(event, recipientPubkey: owner);
    if (!isNew || owner != _pubkey) return;
    await _processEvent(event);
  }

  Future<bool> _processEvent(Nip01Event event) async {
    final myPubkey = _pubkey;
    if (myPubkey == null) return false;

    final recipientTag = event.getFirstTag('p');
    if (recipientTag != myPubkey) return false;

    try {
      final unwrapped = await _unwrapGiftWrap(event);
      if (unwrapped == null) return false;

      final rumor = unwrapped.rumor;
      final seal = unwrapped.seal;

      if (rumor.kind != emailKind) {
        await _giftWraps.updateDecrypted(
          giftWrapId: event.id,
          seal: seal,
          rumor: rumor,
        );
        return false;
      }

      final isPublicRef = rumor.getFirstTag('public-ref') != null;

      // Skip emails the user already deleted locally. Gift wraps can be
      // re-served by relays that ignore NIP-09, while the tombstone is keyed
      // by the user-facing email id (the rumor id).
      if (await _tombstones.contains(rumor.id, recipientPubkey: myPubkey)) {
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

      final folder = email.senderPubkey == myPubkey ? 'sent' : 'inbox';
      final record = buildEmailRecord(email: email, folder: folder);

      await _emails.save(record);
      await _giftWraps.updateDecrypted(
        giftWrapId: event.id,
        seal: seal,
        rumor: rumor,
      );

      _bus.emit(EmailReceived(email: email, timestamp: email.date));
      return true;
    } on SignerRequestCancelledException {
      rethrow;
    } on SignerRequestRejectedException {
      await _giftWraps.markProcessed(event.id);
      return false;
    } catch (_) {
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

      final folder = email.senderPubkey == recipientPubkey ? 'sent' : 'inbox';
      final record = buildEmailRecord(email: email, folder: folder);

      await _emails.save(record);
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
          if (labelRecord['labelEventId'] == deletedEventId) {
            final emailId = labelRecord['emailId'] as String;
            final label = labelRecord['label'] as String;
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
    } on SignerRequestRejectedException {
      rethrow;
    } catch (_) {
      return null;
    }
  }
}
