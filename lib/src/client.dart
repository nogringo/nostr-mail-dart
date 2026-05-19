import 'dart:async';

import 'package:broadcast_queue_shim_for_ndk/broadcast_queue_shim_for_ndk.dart';
import 'package:enough_mail_plus/enough_mail.dart' hide MailEvent;
import 'package:ndk/ndk.dart';
import 'package:rxdart/rxdart.dart';
import 'package:sembast/sembast.dart';

import 'client/email_sender.dart';
import 'client/event_bus.dart';
import 'client/label_manager.dart';
import 'client/settings_manager.dart';
import 'client/sync_engine.dart';
import 'client/watch_manager.dart';
import 'client/relay_resolver.dart';
import 'constants.dart';
import 'exceptions.dart';
import 'models/email.dart';
import 'models/mail_event.dart';
import 'models/private_settings.dart';

import 'storage/email_repository.dart';
import 'storage/gift_wrap_repository.dart';
import 'storage/label_repository.dart';
import 'storage/schema_migrator.dart';
import 'storage/settings_repository.dart';
import 'storage/models/email_query.dart';

/// Main entry-point for the nostr_mail SDK.
///
/// This is a thin façade that delegates to specialized internal managers.
/// The public API surface is kept fully backward-compatible.
class NostrMailClient {
  final Ndk _ndk;
  final EmailRepository _emailRepo;
  final LabelRepository _labelRepo;
  final GiftWrapRepository _giftWrapRepo;
  final SettingsRepository _settingsRepo;
  final EmailSender _sender;
  final LabelManager _labels;
  final SettingsManager _settings;
  final SyncEngine _sync;
  final WatchManager _watch;

  /// Direct access to the offline broadcast queue. Use this to surface
  /// pending broadcasts in the UI (`watchPending()`), inspect history
  /// (`listAll()`), or force a retry pass (`retryNow()`).
  ///
  /// When the client was constructed without an explicit queue, it owns
  /// this instance and disposes it as part of [dispose]. When you pass
  /// your own queue to [create], its lifecycle is yours to manage.
  final OfflineBroadcast broadcastQueue;
  final bool _ownsBroadcastQueue;

  final RelayResolver _relayResolver;

  final Map<String, String>? nip05Overrides;

  /// Build a [NostrMailClient] after running any pending schema migration.
  ///
  /// This is the only supported entry point. The migration is fast (a single
  /// drop per store + ndk fetched-ranges clear) and runs automatically on
  /// every version mismatch so the caller cannot accidentally read records in
  /// a stale format.
  ///
  /// Pass [broadcastQueue] to share a single queue across SDKs, tune its
  /// parameters, or inject a custom one in tests. When you provide your own
  /// queue, you also own its lifecycle: call `.start()` yourself before
  /// `create()` (or before the first send) and `.dispose()` when you no
  /// longer need it. When [broadcastQueue] is null, the client instantiates
  /// and starts an internal `OfflineBroadcast.withNdk(ndk, db: db)`, and
  /// `NostrMailClient.dispose()` disposes it.
  static Future<NostrMailClient> create({
    required Ndk ndk,
    required Database db,
    List<String>? defaultDmRelays,
    List<String>? defaultBlossomServers,
    Map<String, String>? nip05Overrides,
    OfflineBroadcast? broadcastQueue,
  }) async {
    await migrateSchemaIfNeeded(db: db, ndk: ndk);
    final emailRepo = EmailRepository(db);
    final labelRepo = LabelRepository(db);
    final giftWrapRepo = GiftWrapRepository(db);
    final settingsRepo = SettingsRepository(db);
    final bus = EventBus();

    final relayResolver = RelayResolver(ndk, defaultDmRelays: defaultDmRelays);
    final OfflineBroadcast queue;
    final bool ownsQueue;
    if (broadcastQueue != null) {
      queue = broadcastQueue;
      ownsQueue = false;
    } else {
      queue = OfflineBroadcast.withNdk(ndk, db: db);
      queue.start();
      ownsQueue = true;
    }

    final settingsManager = SettingsManager(
      ndk,
      settingsRepo,
      relayResolver,
      queue,
    );
    final syncEngine = SyncEngine(
      ndk,
      emailRepo,
      labelRepo,
      giftWrapRepo,
      bus,
      relayResolver,
      defaultBlossomServers: defaultBlossomServers,
    );

    return NostrMailClient._internal(
      ndk: ndk,
      emailRepo: emailRepo,
      labelRepo: labelRepo,
      giftWrapRepo: giftWrapRepo,
      settingsRepo: settingsRepo,
      sender: EmailSender(
        ndk,
        settingsManager,
        relayResolver,
        queue,
        emailRepo,
        defaultBlossomServers: defaultBlossomServers,
        nip05Overrides: nip05Overrides,
      ),
      labels: LabelManager(ndk, labelRepo, relayResolver, bus, queue),
      settings: settingsManager,
      sync: syncEngine,
      watch: WatchManager(ndk, syncEngine, bus, relayResolver),
      broadcastQueue: queue,
      ownsBroadcastQueue: ownsQueue,
      relayResolver: relayResolver,
      nip05Overrides: nip05Overrides,
    );
  }

