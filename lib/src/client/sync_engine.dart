import 'package:blossom_cache/blossom_cache.dart';
import 'package:ndk/ndk.dart';
import 'package:ndk/domain_layer/entities/filter.dart' as ndk;

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
import 'gap_sync.dart';

/// Orchestrates inbound synchronization from Nostr relays.
///
/// Uses [GapSync] to avoid re-downloading already-synced time ranges.
class SyncEngine {
  final Ndk _ndk;
  final EmailRepository _emails;
  final LabelRepository _labels;
  final GiftWrapRepository _giftWraps;
  final TombstoneRepository _tombstones;
  final EventBus _bus;
  final RelayResolver _relays;
  final List<String> _defaultBlossomServers;
  final BlossomCache _blossomCache;

  SyncEngine(
    this._ndk,
    this._emails,
    this._labels,
    this._giftWraps,
    this._tombstones,
    this._bus,
    this._relays, {
    required BlossomCache blossomCache,
    List<String>? defaultBlossomServers,
  }) : _defaultBlossomServers =
           defaultBlossomServers ?? recommendedBlossomServers,
       _blossomCache = blossomCache;

  String? get _pubkey => _ndk.accounts.getPublicKey();

  void _assertPubkey() {
    if (_pubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }
  }

  // ── Public API ──────────────────────────────────────────────────────────

  /// Incremental sync using gap optimization.
  Future<void> sync({int? since, int? until}) async {
    _assertPubkey();
    final pubkey = _pubkey!;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final effectiveSince = since;
    final effectiveUntil = until ?? now;

    final (dmRelays, writeRelays) = await (
      _relays.getDmRelays(pubkey),
      _relays.getWriteRelays(pubkey),
    ).wait;

    final allRelays = {...dmRelays, ...writeRelays}.toList();

    await _EmailGapSync(
      _ndk,
      pubkey,
      dmRelays,
      effectiveSince,
      effectiveUntil,
      onGiftWrap,
    ).execute();

    await _DeletionGapSync(
      _ndk,
      pubkey,
      allRelays,
      effectiveSince,
      effectiveUntil,
      onDeletion,
    ).execute();

    await _PublicEmailGapSync(
      _ndk,
      pubkey,
      writeRelays,
      effectiveSince,
      effectiveUntil,
      onPublicEmail,
    ).execute();

    await _LabelAdditionGapSync(
      _ndk,
      pubkey,
      writeRelays,
      effectiveSince,
      effectiveUntil,
      onLabelAddition,
    ).execute();

    await _PassiveGapSync(
      _ndk,
      pubkey,
      writeRelays,
      effectiveSince,
      effectiveUntil,
      repostFilter,
    ).execute();

    await _PassiveGapSync(
      _ndk,
      pubkey,
      writeRelays,
      effectiveSince,
      effectiveUntil,
      settingsFilter,
    ).execute();

    await _PassiveGapSync(
      _ndk,
      pubkey,
      writeRelays,
      effectiveSince,
      effectiveUntil,
      metadataFilter,
    ).execute();
  }

  /// Full sync after clearing cached fetched ranges.
  Future<void> resync({int? since, int? until}) async {
    _assertPubkey();
    final pubkey = _pubkey!;

    await Future.wait([
      _ndk.fetchedRanges.clearForFilter(emailFilter(pubkey)),
      _ndk.fetchedRanges.clearForFilter(deletionFilter(pubkey)),
      _ndk.fetchedRanges.clearForFilter(publicEmailFilter(pubkey)),
      _ndk.fetchedRanges.clearForFilter(labelFilter(pubkey)),
      _ndk.fetchedRanges.clearForFilter(repostFilter(pubkey)),
      _ndk.fetchedRanges.clearForFilter(settingsFilter(pubkey)),
      _ndk.fetchedRanges.clearForFilter(metadataFilter(pubkey)),
    ]);

    await sync(since: since, until: until);
  }

  /// Fetch all events without gap optimization.
  Future<void> fetchRecent() async {
    _assertPubkey();
    final pubkey = _pubkey!;

    final (dmRelays, writeRelays) = await (
      _relays.getDmRelays(pubkey),
      _relays.getWriteRelays(pubkey),
    ).wait;

    final allRelays = {...dmRelays, ...writeRelays}.toList();

    // Fetch all filters in parallel; process sequentially to avoid races.
    final (emails, deletions, publicEmails, labelAdditions, _, _, _) = await (
      _fetchEvents(emailFilter(pubkey), dmRelays),
      _fetchEvents(deletionFilter(pubkey), allRelays),
      _fetchEvents(publicEmailFilter(pubkey), writeRelays),
      _fetchEvents(labelFilter(pubkey), writeRelays),
      _fetchEvents(repostFilter(pubkey), writeRelays),
      _fetchEvents(settingsFilter(pubkey), writeRelays),
      _fetchEvents(metadataFilter(pubkey), writeRelays),
    ).wait;

    // Process all event types in parallel where safe.
    // NDK PR #632 added configurable signer concurrency (default 100),
    // so gift-wrap decryption no longer blocks sequentially.
    await Future.wait(emails.map(onGiftWrap));
    await Future.wait(deletions.map(onDeletion));
    await Future.wait(publicEmails.map(onPublicEmail));
    await Future.wait(labelAdditions.map(onLabelAddition));
  }

