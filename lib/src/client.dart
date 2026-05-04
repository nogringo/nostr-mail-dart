import 'dart:async';

import 'package:enough_mail_plus/enough_mail.dart' hide MailEvent;
import 'package:ndk/ndk.dart' hide Filter;
import 'package:ndk/domain_layer/entities/filter.dart' as ndk;
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

  final Map<String, String>? nip05Overrides;

  factory NostrMailClient({
    required Ndk ndk,
    required Database db,
    List<String>? defaultDmRelays,
    List<String>? defaultBlossomServers,
    Map<String, String>? nip05Overrides,
  }) {
    final emailRepo = EmailRepository(db);
    final labelRepo = LabelRepository(db);
    final giftWrapRepo = GiftWrapRepository(db);
    final settingsRepo = SettingsRepository(db);
    final bus = EventBus();

    final relayResolver = RelayResolver(ndk, defaultDmRelays: defaultDmRelays);
    final settingsManager = SettingsManager(ndk, settingsRepo, relayResolver);
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
        defaultBlossomServers: defaultBlossomServers,
        nip05Overrides: nip05Overrides,
      ),
      labels: LabelManager(ndk, labelRepo, relayResolver, bus),
      settings: settingsManager,
      sync: syncEngine,
      watch: WatchManager(ndk, syncEngine, bus, relayResolver),
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
       _watch = watch;

  // ── Reading ─────────────────────────────────────────────────────────────

  Future<List<Email>> getEmails({int? limit, int? offset}) async {
    final result = await _emailRepo.query(
      EmailQuery(limit: limit, offset: offset),
    );
    return result.items.map((r) => r.toEmail()).toList();
  }

  Future<Email?> getEmail(String id) async {
    final record = await _emailRepo.getById(id);
    return record?.toEmail();
  }

  Future<List<Email>> search(String query, {int? limit, int? offset}) async {
    final result = await _emailRepo.query(
      EmailQuery(search: query, limit: limit, offset: offset),
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
      EmailQuery.sent(limit: limit, offset: offset),
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
      EmailQuery.inbox(limit: limit, offset: offset),
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
    final result = await _emailRepo.query(const EmailQuery.trash());
    return result.items.map((r) => r.toEmail()).toList();
  }

  Future<List<Email>> getTrashedEmailsOlderThan(Duration duration) async {
    final cutoff = DateTime.now().subtract(duration);
    final ids = await _labelRepo.getEmailIdsWithLabelOlderThan(
      'folder:trash',
      cutoff,
    );
    final records = await _emailRepo.getByIds(ids);
    return records.map((r) => r.toEmail()).toList();
  }

  Future<List<Email>> getArchivedEmails() async {
    final result = await _emailRepo.query(const EmailQuery.archive());
    return result.items.map((r) => r.toEmail()).toList();
  }

  Future<List<Email>> getStarredEmails() async {
    final result = await _emailRepo.query(const EmailQuery(isStarred: true));
    return result.items.map((r) => r.toEmail()).toList();
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

    final email = await _emailRepo.getById(id);
    if (email == null) {
      throw NostrMailException('Email not found');
    }

    final dmRelays = await _getDmRelays(pubkey);

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
    final broadcast = _ndk.broadcast.broadcast(
      nostrEvent: signed,
      specificRelays: dmRelays,
    );
    await broadcast.broadcastDoneFuture;

    await _emailRepo.delete(id);
    await _labelRepo.deleteLabelsForEmail(id);
    await _giftWrapRepo.remove(id);
  }

  // ── Repost ──────────────────────────────────────────────────────────────

  Future<void> repost(Nip01Event emailEvent) async {
    final pubkey = _ndk.accounts.getPublicKey();
    if (pubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }

    final writeRelays = await _getWriteRelays(pubkey);

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

    final emailBroadcast = _ndk.broadcast.broadcast(
      nostrEvent: emailEvent,
      specificRelays: writeRelays,
    );
    final repostBroadcast = _ndk.broadcast.broadcast(
      nostrEvent: signedRepost,
      specificRelays: writeRelays,
    );

    await Future.wait([
      emailBroadcast.broadcastDoneFuture,
      repostBroadcast.broadcastDoneFuture,
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

  // ── Relay helpers (duplicated — kept for delete / repost) ───────────────

  Future<List<String>> _getDmRelays(String pubkey) async {
    final response = _ndk.requests.query(
      filter: ndk.Filter(kinds: [dmRelayListKind], authors: [pubkey], limit: 1),
    );
    final events = await response.future;
    if (events.isEmpty) return recommendedDmRelays;

    final event = events.reduce((a, b) => a.createdAt > b.createdAt ? a : b);
    final relays = event.tags
        .where((t) => t.isNotEmpty && t[0] == 'relay')
        .map((t) => t[1])
        .toList();
    return relays.isNotEmpty ? relays : recommendedDmRelays;
  }

  Future<List<String>> _getWriteRelays(String pubkey) async {
    final response = _ndk.requests.query(
      filter: ndk.Filter(kinds: [relayListKind], authors: [pubkey], limit: 1),
    );
    final events = await response.future;
    if (events.isEmpty) return recommendedDmRelays;

    final event = events.reduce((a, b) => a.createdAt > b.createdAt ? a : b);
    final relays = event.tags
        .where(
          (t) =>
              t.isNotEmpty &&
              t[0] == 'r' &&
              (t.length == 2 || (t.length == 3 && t[2] != 'read')),
        )
        .map((t) => t[1])
        .toList();
    return relays.isNotEmpty ? relays : recommendedDmRelays;
  }
}