  NostrMailClient._internal({
    required Ndk ndk,
    required EmailRepository emailRepo,
    required LabelRepository labelRepo,
    required GiftWrapRepository giftWrapRepo,
    required SettingsRepository settingsRepo,
    required EmailSender sender,
    required LabelManager labels,
    required SettingsManager settings,
    required SyncEngine sync,
    required WatchManager watch,
    required this.broadcastQueue,
    required bool ownsBroadcastQueue,
    required RelayResolver relayResolver,
    this.nip05Overrides,
  }) : _ndk = ndk,
       _emailRepo = emailRepo,
       _labelRepo = labelRepo,
       _giftWrapRepo = giftWrapRepo,
       _settingsRepo = settingsRepo,
       _sender = sender,
       _labels = labels,
       _settings = settings,
       _sync = sync,
       _watch = watch,
       _ownsBroadcastQueue = ownsBroadcastQueue,
       _relayResolver = relayResolver;

  // ── Reading ─────────────────────────────────────────────────────────────

  String _requirePubkey() {
    final pk = _ndk.accounts.getPublicKey();
    if (pk == null) {
      throw NostrMailException('No account configured in ndk');
    }
    return pk;
  }

  Future<List<Email>> getEmails({int? limit, int? offset}) async {
    final result = await _emailRepo.query(
      EmailQuery(
        recipientPubkey: _requirePubkey(),
        limit: limit,
        offset: offset,
      ),
    );
    return result.items.map((r) => r.toEmail()).toList();
  }

  Future<Email?> getEmail(String id) async {
    final record = await _emailRepo.getById(
      id,
      recipientPubkey: _requirePubkey(),
    );
    return record?.toEmail();
  }

  Future<List<Email>> search(String query, {int? limit, int? offset}) async {
    final result = await _emailRepo.query(
      EmailQuery(
        recipientPubkey: _requirePubkey(),
        search: query,
        limit: limit,
        offset: offset,
      ),
    );
    return result.items.map((r) => r.toEmail()).toList();
  }

  Future<List<Email>> getSentEmails({
    int? limit,
    int? offset,
    bool includeTrashed = false,
    bool includeArchived = false,
  }) async {
    final result = await _emailRepo.query(
      EmailQuery.sent(
        recipientPubkey: _requirePubkey(),
        limit: limit,
        offset: offset,
      ),
    );
    if (includeTrashed && includeArchived) {
      return result.items.map((r) => r.toEmail()).toList();
    }
    return result.items
        .where((r) {
          if (!includeTrashed && r.folder == 'trash') return false;
          if (!includeArchived && r.folder == 'archive') return false;
          return true;
        })
        .map((r) => r.toEmail())
        .toList();
  }