  /// Retry processing a single failed gift wrap.
  Future<bool> retry(String eventId) async {
    final event = await _giftWraps.getUnprocessed(eventId);
    if (event == null) return false;
    return _processEvent(event);
  }

  Future<int> getFailedCount() => _giftWraps.getFailedCount();
  Future<List<Nip01Event>> getFailedEvents() =>
      _giftWraps.getUnprocessedEvents();

  // ── Event processing ────────────────────────────────────────────────────

  Future<void> onGiftWrap(Nip01Event event) async {
    final isNew = await _giftWraps.save(event);
    if (!isNew) return;
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
          await _giftWraps.removeByRumorIds([deletedEventId]);
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

  Future<List<Nip01Event>> _fetchEvents(
    ndk.Filter filter,
    List<String> relays,
  ) async {
    final response = _ndk.requests.query(
      filter: filter,
      explicitRelays: relays,
    );
    return response.future;
  }
}

// ── Concrete GapSync implementations ──────────────────────────────────────

class _EmailGapSync extends GapSync<Nip01Event> {
  final Future<void> Function(Nip01Event) _processor;

  _EmailGapSync(
    super._ndk,
    super._pubkey,
    super._relays,
    super._since,
    super._until,
    this._processor,
  );

  @override
  ndk.Filter buildFilter(String pubkey) => emailFilter(pubkey);

  @override
  Future<List<Nip01Event>> fetch(ndk.Filter filter, List<String> relays) {
    final response = ndkClient.requests.query(
      filter: filter,
      explicitRelays: relays,
    );
    return response.future;
  }

  @override
  Future<void> process(Nip01Event item) => _processor(item);

  @override
  Future<void> processBatch(List<Nip01Event> items) async {
    await Future.wait(items.map(process));
  }
}

class _DeletionGapSync extends GapSync<Nip01Event> {
  final Future<void> Function(Nip01Event) _processor;

  _DeletionGapSync(
    super._ndk,
    super._pubkey,
    super._relays,
    super._since,
    super._until,
    this._processor,
  );

  @override
  ndk.Filter buildFilter(String pubkey) => deletionFilter(pubkey);

  @override
  Future<List<Nip01Event>> fetch(ndk.Filter filter, List<String> relays) {
    final response = ndkClient.requests.query(
      filter: filter,
      explicitRelays: relays,
    );
    return response.future;
  }

  @override
  Future<void> process(Nip01Event item) => _processor(item);
}

class _PublicEmailGapSync extends GapSync<Nip01Event> {
  final Future<void> Function(Nip01Event) _processor;

  _PublicEmailGapSync(
    super._ndk,
    super._pubkey,
    super._relays,
    super._since,
    super._until,
    this._processor,
  );

  @override
  ndk.Filter buildFilter(String pubkey) => publicEmailFilter(pubkey);

  @override
  Future<List<Nip01Event>> fetch(ndk.Filter filter, List<String> relays) {
    final response = ndkClient.requests.query(
      filter: filter,
      explicitRelays: relays,
    );
    return response.future;
  }

  @override
  Future<void> process(Nip01Event item) => _processor(item);
}

class _LabelAdditionGapSync extends GapSync<Nip01Event> {
  final Future<void> Function(Nip01Event) _processor;

  _LabelAdditionGapSync(
    super._ndk,
    super._pubkey,
    super._relays,
    super._since,
    super._until,
    this._processor,
  );

  @override
  ndk.Filter buildFilter(String pubkey) => labelFilter(pubkey);

  @override
  Future<List<Nip01Event>> fetch(ndk.Filter filter, List<String> relays) {
    final response = ndkClient.requests.query(
      filter: filter,
      explicitRelays: relays,
    );
    return response.future;
  }

  @override
  Future<void> process(Nip01Event item) => _processor(item);
}

/// Fetches events only to warm the NDK cache; no local processing.
class _PassiveGapSync extends GapSync<Nip01Event> {
  final ndk.Filter Function(String) _filterBuilder;

  _PassiveGapSync(
    super._ndk,
    super._pubkey,
    super._relays,
    super._since,
    super._until,
    this._filterBuilder,
  );

  @override
  ndk.Filter buildFilter(String pubkey) => _filterBuilder(pubkey);

  @override
  Future<List<Nip01Event>> fetch(ndk.Filter filter, List<String> relays) {
    final response = ndkClient.requests.query(
      filter: filter,
      explicitRelays: relays,
    );
    return response.future;
  }

  @override
  Future<void> process(Nip01Event item) async {
    // No-op: events are only fetched to warm the NDK cache.
  }
}
