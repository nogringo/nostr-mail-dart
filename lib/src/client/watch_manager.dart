import 'package:ndk/ndk.dart';
import 'package:ndk/domain_layer/entities/filter.dart' as ndk;

import '../constants.dart';
import '../exceptions.dart';
import '../models/mail_event.dart';
import 'event_bus.dart';
import 'relay_resolver.dart';
import 'sync_engine.dart';

/// Manages real-time Nostr subscriptions and routes incoming events
/// to the [SyncEngine] for processing.
class WatchManager {
  final Ndk _ndk;
  final SyncEngine _sync;
  final EventBus _bus;
  final RelayResolver _relays;

  WatchManager(this._ndk, this._sync, this._bus, this._relays);

  String? get _pubkey => _ndk.accounts.getPublicKey();

  /// Start watching and return the broadcast stream of [MailEvent]s.
  Stream<MailEvent> watch() {
    if (_bus.isActive) return _bus.stream;

    final pubkey = _pubkey;
    if (pubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }

    // Ensure the stream exists
    _bus.stream;

    _setupSubscriptions(pubkey);
    return _bus.stream;
  }

  /// Stop all subscriptions and close the event bus.
  void stopWatching() => _bus.close();

  // ── Stream helpers ──────────────────────────────────────────────────────

  Stream<MailEvent> get onLabel =>
      _bus.stream.where((e) => e is LabelAdded || e is LabelRemoved);

  Stream<MailEvent> get onTrash =>
      onLabel.where((e) => _getLabelFromEvent(e) == 'folder:trash');

  Stream<MailEvent> get onRead =>
      onLabel.where((e) => _getLabelFromEvent(e) == 'state:read');

  Stream<MailEvent> get onStarred =>
      onLabel.where((e) => _getLabelFromEvent(e) == 'flag:starred');

  String? _getLabelFromEvent(MailEvent e) {
    if (e is LabelAdded) return e.label;
    if (e is LabelRemoved) return e.label;
    return null;
  }

  // ── Subscriptions ───────────────────────────────────────────────────────

  Future<void> _setupSubscriptions(String pubkey) async {
    final dmRelays = await _relays.getDmRelays(pubkey);
    final writeRelays = await _relays.getWriteRelays(pubkey);

    // Gift wraps (emails)
    final emailSub = _ndk.requests.subscription(
      filter: ndk.Filter(
        kinds: [GiftWrap.kGiftWrapEventkind],
        pTags: [pubkey],
        limit: 0,
      ),
      explicitRelays: dmRelays,
    );

    // Public emails
    final publicSub = _ndk.requests.subscription(
      filter: ndk.Filter(kinds: [emailKind], pTags: [pubkey], limit: 0),
      explicitRelays: writeRelays,
    );

    // Label additions
    final labelSub = _ndk.requests.subscription(
      filter: ndk.Filter(kinds: [labelKind], authors: [pubkey], limit: 0),
      explicitRelays: writeRelays,
    );

    // Label deletions
    final labelDeletionFilter = ndk.Filter(
      kinds: [deletionRequestKind],
      authors: [pubkey],
      limit: 0,
    )..setTag('k', [labelKind.toString()]);
    final labelDeletionSub = _ndk.requests.subscription(
      filter: labelDeletionFilter,
      explicitRelays: writeRelays,
    );

    // Email deletions
    final emailDeletionFilter = ndk.Filter(
      kinds: [deletionRequestKind],
      authors: [pubkey],
      limit: 0,
    )..setTag('k', [giftWrapKind.toString()]);
    final emailDeletionSub = _ndk.requests.subscription(
      filter: emailDeletionFilter,
      explicitRelays: dmRelays,
    );

    emailSub.stream.listen(_sync.onGiftWrap);
    publicSub.stream.listen(_sync.onPublicEmail);
    labelSub.stream.listen(_sync.onLabelAddition);
    labelDeletionSub.stream.listen(_sync.onLabelDeletion);
    emailDeletionSub.stream.listen(_sync.onEmailDeletion);
  }
}