  Future<List<Email>> getInboxEmails({
    int? limit,
    int? offset,
    bool includeTrashed = false,
    bool includeArchived = false,
  }) async {
    final result = await _emailRepo.query(
      EmailQuery.inbox(
        recipientPubkey: _requirePubkey(),
        limit: limit,
        offset: offset,
      ),
    );
    if (includeTrashed && includeArchived) {
      return result.items.map((r) => r.toEmail()).toList();
    }
    return result.items
        .where((r) {
          if (!includeTrashed && r.folder == 'trash') return false;
          if (!includeArchived && r.folder == 'archive') return false;
          return true;
        })
        .map((r) => r.toEmail())
        .toList();
  }

  Future<List<Email>> getTrashedEmails() async {
    final result = await _emailRepo.query(
      EmailQuery.trash(recipientPubkey: _requirePubkey()),
    );
    return result.items.map((r) => r.toEmail()).toList();
  }

  Future<List<Email>> getTrashedEmailsOlderThan(Duration duration) async {
    final pubkey = _requirePubkey();
    final cutoff = DateTime.now().subtract(duration);
    final ids = await _labelRepo.getEmailIdsWithLabelOlderThan(
      'folder:trash',
      cutoff,
      recipientPubkey: pubkey,
    );
    final records = await _emailRepo.getByIds(ids, recipientPubkey: pubkey);
    return records.map((r) => r.toEmail()).toList();
  }

  Future<List<Email>> getArchivedEmails() async {
    final result = await _emailRepo.query(
      EmailQuery.archive(recipientPubkey: _requirePubkey()),
    );
    return result.items.map((r) => r.toEmail()).toList();
  }

  Future<List<Email>> getStarredEmails() async {
    final result = await _emailRepo.query(
      EmailQuery(recipientPubkey: _requirePubkey(), isStarred: true),
    );
    return result.items.map((r) => r.toEmail()).toList();
  }

  // ── Counts ──────────────────────────────────────────────────────────────

  /// Number of unread emails, optionally scoped to a [folder]
  /// (`'inbox'`, `'archive'`, `'sent'`, `'trash'`, ...).
  /// Pass `null` to count across all folders.
  Future<int> getUnreadCount({String? folder}) {
    return _emailRepo.count(
      EmailQuery(
        recipientPubkey: _requirePubkey(),
        folder: folder,
        isRead: false,
      ),
    );
  }

  /// Reactive stream of [getUnreadCount] for [folder].
  ///
  /// Emits the current value immediately, then re-emits whenever the count
  /// may have changed (new email received, mark as read/unread, folder
  /// change, deletion). Ideal for driving a folder badge with
  /// `StreamBuilder`.
  Stream<int> watchUnreadCount({String? folder}) {
    return Rx.defer(() {
      return Rx.merge<Object?>([
            Stream.value(null),
            _watch.events
                .where(
                  (e) =>
                      e is EmailReceived ||
                      e is LabelAdded ||
                      e is LabelRemoved ||
                      e is EmailDeleted,
                )
                .debounceTime(const Duration(milliseconds: 50)),
          ])
          .switchMap((_) => Stream.fromFuture(getUnreadCount(folder: folder)))
          .distinct();
    }, reusable: true);
  }

  // ── NIP-59 Introspection ────────────────────────────────────────────────

  Future<Nip01Event?> getGiftWrap(String emailId) async {
    final record = await _giftWrapRepo.getByRumorId(emailId);
    if (record == null) return null;
    return Nip01EventModel.fromJson(record['event'] as Map);
  }

  Future<Nip01Event?> getSeal(String emailId) async {
    final record = await _giftWrapRepo.getByRumorId(emailId);
    if (record == null || record['seal'] == null) return null;
    return Nip01EventModel.fromJson(record['seal'] as Map);
  }

  Future<Nip01Event?> getRumor(String emailId) async {
    final record = await _giftWrapRepo.getByRumorId(emailId);
    if (record == null || record['rumor'] == null) return null;
    return Nip01EventModel.fromJson(record['rumor'] as Map);
  }

  // ── Deletion ────────────────────────────────────────────────────────────

