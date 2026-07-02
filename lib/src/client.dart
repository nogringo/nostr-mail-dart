import 'dart:async';

import 'package:blossom_cache/blossom_cache.dart';
import 'package:blossom_upload_queue_shim_for_ndk/blossom_upload_queue_shim_for_ndk.dart';
import 'package:broadcast_queue_shim_for_ndk/broadcast_queue_shim_for_ndk.dart';
import 'package:enough_mail_plus/enough_mail.dart' hide MailEvent;
import 'package:ndk/ndk.dart';
import 'package:nostr_event_scheduler/nostr_event_scheduler.dart';
import 'package:rxdart/rxdart.dart';
import 'package:sembast/sembast.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'client/email_sender.dart';
import 'client/event_bus.dart';
import 'client/label_manager.dart';
import 'client/settings_manager.dart';
import 'client/sync_engine.dart';
import 'client/watch_manager.dart';
import 'client/relay_resolver.dart';
import 'client/schedule_manager.dart';
import 'constants.dart';
import 'exceptions.dart';
import 'models/attachment_ref.dart';
import 'models/email.dart';
import 'models/mail_event.dart';
import 'models/private_settings.dart';
import 'models/recipient.dart';
import 'models/scheduled_email.dart';

import 'storage/email_repository.dart';
import 'storage/gift_wrap_repository.dart';
import 'storage/label_repository.dart';
import 'storage/schema_migrator.dart';
import 'storage/settings_repository.dart';
import 'storage/tombstone_repository.dart';
import 'storage/models/email_query.dart';
import 'utils/attachment_extractor.dart';
import 'utils/blob_fetcher.dart';
import 'utils/decrypt_blob.dart';

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
  final TombstoneRepository _tombstoneRepo;
  final EventBus _bus;
  final EmailSender _sender;
  final LabelManager _labels;
  final SettingsManager _settings;
  final SyncEngine _sync;
  final WatchManager _watch;
  final ScheduleManager _schedule;

  /// Direct access to the offline broadcast queue. Use this to surface
  /// pending broadcasts in the UI (`watchPending()`), inspect history
  /// (`listAll()`), or force a retry pass (`retryNow()`).
  ///
  /// When the client was constructed without an explicit queue, it owns
  /// this instance and disposes it as part of [dispose]. When you pass
  /// your own queue to [create], its lifecycle is yours to manage.
  final OfflineBroadcast broadcastQueue;
  final bool _ownsBroadcastQueue;

  /// Direct access to the offline Blossom upload queue. Use this to surface
  /// pending blob uploads in the UI (`watchPending()`), inspect history
  /// (`listAll()`), or force a retry pass (`retryNow()`).
  ///
  /// When the client was constructed without an explicit queue, it owns
  /// this instance and disposes it as part of [dispose]. When you pass
  /// your own queue to [create], its lifecycle is yours to manage.
  final OfflineBlossomUpload blossomUploadQueue;
  final bool _ownsBlossomUploadQueue;

  final RelayResolver _relayResolver;

  final BlossomCache _blossomCache;

  final List<String>? _defaultBlossomServers;

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
  ///
  /// [blossomCache] is the local blob store that holds the encrypted bytes
  /// of large emails until every Blossom server has acked the upload. The
  /// caller picks the backend that matches their platform
  /// (`IdbBlossomCache.open(factory: idbFactoryBrowser)` on web,
  /// `idbFactorySembastIo` on native, `newIdbFactoryMemory()` in tests).
  /// The SDK does not own this cache: it will not be closed by [dispose].
  ///
  /// Pass [blossomUploadQueue] to share an upload queue across SDKs, tune
  /// its parameters, or inject a custom one in tests. Same lifecycle rules
  /// as [broadcastQueue]: when you provide it, you own it; when null, the
  /// client instantiates and starts an internal
  /// `OfflineBlossomUpload.withNdk(ndk, cache: blossomCache, db: db)` and
  /// disposes it as part of [dispose].
  static Future<NostrMailClient> create({
    required Ndk ndk,
    required Database db,
    required BlossomCache blossomCache,
    List<String>? defaultDmRelays,
    List<String>? defaultBlossomServers,
    Map<String, String>? nip05Overrides,
    OfflineBroadcast? broadcastQueue,
    OfflineBlossomUpload? blossomUploadQueue,
    String? schedulerDvm,
    List<String>? schedulerDvmReadRelays,
  }) async {
    await migrateSchemaIfNeeded(db: db, ndk: ndk);
    final emailRepo = EmailRepository(db);
    final labelRepo = LabelRepository(db);
    final giftWrapRepo = GiftWrapRepository(db);
    final settingsRepo = SettingsRepository(db);
    final tombstoneRepo = TombstoneRepository(db);
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

    final OfflineBlossomUpload blossomQueue;
    final bool ownsBlossomQueue;
    if (blossomUploadQueue != null) {
      blossomQueue = blossomUploadQueue;
      ownsBlossomQueue = false;
    } else {
      blossomQueue = OfflineBlossomUpload.withNdk(
        ndk,
        cache: blossomCache,
        db: db,
      );
      blossomQueue.start();
      ownsBlossomQueue = true;
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
      tombstoneRepo,
      bus,
      relayResolver,
      defaultBlossomServers: defaultBlossomServers,
      blossomCache: blossomCache,
    );

    // Prime the in-memory settings cache from local storage so the sync
    // getter `cachedPrivateSettings` is ready right after `create()` returns.
    // Without this, callers observe `null` until the first async local read,
    // which races with auth-state listeners that fire before this client
    // is constructed.
    if (ndk.accounts.isLoggedIn) {
      await settingsManager.getPrivateSettings();
    }

    final emailSender = EmailSender(
      ndk,
      settingsManager,
      relayResolver,
      queue,
      blossomQueue,
      blossomCache,
      emailRepo,
      defaultBlossomServers: defaultBlossomServers,
      nip05Overrides: nip05Overrides,
    );

    final scheduleManager = ScheduleManager(
      EventScheduler(ndk: ndk, broadcast: queue, db: db),
      emailSender,
      defaultDvm: schedulerDvm,
      dvmReadRelays: schedulerDvmReadRelays,
    );

    return NostrMailClient._internal(
      ndk: ndk,
      emailRepo: emailRepo,
      labelRepo: labelRepo,
      giftWrapRepo: giftWrapRepo,
      settingsRepo: settingsRepo,
      tombstoneRepo: tombstoneRepo,
      bus: bus,
      blossomCache: blossomCache,
      defaultBlossomServers: defaultBlossomServers,
      sender: emailSender,
      schedule: scheduleManager,
      labels: LabelManager(
        ndk,
        labelRepo,
        tombstoneRepo,
        relayResolver,
        bus,
        queue,
      ),
      settings: settingsManager,
      sync: syncEngine,
      watch: WatchManager(ndk, syncEngine, bus, relayResolver),
      broadcastQueue: queue,
      ownsBroadcastQueue: ownsQueue,
      blossomUploadQueue: blossomQueue,
      ownsBlossomUploadQueue: ownsBlossomQueue,
      relayResolver: relayResolver,
      nip05Overrides: nip05Overrides,
    );
  }

  NostrMailClient._internal({
    required this._ndk,
    required this._emailRepo,
    required this._labelRepo,
    required this._giftWrapRepo,
    required this._settingsRepo,
    required this._tombstoneRepo,
    required this._bus,
    required this._blossomCache,
    required this._sender,
    required this._labels,
    required this._settings,
    required this._sync,
    required this._watch,
    required this._schedule,
    required this.broadcastQueue,
    required this._ownsBroadcastQueue,
    required this.blossomUploadQueue,
    required this._ownsBlossomUploadQueue,
    required this._relayResolver,
    this._defaultBlossomServers,
    this.nip05Overrides,
  });

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

  // ── Attachments and raw MIME ────────────────────────────────────────────

  /// Load the decoded bytes for one of [email]'s attachments.
  ///
  /// Fast path: the bytes live in [BlossomCache] under [AttachmentRef.sha256],
  /// where attachment extraction stored them at sync time.
  ///
  /// Slow path (cache miss, e.g. after LRU eviction): the original full MIME
  /// is reconstructed (decrypted from the source-of-truth Blossom blob, or
  /// read from the local rumor for inline emails) and every attachment is
  /// re-extracted into the cache. The requested bytes are then served from
  /// the cache.
  ///
  /// Returns `null` if the bytes cannot be recovered, e.g. the source-of-
  /// truth blob has been evicted *and* never re-downloaded.
  Future<Uint8List?> getAttachmentBytes(Email email, AttachmentRef ref) async {
    final cached = await _blossomCache.get(ref.sha256);
    if (cached != null) return cached;

    final fullMime = await _reconstructFullMimeText(email);
    if (fullMime == null) return null;

    final mime = MimeMessage.parseFromText(fullMime);
    await extractAttachments(mime: mime, cache: _blossomCache);

    return _blossomCache.get(ref.sha256);
  }

  /// Reconstruct [email]'s original RFC 2822 MIME string with every
  /// attachment body restored.
  ///
  /// Used for `.eml` export, replies that include the full quoted message,
  /// or any consumer flow that needs byte-exact original content. Returns
  /// `null` if the source data is unavailable locally (Blossom blob evicted
  /// without re-download, or inline rumor missing from `gift_wraps`).
  Future<String?> getRawMimeText(Email email) =>
      _reconstructFullMimeText(email);

  /// Convenience over [getRawMimeText] that returns the parsed MIME message.
  Future<MimeMessage?> getRawMime(Email email) async {
    final text = await _reconstructFullMimeText(email);
    if (text == null) return null;
    return MimeMessage.parseFromText(text);
  }

  Future<String?> _reconstructFullMimeText(Email email) async {
    final hash = email.blossomHash;
    if (hash != null) {
      final key = email.decryptionKey;
      final nonce = email.decryptionNonce;
      if (key == null || nonce == null) return null;
      final serverUrls = await resolveBlobServers(
        ndk: _ndk,
        pubkeys: [email.senderPubkey, email.recipientPubkey],
        defaultBlossomServers: _defaultBlossomServers,
      );
      final encrypted = await fetchOrLoadEncryptedBlob(
        blossomHash: hash,
        serverUrls: serverUrls,
        cache: _blossomCache,
        ndk: _ndk,
      );
      final decrypted = await decryptBlob(
        encryptedBytes: encrypted,
        key: key,
        nonce: nonce,
      );
      return utf8.decode(decrypted);
    }

    // Inline email: the original MIME lives in the rumor's `content`.
    final record = await _giftWrapRepo.getByRumorId(email.id);
    if (record == null || record['rumor'] == null) return null;
    final rumor = Nip01EventModel.fromJson(record['rumor'] as Map);
    final content = rumor.content;
    return content.isEmpty ? null : content;
  }

  // ── Deletion ────────────────────────────────────────────────────────────

  /// Delete emails locally and publish one batched NIP-09 request.
  ///
  /// All [ids] must exist for the active account. The deletion request is
  /// signed before local state is mutated; after signing, local emails,
  /// labels, gift-wrap cache entries and tombstones are updated in batch.
  Future<void> delete(Iterable<String> ids) async {
    final pubkey = _ndk.accounts.getPublicKey();
    if (pubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }

    final uniqueIds = ids.toSet().toList();
    if (uniqueIds.isEmpty) return;

    final emails = await _emailRepo.getByIds(
      uniqueIds,
      recipientPubkey: pubkey,
    );
    if (emails.length != uniqueIds.length) {
      final foundIds = emails.map((e) => e.id).toSet();
      final missingIds = uniqueIds.where((id) => !foundIds.contains(id));
      if (uniqueIds.length == 1) {
        throw NostrMailException('Email not found');
      }
      throw NostrMailException('Emails not found: ${missingIds.join(', ')}');
    }

    final labelEventIds = await _labelRepo.getLabelEventIdsForEmails(
      uniqueIds,
      recipientPubkey: pubkey,
    );

    final deletionIds = [...uniqueIds, ...labelEventIds];
    final targetKinds = emails
        .map((email) => email.isPublic ? emailKind : giftWrapKind)
        .toSet();
    if (labelEventIds.isNotEmpty) {
      targetKinds.add(labelKind);
    }
    final deletionEvent = Nip01Event(
      pubKey: pubkey,
      kind: deletionRequestKind,
      tags: [
        ...deletionIds.map((id) => ['e', id]),
        ...targetKinds.map((kind) => ['k', kind.toString()]),
      ],
      content: '',
    );

    final signed = await _ndk.accounts.sign(deletionEvent);

    // Local-first: remove from local storage immediately, then enqueue the
    // deletion request for durable broadcast. The queue persists the event
    // before any network attempt and retries until every targeted relay has
    // acked.
    await Future.wait([
      _tombstoneRepo.addMany(deletionIds, recipientPubkey: pubkey),
      _emailRepo.deleteByIds(uniqueIds, recipientPubkey: pubkey),
      _labelRepo.deleteLabelsForEmails(uniqueIds, recipientPubkey: pubkey),
      _giftWrapRepo.removeByRumorIds(uniqueIds),
    ]);

    for (final id in uniqueIds) {
      _bus.emit(EmailDeleted(emailId: id));
    }

    final relayLookups = <Future<List<String>>>[
      if (emails.any((email) => !email.isPublic))
        _relayResolver.getDmRelays(pubkey),
      if (emails.any((email) => email.isPublic) || labelEventIds.isNotEmpty)
        _relayResolver.getWriteRelays(pubkey),
    ];
    final relayLists = await Future.wait(relayLookups);
    final relays = relayLists.expand((relays) => relays).toSet().toList();
    await broadcastQueue.broadcast(signed, relays: relays);
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
    required List<Recipient> to,
    List<Recipient> cc = const [],
    List<Recipient> bcc = const [],
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
    required List<Recipient> to,
    List<Recipient> cc = const [],
    List<Recipient> bcc = const [],
    bool keepCopy = true,
    bool signRumor = false,
    bool isPublic = false,
    String? mailFrom,
  }) => _sender.sendMime(
    message,
    to: to,
    cc: cc,
    bcc: bcc,
    keepCopy: keepCopy,
    signRumor: signRumor,
    isPublic: isPublic,
    mailFrom: mailFrom,
  );

  // ── Scheduling ──────────────────────────────────────────────────────────

  /// Schedule an email to be sent at [at] by a Scheduler DVM. Returns the
  /// created [ScheduledEmail]; cancel it with [cancelScheduledEmail].
  ///
  /// The DVM is [dvmPubkey] or the `schedulerDvm` configured in [create], and
  /// throws when neither is set. The email is not saved to Sent now: it lands
  /// there through the normal sync once the DVM publishes at [at].
  Future<ScheduledEmail> scheduleEmail({
    required List<Recipient> to,
    List<Recipient> cc = const [],
    List<Recipient> bcc = const [],
    required String subject,
    required String body,
    MailAddress? from,
    String? htmlBody,
    bool keepCopy = true,
    bool signRumor = false,
    bool isPublic = false,
    required DateTime at,
    String? dvmPubkey,
  }) => _schedule.scheduleEmail(
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
    at: at,
    dvmPubkey: dvmPubkey,
  );

  /// Schedule a pre-built [message]. See [scheduleEmail].
  Future<ScheduledEmail> scheduleMime(
    MimeMessage message, {
    required List<Recipient> to,
    List<Recipient> cc = const [],
    List<Recipient> bcc = const [],
    bool keepCopy = true,
    bool signRumor = false,
    bool isPublic = false,
    String? mailFrom,
    required DateTime at,
    String? dvmPubkey,
  }) => _schedule.scheduleMime(
    message,
    to: to,
    cc: cc,
    bcc: bcc,
    keepCopy: keepCopy,
    signRumor: signRumor,
    isPublic: isPublic,
    mailFrom: mailFrom,
    at: at,
    dvmPubkey: dvmPubkey,
  );

  /// All scheduled (not-yet-sent) emails, newest first.
  Future<List<ScheduledEmail>> getScheduledEmails() => _schedule.list();

  /// Reactive [getScheduledEmails]: re-emits on schedule, cancel, or DVM
  /// feedback. Call [startScheduling] to receive live DVM feedback and
  /// multi-device updates.
  Stream<List<ScheduledEmail>> watchScheduledEmails() => _schedule.watch();

  /// Cancel a scheduled email by its package id so the DVM never sends it.
  Future<void> cancelScheduledEmail(String packageId) =>
      _schedule.cancel(packageId);

  /// Force a one-shot network resync of scheduled emails, cancellations and
  /// DVM status feedback. Updates the local store; [watchScheduledEmails]
  /// re-emits with the result.
  Future<void> resyncScheduledEmails() => _schedule.resync();

  /// Start listening for DVM feedback and multi-device schedule sync. Requires
  /// a logged-in account. Scheduling, listing and cancelling work without it
  /// (local-first); this only adds live status updates. Idempotent.
  Future<void> startScheduling() => _schedule.startListening();

  /// Stop the [startScheduling] subscriptions. Local scheduling still works.
  Future<void> stopScheduling() => _schedule.stopListening();

  // ── Private Settings ────────────────────────────────────────────────────

  PrivateSettings? get cachedPrivateSettings => _settings.cachedPrivateSettings;

  Future<PrivateSettings?> getPrivateSettings() =>
      _settings.getPrivateSettings();

  Future<PrivateSettings?> fetchPrivateSettings() =>
      _settings.fetchPrivateSettings();

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
      _tombstoneRepo.clearAll(),
    ]);
    _settings.clearCache();
  }

  /// Stops background workers and, if this client owns either of the
  /// internal queues, disposes them and waits for any in-flight attempt
  /// to finish. Call before closing the underlying sembast database and
  /// Blossom cache.
  ///
  /// When a queue was passed to [create] explicitly, the caller owns its
  /// lifecycle and must dispose it themselves. The Blossom cache is never
  /// owned by the client.
  Future<void> dispose() async {
    stopWatching();
    await _schedule.dispose();
    if (_ownsBroadcastQueue) {
      await broadcastQueue.dispose();
    }
    if (_ownsBlossomUploadQueue) {
      await blossomUploadQueue.dispose();
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

  // ── Blossom upload queue ────────────────────────────────────────────────

  /// Waits until every queued Blossom upload has been acknowledged by every
  /// targeted server, or until [timeout] elapses. Useful in tests and in
  /// suspend handlers that want to ensure delivery before going idle.
  ///
  /// Throws [TimeoutException] if delivery is still incomplete when
  /// [timeout] expires.
  Future<void> flushBlossomUploads({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final all = await blossomUploadQueue.listAll();
      final undelivered = all.where((u) => u.deliveredAt == null).toList();
      if (undelivered.isEmpty) return;
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException(
          'flushBlossomUploads timed out with ${undelivered.length} '
          'undelivered upload(s)',
          timeout,
        );
      }
      await blossomUploadQueue.retryNow();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}
