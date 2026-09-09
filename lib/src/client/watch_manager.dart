import 'dart:async';

import 'package:ndk/ndk.dart';

import '../exceptions.dart';
import '../models/mail_event.dart';
import 'event_bus.dart';
import 'filters.dart';
import 'relay_resolver.dart';
import 'mail_sync.dart';

/// Manages real-time Nostr subscriptions and routes incoming events
/// to the [MailSync] for processing.
class WatchManager {
  final Ndk _ndk;
  final MailSync _sync;
  final EventBus _bus;
  final RelayResolver _relays;

  WatchManager(this._ndk, this._sync, this._bus, this._relays);

  String? get _pubkey => _ndk.accounts.getPublicKey();

  /// The open subscriptions, by ndk request id, held until the account changes
  /// or [stopWatching] is called.
  final List<String> _requestIds = [];

  /// The account [_requestIds] were opened for, null while nothing is watched.
  String? _watched;

  StreamSubscription<Account?>? _account;

  /// Bumped on every teardown. A setup still resolving its relays, and an
  /// event still in flight on a closed subscription, both carry the generation
  /// they were opened under, and are dropped once it is over.
  int _generation = 0;

  /// Start watching and return the broadcast stream of [MailEvent]s.
  Stream<MailEvent> watch() {
    final pubkey = _pubkey;
    if (pubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }

    // Ensure the stream exists
    _bus.stream;

    _followActiveAccount();
    _redraw(pubkey);

    return _bus.stream;
  }

  /// Stop all subscriptions and close the event bus.
  void stopWatching() {
    _account?.cancel().ignore();
    _account = null;
    _closeSubscriptions();
    _bus.close();
  }

  // ── Stream helpers ──────────────────────────────────────────────────────

  /// All mail events from the internal bus, including those emitted by
  /// local actions (e.g. [LabelManager.markAsRead]) regardless of whether
  /// network subscriptions have been started via [watch].
  Stream<MailEvent> get events => _bus.stream;

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

  /// Follows the active account: every filter is drawn from its pubkey, so a
  /// login, a switch or a logout has to redraw the subscriptions. Without this
  /// the account left behind keeps its own open, and what they bring in is
  /// processed under whoever is logged in now.
  void _followActiveAccount() {
    _account ??= _ndk.accounts.authStateChanges.listen((_) => _redraw(_pubkey));
  }

  void _redraw(String? pubkey) {
    if (_watched == pubkey) return;
    _closeSubscriptions();
    if (pubkey == null) return;
    _watched = pubkey;
    _setupSubscriptions(pubkey, _generation).ignore();
  }

  void _closeSubscriptions() {
    _generation++;
    for (final requestId in _requestIds) {
      _ndk.requests.closeSubscription(requestId).ignore();
    }
    _requestIds.clear();
    _watched = null;
  }

  Future<void> _setupSubscriptions(String pubkey, int generation) async {
    final (dmRelays, writeRelays) = await (
      _relays.getDmRelays(pubkey),
      _relays.getWriteRelays(pubkey),
    ).wait;
    if (generation != _generation) return;
    final allRelays = {...dmRelays, ...writeRelays}.toList();

    // Gift wraps (emails)
    _open(
      _ndk.requests.subscription(
        filter: emailFilter(pubkey)..limit = 0,
        explicitRelays: dmRelays,
        cacheWrite: true,
      ),
      generation,
      process: _sync.onGiftWrap,
    );

    // Public emails
    _open(
      _ndk.requests.subscription(
        filter: publicEmailFilter(pubkey)..limit = 0,
        explicitRelays: writeRelays,
        cacheWrite: true,
      ),
      generation,
      process: _sync.onPublicEmail,
    );

    // Label additions
    _open(
      _ndk.requests.subscription(
        filter: labelFilter(pubkey)..limit = 0,
        explicitRelays: writeRelays,
        cacheWrite: true,
      ),
      generation,
      process: _sync.onLabelAddition,
    );

    // Unified deletions (emails, labels, reposts)
    _open(
      _ndk.requests.subscription(
        filter: deletionFilter(pubkey)..limit = 0,
        explicitRelays: allRelays,
        cacheWrite: true,
      ),
      generation,
      process: _sync.onDeletion,
    );

    // Reposts
    _open(
      _ndk.requests.subscription(
        filter: repostFilter(pubkey)..limit = 0,
        explicitRelays: writeRelays,
        cacheWrite: true,
      ),
      generation,
    );

    // Private settings
    _open(
      _ndk.requests.subscription(
        filter: settingsFilter(pubkey)..limit = 0,
        explicitRelays: writeRelays,
        cacheWrite: true,
      ),
      generation,
    );

    // Metadata & relay lists
    _open(
      _ndk.requests.subscription(
        filter: metadataFilter(pubkey)..limit = 0,
        explicitRelays: writeRelays,
        cacheWrite: true,
      ),
      generation,
    );
  }

  /// Holds [subscription] so it can be closed, and routes what it brings to
  /// [process]. A subscription with nothing to process is still listened to:
  /// an unlistened stream never runs, and these ones fill the NDK cache.
  void _open(
    NdkResponse subscription,
    int generation, {
    Future<void> Function(Nip01Event)? process,
  }) {
    _requestIds.add(subscription.requestId);
    subscription.stream.listen((event) {
      // Closing is asynchronous, and the handlers store under the account that
      // is active now: an event arriving late would land in its mailbox.
      if (generation != _generation) return;
      process?.call(event).ignore();
    });
  }
}