  Future<void> delete(String id) async {
    final pubkey = _ndk.accounts.getPublicKey();
    if (pubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }

    final email = await _emailRepo.getById(id, recipientPubkey: pubkey);
    if (email == null) {
      throw NostrMailException('Email not found');
    }

    final deletionEvent = Nip01Event(
      pubKey: pubkey,
      kind: deletionRequestKind,
      tags: [
        ['e', email.id],
        ['k', giftWrapKind.toString()],
      ],
      content: '',
    );

    final signed = await _ndk.accounts.sign(deletionEvent);

    // Local-first: remove from local storage immediately, then enqueue the
    // deletion request for durable broadcast. The queue persists the event
    // before any network attempt and retries until every DM relay has acked.
    await _emailRepo.delete(id, recipientPubkey: pubkey);
    await _labelRepo.deleteLabelsForEmail(id, recipientPubkey: pubkey);
    await _giftWrapRepo.remove(id);

    final dmRelays = await _relayResolver.getDmRelays(pubkey);
    await broadcastQueue.broadcast(signed, relays: dmRelays);
  }

  // ── Repost ──────────────────────────────────────────────────────────────

  Future<void> repost(Nip01Event emailEvent) async {
    final pubkey = _ndk.accounts.getPublicKey();
    if (pubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }

    final writeRelays = await _relayResolver.getWriteRelays(pubkey);

    final tags = <List<String>>[
      ['e', emailEvent.id],
      ['p', emailEvent.pubKey],
      ['k', emailKind.toString()],
      ...writeRelays.map((r) => ['r', r]),
    ];

    final repostEvent = Nip01Event(
      pubKey: pubkey,
      kind: genericRepostKind,
      tags: tags,
      content: Nip01EventModel.fromEntity(emailEvent).toJsonString(),
    );

    final signedRepost = await _ndk.accounts.sign(repostEvent);

    await Future.wait([
      broadcastQueue.broadcast(emailEvent, relays: writeRelays),
      broadcastQueue.broadcast(signedRepost, relays: writeRelays),
    ]);
  }

  // ── Labels ──────────────────────────────────────────────────────────────

  Future<void> addLabel(String emailId, String label) =>
      _labels.addLabel(emailId, label);

  Future<void> removeLabel(String emailId, String label) =>
      _labels.removeLabel(emailId, label);

  Future<List<String>> getLabels(String emailId) => _labels.getLabels(emailId);

  Future<bool> hasLabel(String emailId, String label) =>
      _labels.hasLabel(emailId, label);

  Future<void> moveToTrash(String emailId) => _labels.moveToTrash(emailId);
  Future<void> restoreFromTrash(String emailId) =>
      _labels.restoreFromTrash(emailId);
  Future<void> moveToArchive(String emailId) => _labels.moveToArchive(emailId);
  Future<void> restoreFromArchive(String emailId) =>
      _labels.restoreFromArchive(emailId);
  Future<void> markAsRead(String emailId) => _labels.markAsRead(emailId);
  Future<void> markAsUnread(String emailId) => _labels.markAsUnread(emailId);
  Future<void> star(String emailId) => _labels.star(emailId);
  Future<void> unstar(String emailId) => _labels.unstar(emailId);

  Future<bool> isTrashed(String emailId) => _labels.isTrashed(emailId);
  Future<bool> isArchived(String emailId) => _labels.isArchived(emailId);
  Future<bool> isRead(String emailId) => _labels.isRead(emailId);
  Future<bool> isStarred(String emailId) => _labels.isStarred(emailId);

  Future<List<String>> getTrashedEmailIds() => _labels.getTrashedEmailIds();
  Future<List<String>> getArchivedEmailIds() => _labels.getArchivedEmailIds();
  Future<List<String>> getStarredEmailIds() => _labels.getStarredEmailIds();
  Future<List<String>> getReadEmailIds() => _labels.getReadEmailIds();

  // ── Watch ───────────────────────────────────────────────────────────────

  Stream<MailEvent> watch() => _watch.watch();
  void stopWatching() => _watch.stopWatching();

  Stream<Email> get onEmail => watch()
      .where((e) => e is EmailReceived)
      .cast<EmailReceived>()
      .map((e) => e.email);

  Stream<MailEvent> get onLabel => _watch.onLabel;
  Stream<MailEvent> get onTrash => _watch.onTrash;
  Stream<MailEvent> get onRead => _watch.onRead;
  Stream<MailEvent> get onStarred => _watch.onStarred;

  // ── Sync ────────────────────────────────────────────────────────────────

  Future<void> sync({int? since, int? until}) =>
      _sync.sync(since: since, until: until);
  Future<void> resync({int? since, int? until}) =>
      _sync.resync(since: since, until: until);
  Future<void> fetchRecent() => _sync.fetchRecent();

  Future<bool> retry(String eventId) => _sync.retry(eventId);
  Future<int> getFailedCount() => _sync.getFailedCount();
  Future<List<Nip01Event>> getFailedEvents() => _sync.getFailedEvents();

  // ── Sending ─────────────────────────────────────────────────────────────

  Future<void> send({
    required List<MailAddress> to,
    List<MailAddress>? cc,
    List<MailAddress>? bcc,
    required String subject,
    required String body,
    MailAddress? from,
    String? htmlBody,
    bool keepCopy = true,
    bool signRumor = false,
    bool isPublic = false,
  }) => _sender.send(
    to: to,
    cc: cc,
    bcc: bcc,
    subject: subject,
    body: body,
    from: from,
    htmlBody: htmlBody,
    keepCopy: keepCopy,
    signRumor: signRumor,
    isPublic: isPublic,
  );

  Future<void> sendMime(
    MimeMessage message, {
    bool keepCopy = true,
    bool signRumor = false,
    bool isPublic = false,
    String? mailFrom,
  }) => _sender.sendMime(
    message,
    keepCopy: keepCopy,
    signRumor: signRumor,
    isPublic: isPublic,
    mailFrom: mailFrom,
  );

  // ── Private Settings ────────────────────────────────────────────────────

  PrivateSettings? get cachedPrivateSettings => _settings.cachedPrivateSettings;

  Future<PrivateSettings?> getCachedPrivateSettings() =>
      _settings.getCachedPrivateSettings();

  Future<PrivateSettings?> getPrivateSettings() =>
      _settings.getPrivateSettings();

  Future<void> setPrivateSettings(PrivateSettings settings) =>
      _settings.setPrivateSettings(settings);

  Future<void> updatePrivateSettings({
    String? signature,
    List<String>? bridges,
    List<MailAddress>? identities,
    bool clearSignature = false,
    bool clearBridges = false,
    bool clearIdentities = false,
  }) => _settings.updatePrivateSettings(
    signature: signature,
    bridges: bridges,
    identities: identities,
    clearSignature: clearSignature,
    clearBridges: clearBridges,
    clearIdentities: clearIdentities,
  );

  // ── Lifecycle ───────────────────────────────────────────────────────────

  Future<void> clearAll() async {
    await Future.wait([
      _emailRepo.clearAll(),
      _labelRepo.clearAll(),
      _giftWrapRepo.clearAll(),
      _settingsRepo.clear(),
    ]);
    _settings.clearCache();
  }

  /// Stops background workers and, if this client owns the broadcast queue,
  /// disposes it and waits for any in-flight attempt to finish. Call before
  /// closing the underlying sembast database.
  ///
  /// When a queue was passed to [create] explicitly, the caller owns its
  /// lifecycle and must dispose it themselves.
  Future<void> dispose() async {
    stopWatching();
    if (_ownsBroadcastQueue) {
      await broadcastQueue.dispose();
    }
  }

  // ── Broadcast queue ─────────────────────────────────────────────────────

  /// Waits until every queued broadcast has been acknowledged by every
  /// targeted relay, or until [timeout] elapses. Useful in tests and in
  /// suspend handlers that want to ensure delivery before going idle.
  ///
  /// Throws [TimeoutException] if delivery is still incomplete when
  /// [timeout] expires.
  Future<void> flushBroadcasts({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final all = await broadcastQueue.listAll();
      final undelivered = all.where((b) => b.deliveredAt == null).toList();
      if (undelivered.isEmpty) return;
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException(
          'flushBroadcasts timed out with ${undelivered.length} undelivered '
          'broadcast(s)',
          timeout,
        );
      }
      await broadcastQueue.retryNow();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}
