import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_mail_plus/enough_mail.dart' hide MailEvent;
import 'package:ndk/ndk.dart' hide Filter;
import 'package:ndk/domain_layer/entities/filter.dart' as ndk;
import 'package:sembast/sembast.dart';

import 'constants.dart';
import 'exceptions.dart';
import 'models/email.dart';
import 'models/mail_event.dart';
import 'models/private_settings.dart';
import 'models/unwrapped_gift_wrap.dart';
import 'services/email_parser.dart';
import 'storage/email_store.dart';
import 'storage/gift_wrap_store.dart';
import 'storage/label_store.dart';
import 'storage/private_settings_store.dart';
import 'utils/recipient_resolver.dart';
import 'utils/encrypt_blob.dart';
import 'utils/event_email_parser.dart';
import 'utils/mime_message_cleaner.dart';

class NostrMailClient {
  final Ndk _ndk;
  final EmailStore _store;
  final LabelStore _labelStore;
  final GiftWrapStore _giftWrapStore;
  final EmailParser _parser;
  final PrivateSettingsStore _settingsStore;
  final List<String> _defaultDmRelays;
  final List<String> _defaultBlossomServers;
  final Map<String, String>? nip05Overrides;

  /// Cached broadcast stream for watch()
  StreamController<MailEvent>? _watchController;
  Stream<MailEvent>? _watchBroadcastStream;

  /// In-memory cache for private settings keyed by pubkey.
  /// Avoids repeated relay queries and signer decrypts.
  final Map<String, PrivateSettings?> _cachedPrivateSettings = {};

  NostrMailClient({
    required Ndk ndk,
    required Database db,
    List<String>? defaultDmRelays,
    List<String>? defaultBlossomServers,
    this.nip05Overrides,
  }) : _ndk = ndk,
       _store = EmailStore(db),
       _labelStore = LabelStore(db),
       _giftWrapStore = GiftWrapStore(db),
       _settingsStore = PrivateSettingsStore(db),
       _parser = EmailParser(),
       _defaultDmRelays = defaultDmRelays ?? recommendedDmRelays,
       _defaultBlossomServers =
           defaultBlossomServers ?? recommendedBlossomServers;

  /// Get cached emails from local DB
  Future<List<Email>> getEmails({int? limit, int? offset}) {
    return _store.getEmails(limit: limit, offset: offset);
  }

  /// Get single email by ID
  Future<Email?> getEmail(String id) {
    return _store.getEmailById(id);
  }

  /// Get the original NIP-59 Gift Wrap event (kind 1059) for an email.
  Future<Nip01Event?> getGiftWrap(String emailId) async {
    final record = await _giftWrapStore.getByRumorId(emailId);
    if (record == null) return null;
    return Nip01EventModel.fromJson(record['event'] as Map);
  }

  /// Get the NIP-59 Seal event (kind 13) for an email.
  Future<Nip01Event?> getSeal(String emailId) async {
    final record = await _giftWrapStore.getByRumorId(emailId);
    if (record == null || record['seal'] == null) return null;
    return Nip01EventModel.fromJson(record['seal'] as Map);
  }

  /// Get the original Rumor event (kind 1301) for an email.
  Future<Nip01Event?> getRumor(String emailId) async {
    final record = await _giftWrapStore.getByRumorId(emailId);
    if (record == null || record['rumor'] == null) return null;
    return Nip01EventModel.fromJson(record['rumor'] as Map);
  }

  /// Search emails by query (subject, body, or sender) from local DB
  Future<List<Email>> search(String query, {int? limit, int? offset}) async {
    return _store.searchEmails(query, limit: limit, offset: offset);
  }

  /// Get sent emails from local DB
  ///
  /// By default excludes trashed emails. Set [includeTrashed] to true to include them.
  /// Note: pages may have fewer items if some are trashed.
  Future<List<Email>> getSentEmails({
    int? limit,
    int? offset,
    bool includeTrashed = false,
    bool includeArchived = false,
  }) async {
    final pubkey = _ndk.accounts.getPublicKey();
    if (pubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }
    final emails = await _store.getEmailsBySender(
      pubkey,
      limit: limit,
      offset: offset,
    );
    if (includeTrashed && includeArchived) return emails;
    final trashedIds = await getTrashedEmailIds();
    final archivedIds = await getArchivedEmailIds();
    return emails
        .where((e) => !trashedIds.contains(e.id) && !archivedIds.contains(e.id))
        .toList();
  }

  /// Get inbox emails from local DB (received, excluding sent)
  ///
  /// By default excludes trashed emails. Set [includeTrashed] to true to include them.
  /// Note: pages may have fewer items if some are trashed.
  Future<List<Email>> getInboxEmails({
    int? limit,
    int? offset,
    bool includeTrashed = false,
    bool includeArchived = false,
  }) async {
    final pubkey = _ndk.accounts.getPublicKey();
    if (pubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }
    final emails = await _store.getEmailsByRecipient(
      pubkey,
      limit: limit,
      offset: offset,
    );
    if (includeTrashed && includeArchived) return emails;
    final trashedIds = await getTrashedEmailIds();
    final archivedIds = await getArchivedEmailIds();
    return emails
        .where((e) => !trashedIds.contains(e.id) && !archivedIds.contains(e.id))
        .toList();
  }

  /// Delete email from local DB and request deletion from relays (NIP-09)
  ///
  /// Publishes a kind 5 deletion request event to the user's DM relays.
  /// Per NIP-59, relays should delete kind 1059 events whose p-tag matches
  /// the signer of the deletion request.
  Future<void> delete(String id) async {
    final pubkey = _ndk.accounts.getPublicKey();
    if (pubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }

    // Get the email to find the gift wrap ID
    final email = await _store.getEmailById(id);
    if (email == null) {
      throw NostrMailException('Email not found');
    }

    final dmRelays = await _getDmRelays(pubkey);

    // Create NIP-09 deletion request event
    final deletionEvent = Nip01Event(
      pubKey: pubkey,
      kind: deletionRequestKind,
      tags: [
        ['e', email.id],
        ['k', giftWrapKind.toString()],
      ],
      content: '',
    );

    // Sign and broadcast
    final signedEvent = await _ndk.accounts.sign(deletionEvent);
    final broadcast = _ndk.broadcast.broadcast(
      nostrEvent: signedEvent,
      specificRelays: dmRelays,
    );
    //! long await
    await broadcast.broadcastDoneFuture;

    // Delete from local DB
    await _store.deleteEmail(id);
    await _labelStore.deleteLabelsForEmail(id);
    await _giftWrapStore.remove(id);
  }

  /// Add a label to an email (NIP-32)
  ///
  /// Saves locally and notifies listeners immediately, then broadcasts
  /// to relays in background (local-first).
  ///
  /// For folder: labels, automatically removes other folder: labels
  /// to ensure mutual exclusion (an email can only be in one folder).
  Future<void> addLabel(String emailId, String label) async {
    final pubkey = _ndk.accounts.getPublicKey();
    if (pubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }

    // For folder: labels, remove other folder: labels first (mutual exclusion)
    if (label.startsWith('folder:')) {
      final allLabels = await _labelStore.getLabelsForEmail(emailId);
      for (final existingLabel in allLabels) {
        if (existingLabel.startsWith('folder:') && existingLabel != label) {
          await removeLabel(emailId, existingLabel);
        }
      }
    }

    // Check if label already exists (after removing conflicting folder labels)
    if (await _labelStore.hasLabel(emailId, label)) {
      return;
    }

    // Create NIP-32 label event
    final labelEvent = Nip01Event(
      pubKey: pubkey,
      kind: labelKind,
      tags: [
        ['L', labelNamespace],
        ['l', label, labelNamespace],
        ['e', emailId, '', 'labelled'],
      ],
      content: '',
    );

    // Sign to get event ID
    final signedEvent = await _ndk.accounts.sign(labelEvent);

    // Save locally FIRST
    await _labelStore.saveLabel(
      emailId: emailId,
      label: label,
      labelEventId: signedEvent.id,
    );

    // Notify listeners immediately
    _watchController?.add(
      LabelAdded(emailId: emailId, label: label, labelEventId: signedEvent.id),
    );

    // Broadcast in background (don't await)
    _getWriteRelays(pubkey).then((relays) {
      _ndk.broadcast.broadcast(nostrEvent: signedEvent, specificRelays: relays);
    });
  }

  /// Remove a label from an email
  ///
  /// Removes locally and notifies listeners immediately, then broadcasts
  /// deletion to relays in background (local-first).
  Future<void> removeLabel(String emailId, String label) async {
    final pubkey = _ndk.accounts.getPublicKey();
    if (pubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }

    // Get the label event ID
    final labelEventId = await _labelStore.getLabelEventId(emailId, label);
    if (labelEventId == null) {
      return; // Label doesn't exist
    }

    // Remove locally FIRST
    await _labelStore.removeLabel(emailId, label);

    // Notify listeners immediately
    _watchController?.add(LabelRemoved(emailId: emailId, label: label));

    // Create NIP-09 deletion request
    final deletionEvent = Nip01Event(
      pubKey: pubkey,
      kind: deletionRequestKind,
      tags: [
        ['e', labelEventId],
        ['k', labelKind.toString()],
      ],
      content: '',
    );

    // Broadcast in background (don't await)
    _ndk.accounts.sign(deletionEvent).then((signedEvent) {
      _getWriteRelays(pubkey).then((relays) {
        _ndk.broadcast.broadcast(
          nostrEvent: signedEvent,
          specificRelays: relays,
        );
      });
    });
  }

  /// Get all labels for an email
  Future<List<String>> getLabels(String emailId) {
    return _labelStore.getLabelsForEmail(emailId);
  }

  /// Check if an email has a specific label
  Future<bool> hasLabel(String emailId, String label) {
    return _labelStore.hasLabel(emailId, label);
  }

  /// Move email to trash
  Future<void> moveToTrash(String emailId) => addLabel(emailId, 'folder:trash');

  /// Restore email from trash
  Future<void> restoreFromTrash(String emailId) =>
      removeLabel(emailId, 'folder:trash');

  /// Move email to archive
  Future<void> moveToArchive(String emailId) =>
      addLabel(emailId, 'folder:archive');

  /// Restore email from archive
  Future<void> restoreFromArchive(String emailId) =>
      removeLabel(emailId, 'folder:archive');

  /// Mark email as read
  Future<void> markAsRead(String emailId) => addLabel(emailId, 'state:read');

  /// Mark email as unread
  Future<void> markAsUnread(String emailId) =>
      removeLabel(emailId, 'state:read');

  /// Star an email
  Future<void> star(String emailId) => addLabel(emailId, 'flag:starred');

  /// Unstar an email
  Future<void> unstar(String emailId) => removeLabel(emailId, 'flag:starred');

  /// Check if email is in trash
  Future<bool> isTrashed(String emailId) => hasLabel(emailId, 'folder:trash');

  /// Check if email is archived
  Future<bool> isArchived(String emailId) =>
      hasLabel(emailId, 'folder:archive');

  /// Check if email is read
  Future<bool> isRead(String emailId) => hasLabel(emailId, 'state:read');

  /// Check if email is starred
  Future<bool> isStarred(String emailId) => hasLabel(emailId, 'flag:starred');

  /// Get all trashed email IDs
  Future<List<String>> getTrashedEmailIds() =>
      _labelStore.getEmailIdsWithLabel('folder:trash');

  /// Get all archived email IDs
  Future<List<String>> getArchivedEmailIds() =>
      _labelStore.getEmailIdsWithLabel('folder:archive');

  /// Get all starred email IDs
  Future<List<String>> getStarredEmailIds() =>
      _labelStore.getEmailIdsWithLabel('flag:starred');

  /// Get all read email IDs
  Future<List<String>> getReadEmailIds() =>
      _labelStore.getEmailIdsWithLabel('state:read');

  /// Get all trashed emails (sorted by date descending)
  Future<List<Email>> getTrashedEmails() async {
    final ids = await getTrashedEmailIds();
    return _store.getEmailsByIds(ids);
  }

  /// Get all archived emails (sorted by date descending)
  Future<List<Email>> getArchivedEmails() async {
    final ids = await getArchivedEmailIds();
    return _store.getEmailsByIds(ids);
  }

  /// Get all starred emails (sorted by date descending)
  Future<List<Email>> getStarredEmails() async {
    final ids = await getStarredEmailIds();
    return _store.getEmailsByIds(ids);
  }

  /// Sync labels from relays (internal)
  Future<void> _syncLabels(
    String pubkey,
    List<String> writeRelays,
    int? since,
    int until,
  ) async {
    // Sync label additions
    await _syncLabelAdditions(pubkey, writeRelays, since, until);

    // Sync label deletions
    await _syncLabelDeletions(pubkey, writeRelays, since, until);
  }

  Future<void> _syncLabelAdditions(
    String pubkey,
    List<String> writeRelays,
    int? since,
    int until,
  ) async {
    final baseFilter = _labelFilter(pubkey);

    final existingRanges = await _ndk.fetchedRanges.getForFilter(baseFilter);

    if (existingRanges.isEmpty) {
      final filter = baseFilter.clone()
        ..since = since
        ..until = until;
      final events = await _fetchEvents(filter, writeRelays);
      await _processLabelAdditions(events);
      return;
    }

    final optimizedFilters = await _ndk.fetchedRanges.getOptimizedFilters(
      filter: baseFilter,
      since: since ?? 0,
      until: until,
    );

    if (optimizedFilters.isEmpty) return;

    for (final gapFilter in optimizedFilters.values.expand((f) => f)) {
      final events = await _fetchEvents(gapFilter, writeRelays);
      await _processLabelAdditions(events);
    }
  }

  // TODO: store events in a dedicated store before processing (like gift wraps)
  Future<void> _processLabelAdditions(List<Nip01Event> events) async {
    for (final event in events) {
      // Check if it's a 'mail' namespace label
      final namespaceTag = event.tags.firstWhere(
        (t) => t.isNotEmpty && t[0] == 'L' && t[1] == labelNamespace,
        orElse: () => [],
      );
      if (namespaceTag.isEmpty) continue;

      // Get the label value
      final labelTag = event.tags.firstWhere(
        (t) => t.length >= 3 && t[0] == 'l' && t[2] == labelNamespace,
        orElse: () => [],
      );
      if (labelTag.isEmpty) continue;
      final label = labelTag[1];

      // Get the email ID
      final emailTag = event.tags.firstWhere(
        (t) => t.isNotEmpty && t[0] == 'e',
        orElse: () => [],
      );
      if (emailTag.isEmpty) continue;
      final emailId = emailTag[1];

      // Save to local cache
      await _labelStore.saveLabel(
        emailId: emailId,
        label: label,
        labelEventId: event.id,
      );
    }
  }

  Future<void> _syncLabelDeletions(
    String pubkey,
    List<String> writeRelays,
    int? since,
    int until,
  ) async {
    final baseFilter = _labelDeletionFilter(pubkey);

    final existingRanges = await _ndk.fetchedRanges.getForFilter(baseFilter);

    if (existingRanges.isEmpty) {
      final filter = baseFilter.clone()
        ..since = since
        ..until = until;
      final events = await _fetchEvents(filter, writeRelays);
      await _processLabelDeletions(events);
      return;
    }

    final optimizedFilters = await _ndk.fetchedRanges.getOptimizedFilters(
      filter: baseFilter,
      since: since ?? 0,
      until: until,
    );

    if (optimizedFilters.isEmpty) return;

    for (final gapFilter in optimizedFilters.values.expand((f) => f)) {
      final events = await _fetchEvents(gapFilter, writeRelays);
      await _processLabelDeletions(events);
    }
  }

  // TODO: store events in a dedicated store before processing (like gift wraps)
  Future<void> _processLabelDeletions(List<Nip01Event> events) async {
    for (final event in events) {
      for (final tag in event.tags) {
        if (tag.isNotEmpty && tag[0] == 'e') {
          final deletedEventId = tag[1];

          // Find and remove the label from local store
          final labels = await _labelStore.getAllLabels();
          for (final labelRecord in labels) {
            if (labelRecord['labelEventId'] == deletedEventId) {
              final emailId = labelRecord['emailId'] as String;
              final label = labelRecord['label'] as String;
              await _labelStore.removeLabel(emailId, label);
              break;
            }
          }
        }
      }
    }
  }

  /// Watch for all mail events (emails, labels) in real-time
  ///
  /// Returns a unified stream of [MailEvent] that includes:
  /// - [EmailReceived] when a new email arrives
  /// - [EmailDeleted] when an email is deleted
  /// - [LabelAdded] when a label is added to an email
  /// - [LabelRemoved] when a label is removed from an email
  ///
  /// The stream is shared (broadcast) - multiple listeners share the same
  /// underlying Nostr subscriptions.
  Stream<MailEvent> watch() {
    // Return cached broadcast stream if it exists
    if (_watchBroadcastStream != null) {
      return _watchBroadcastStream!;
    }

    final pubkey = _ndk.accounts.getPublicKey();
    if (pubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }

    _watchController = StreamController<MailEvent>.broadcast();
    _watchBroadcastStream = _watchController!.stream;

    // Setup subscriptions asynchronously
    _setupWatchSubscriptions(pubkey);

    return _watchBroadcastStream!;
  }

  /// Setup Nostr subscriptions for watching
  Future<void> _setupWatchSubscriptions(String pubkey) async {
    // Watch emails on DM relays
    final dmRelays = await _getDmRelays(pubkey);
    final emailResponse = _ndk.requests.subscription(
      filter: ndk.Filter(
        kinds: [GiftWrap.kGiftWrapEventkind],
        pTags: [pubkey],
        limit: 0,
      ),
      explicitRelays: dmRelays,
    );

    // Watch labels on write relays
    final writeRelays = await _getWriteRelays(pubkey);
    final labelResponse = _ndk.requests.subscription(
      filter: ndk.Filter(kinds: [labelKind], authors: [pubkey], limit: 0),
      explicitRelays: writeRelays,
    );

    // Watch label deletions on write relays
    final labelDeletionFilter = ndk.Filter(
      kinds: [deletionRequestKind],
      authors: [pubkey],
      limit: 0,
    )..setTag('k', [labelKind.toString()]);
    final labelDeletionResponse = _ndk.requests.subscription(
      filter: labelDeletionFilter,
      explicitRelays: writeRelays,
    );

    // Watch email deletions on DM relays
    final emailDeletionFilter = ndk.Filter(
      kinds: [deletionRequestKind],
      authors: [pubkey],
      limit: 0,
    )..setTag('k', [giftWrapKind.toString()]);
    final emailDeletionResponse = _ndk.requests.subscription(
      filter: emailDeletionFilter,
      explicitRelays: dmRelays,
    );

    // Watch public emails on write relays
    final publicEmailFilter = ndk.Filter(
      kinds: [emailKind],
      pTags: [pubkey],
      limit: 0,
    );
    final publicEmailResponse = _ndk.requests.subscription(
      filter: publicEmailFilter,
      explicitRelays: writeRelays,
    );

    // Process emails
    emailResponse.stream.listen(_saveAndProcess);

    // Process public emails
    publicEmailResponse.stream.listen((event) async {
      await _processPublicEmail(event);
    });

    // Process label additions
    labelResponse.stream.listen((event) async {
      // Check namespace
      final namespaceTag = event.tags.firstWhere(
        (t) => t.isNotEmpty && t[0] == 'L' && t[1] == labelNamespace,
        orElse: () => [],
      );
      if (namespaceTag.isEmpty) return;

      // Get label value
      final labelTag = event.tags.firstWhere(
        (t) => t.length >= 3 && t[0] == 'l' && t[2] == labelNamespace,
        orElse: () => [],
      );
      if (labelTag.isEmpty) return;
      final label = labelTag[1];

      // Get email ID
      final emailTag = event.tags.firstWhere(
        (t) => t.isNotEmpty && t[0] == 'e',
        orElse: () => [],
      );
      if (emailTag.isEmpty) return;
      final emailId = emailTag[1];

      // Skip if already have this label
      if (await _labelStore.hasLabel(emailId, label)) return;

      // Save locally
      await _labelStore.saveLabel(
        emailId: emailId,
        label: label,
        labelEventId: event.id,
      );

      _watchController?.add(
        LabelAdded(
          emailId: emailId,
          label: label,
          labelEventId: event.id,
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            event.createdAt * 1000,
          ),
        ),
      );
    });

    // Process label deletions
    labelDeletionResponse.stream.listen((event) async {
      for (final tag in event.tags) {
        if (tag.isNotEmpty && tag[0] == 'e') {
          final deletedEventId = tag[1];

          // Find and remove the label from local store
          // We need to find which label this event ID corresponds to
          final labels = await _labelStore.getAllLabels();
          for (final labelRecord in labels) {
            if (labelRecord['labelEventId'] == deletedEventId) {
              final emailId = labelRecord['emailId'] as String;
              final label = labelRecord['label'] as String;

              await _labelStore.removeLabel(emailId, label);

              _watchController?.add(
                LabelRemoved(
                  emailId: emailId,
                  label: label,
                  timestamp: DateTime.fromMillisecondsSinceEpoch(
                    event.createdAt * 1000,
                  ),
                ),
              );
              break;
            }
          }
        }
      }
    });

    // Process email deletions
    emailDeletionResponse.stream.listen((event) async {
      for (final tag in event.tags) {
        if (tag.isNotEmpty && tag[0] == 'e') {
          final emailId = tag[1];

          // Check if we have this email locally
          final email = await _store.getEmailById(emailId);
          if (email != null) {
            // Delete from local store
            await _store.deleteEmail(emailId);
            await _labelStore.deleteLabelsForEmail(emailId);
            await _giftWrapStore.remove(emailId);

            _watchController?.add(
              EmailDeleted(
                emailId: emailId,
                timestamp: DateTime.fromMillisecondsSinceEpoch(
                  event.createdAt * 1000,
                ),
              ),
            );
          }
        }
      }
    });
  }

  /// Stop watching and close the stream
  ///
  /// Call this to clean up resources when you no longer need to watch for events.
  /// After calling this, the next call to [watch] will create new subscriptions.
  void stopWatching() {
    _watchController?.close();
    _watchController = null;
    _watchBroadcastStream = null;
  }

  /// Clear all local data (emails, labels, gift wraps, private settings)
  Future<void> clearAll() async {
    await Future.wait([
      _store.clearAll(),
      _labelStore.clearAll(),
      _giftWrapStore.clearAll(),
      _settingsStore.clear(), // clear all pubkeys
    ]);
    _cachedPrivateSettings.clear();
  }

  // ─── Private Settings (NIP-78 kind 30078, NIP-44 encrypted) ───────────

  /// Synchronous access to the cached private settings for the current pubkey.
  ///
  /// Reads from the in-memory cache. No signer or network required.
  /// Returns `null` if the current pubkey has no cached settings.
  PrivateSettings? get cachedPrivateSettings {
    final pubkey = _ndk.accounts.getPublicKey();
    if (pubkey == null) return null;
    return _cachedPrivateSettings[pubkey];
  }

  /// Read private settings from the local decrypted cache.
  ///
  /// This is an async read of the locally persisted decrypted JSON — no
  /// signer or network required. Returns `null` if nothing is cached.
  ///
  /// Use this at startup to get the signature immediately without waiting
  /// for the bunker. Call [getPrivateSettings] afterward to refresh from
  /// relays.
  Future<PrivateSettings?> getCachedPrivateSettings() async {
    final pubkey = _ndk.accounts.getPublicKey();
    if (pubkey == null) return null;

    final cached = _cachedPrivateSettings[pubkey];
    if (cached != null) return cached;

    final cachedJson = await _settingsStore.load(pubkey: pubkey);
    if (cachedJson == null || cachedJson.isEmpty) return null;
    final settings = PrivateSettings.fromJson(cachedJson);
    _cachedPrivateSettings[pubkey] = settings;
    return settings;
  }

  /// Fetch private settings from relays and decrypt them.
  ///
  /// Results are cached in memory [_cachedPrivateSettings] and persisted
  /// locally in decrypted form so future reads don't require the signer.
  /// Returns [PrivateSettings] (possibly empty) if successful, or `null` if
  /// no settings event is found on relays.
  ///
  /// Settings are stored as NIP-78 replaceable parameterized events (kind 30078)
  /// with d-tag `nostr-mail/settings/private`, encrypted using NIP-44.
  /// Queried from the user's write relays (NIP-65).
  Future<PrivateSettings?> getPrivateSettings() async {
    final pubkey = _ndk.accounts.getPublicKey();
    if (pubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }

    final account = _ndk.accounts.getLoggedAccount();
    if (account == null || !account.signer.canSign()) {
      throw NostrMailException(
        'Cannot read private settings: no signing capability',
      );
    }

    final writeRelays = await _getWriteRelays(pubkey);

    final response = _ndk.requests.query(
      filter: ndk.Filter(kinds: [appSettingsKind], authors: [pubkey], limit: 1)
        ..setTag('d', [privateSettingsDTag]),
      explicitRelays: writeRelays,
    );

    final events = await response.future;
    if (events.isEmpty) return null;

    // Get the most recent event
    final event = events.reduce((a, b) => a.createdAt > b.createdAt ? a : b);

    try {
      final decrypted = await account.signer.decryptNip44(
        ciphertext: event.content,
        senderPubKey: pubkey,
      );
      if (decrypted == null || decrypted.isEmpty) return null;

      // Persist decrypted JSON locally for offline access
      await _settingsStore.save(pubkey: pubkey, json: decrypted);

      final settings = PrivateSettings.fromJson(decrypted, sourceEvent: event);
      _cachedPrivateSettings[pubkey] = settings;
      return settings;
    } catch (e) {
      return null;
    }
  }

  /// Save (publish) private settings to relays.
  ///
  /// Creates a NIP-78 replaceable parameterized event (kind 30078) with the
  /// settings encrypted to self using NIP-44.
  Future<void> setPrivateSettings(PrivateSettings settings) async {
    final pubkey = _ndk.accounts.getPublicKey();
    if (pubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }

    final account = _ndk.accounts.getLoggedAccount();
    if (account == null || !account.signer.canSign()) {
      throw NostrMailException(
        'Cannot write private settings: no signing capability',
      );
    }

    final jsonContent = settings.toJson();
    final encryptedContent = await account.signer.encryptNip44(
      plaintext: jsonContent,
      recipientPubKey: pubkey,
    );
    if (encryptedContent == null) {
      throw NostrMailException('Failed to encrypt private settings');
    }

    final event = Nip01Event(
      pubKey: pubkey,
      kind: appSettingsKind,
      tags: [
        ['d', privateSettingsDTag],
      ],
      content: encryptedContent,
    );

    final signedEvent = await _ndk.accounts.sign(event);

    // Persist locally for offline access (no signer needed to read)
    await _settingsStore.save(pubkey: pubkey, json: settings.toJson());
    _cachedPrivateSettings[pubkey] = PrivateSettings(
      sourceEvent: signedEvent,
      signature: settings.signature,
      bridges: settings.bridges,
      identities: settings.identities,
    );

    final writeRelays = await _getWriteRelays(pubkey);
    final broadcast = _ndk.broadcast.broadcast(
      nostrEvent: signedEvent,
      specificRelays: writeRelays,
    );
    await broadcast.broadcastDoneFuture;
  }

  /// Update a single field in private settings.
  ///
  /// Fetches current settings, updates the specified field, and re-publishes.
  /// Use the [clear*] flags to explicitly remove a field.
  Future<void> updatePrivateSettings({
    String? signature,
    List<String>? bridges,
    List<MailAddress>? identities,
    bool clearSignature = false,
    bool clearBridges = false,
    bool clearIdentities = false,
  }) async {
    final current = await getPrivateSettings() ?? const PrivateSettings();
    final updated = current.copyWith(
      signature: signature,
      bridges: bridges,
      identities: identities,
      clearSignature: clearSignature,
      clearBridges: clearBridges,
      clearIdentities: clearIdentities,
    );
    await setPrivateSettings(updated);
  }

  /// Stream of new emails
  Stream<Email> get onEmail => watch()
      .where((e) => e is EmailReceived)
      .cast<EmailReceived>()
      .map((e) => e.email);

  /// Stream of label changes
  Stream<MailEvent> get onLabel =>
      watch().where((e) => e is LabelAdded || e is LabelRemoved);

  /// Stream of trash events
  Stream<MailEvent> get onTrash =>
      onLabel.where((e) => _getLabelFromEvent(e) == 'folder:trash');

  /// Stream of read state events
  Stream<MailEvent> get onRead =>
      onLabel.where((e) => _getLabelFromEvent(e) == 'state:read');

  /// Stream of starred events
  Stream<MailEvent> get onStarred =>
      onLabel.where((e) => _getLabelFromEvent(e) == 'flag:starred');

  String? _getLabelFromEvent(MailEvent e) {
    if (e is LabelAdded) return e.label;
    if (e is LabelRemoved) return e.label;
    return null;
  }

  /// Sync all data from relays (emails, labels, deletions)
  ///
  /// Uses NDK's fetchedRanges to only fetch gaps (time ranges not yet synced).
  /// [until] defaults to now if not specified.
  Future<void> sync({int? since, int? until}) async {
    final pubkey = _ndk.accounts.getPublicKey();
    if (pubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final effectiveSince = since;
    final effectiveUntil = until ?? now;

    // Get relays
    final (dmRelays, writeRelays) = await (
      _getDmRelays(pubkey),
      _getWriteRelays(pubkey),
    ).wait;

    // Sync emails
    await _syncEmails(pubkey, dmRelays, effectiveSince, effectiveUntil);

    // Sync email deletions
    await _syncEmailDeletions(pubkey, dmRelays, effectiveSince, effectiveUntil);

    // Sync public emails (from write relays)
    await _syncPublicEmails(
      pubkey,
      writeRelays,
      effectiveSince,
      effectiveUntil,
    );

    // Sync labels (includes label deletions)
    await _syncLabels(pubkey, writeRelays, effectiveSince, effectiveUntil);
  }

  /// Resync all data from relays, ignoring cached fetchedRanges
  ///
  /// This clears all fetchedRanges for email-related filters and performs
  /// a full sync. Use this to recover events that may have been missed
  /// due to late broadcasts (e.g., when another device retried a failed send).
  Future<void> resync({int? since, int? until}) async {
    final pubkey = _ndk.accounts.getPublicKey();
    if (pubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }

    // Clear all fetchedRanges in parallel
    await Future.wait([
      _ndk.fetchedRanges.clearForFilter(_emailFilter(pubkey)),
      _ndk.fetchedRanges.clearForFilter(_emailDeletionFilter(pubkey)),
      _ndk.fetchedRanges.clearForFilter(_labelFilter(pubkey)),
      _ndk.fetchedRanges.clearForFilter(_labelDeletionFilter(pubkey)),
    ]);

    // Now sync normally (will fetch everything since ranges are cleared)
    await sync(since: since, until: until);
  }

  /// Fetches all events without fetchedRanges optimization
  ///
  /// Simple parallel queries to all relays.
  Future<void> fetchRecent() async {
    final pubkey = _ndk.accounts.getPublicKey();
    if (pubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }

    final (dmRelays, writeRelays) = await (
      _getDmRelays(pubkey),
      _getWriteRelays(pubkey),
    ).wait;

    // Fetch all in parallel
    final results = await (
      _fetchEmails(_emailFilter(pubkey), dmRelays),
      _fetchEvents(_emailDeletionFilter(pubkey), dmRelays),
      _fetchEvents(_labelFilter(pubkey), writeRelays),
      _fetchEvents(_labelDeletionFilter(pubkey), writeRelays),
    ).wait;

    // Save and process emails
    for (final event in results.$1) {
      await _saveAndProcess(event);
    }

    // Process deletions and labels
    await _processEmailDeletions(results.$2);
    await _processLabelAdditions(results.$3);
    await _processLabelDeletions(results.$4);
  }

  // Filter builders for reuse
  ndk.Filter _emailFilter(String pubkey) =>
      ndk.Filter(kinds: [GiftWrap.kGiftWrapEventkind], pTags: [pubkey]);

  ndk.Filter _emailDeletionFilter(String pubkey) =>
      ndk.Filter(kinds: [deletionRequestKind], authors: [pubkey])
        ..setTag('k', [giftWrapKind.toString()]);

  ndk.Filter _labelFilter(String pubkey) =>
      ndk.Filter(kinds: [labelKind], authors: [pubkey]);

  ndk.Filter _labelDeletionFilter(String pubkey) =>
      ndk.Filter(kinds: [deletionRequestKind], authors: [pubkey])
        ..setTag('k', [labelKind.toString()]);

  ndk.Filter _publicEmailFilter(String pubkey) =>
      ndk.Filter(kinds: [emailKind], pTags: [pubkey]);

  /// Sync emails from relays (internal)
  Future<void> _syncEmails(
    String pubkey,
    List<String> dmRelays,
    int? since,
    int until,
  ) async {
    final baseFilter = _emailFilter(pubkey);

    // Check if we have any existing fetched ranges
    final existingRanges = await _ndk.fetchedRanges.getForFilter(baseFilter);

    if (existingRanges.isEmpty) {
      // First sync - fetch the full range
      final filter = baseFilter.clone()
        ..since = since
        ..until = until;
      final events = await _fetchEmails(filter, dmRelays);
      for (final event in events) {
        await _saveAndProcess(event);
      }
      return;
    }

    // Get optimized filters that cover only the gaps (unfetched ranges)
    final optimizedFilters = await _ndk.fetchedRanges.getOptimizedFilters(
      filter: baseFilter,
      since: since ?? 0,
      until: until,
    );

    // If no gaps, nothing to sync
    if (optimizedFilters.isEmpty) return;

    // Fetch each gap
    for (final gapFilter in optimizedFilters.values.expand((f) => f)) {
      final events = await _fetchEmails(gapFilter, dmRelays);
      for (final event in events) {
        await _saveAndProcess(event);
      }
    }
  }

  /// Sync email deletions from relays (internal)
  Future<void> _syncEmailDeletions(
    String pubkey,
    List<String> dmRelays,
    int? since,
    int until,
  ) async {
    final baseFilter = _emailDeletionFilter(pubkey);

    // Check existing fetched ranges
    final existingRanges = await _ndk.fetchedRanges.getForFilter(baseFilter);

    if (existingRanges.isEmpty) {
      final filter = baseFilter.clone()
        ..since = since
        ..until = until;
      final events = await _fetchEvents(filter, dmRelays);
      await _processEmailDeletions(events);
      return;
    }

    // Get optimized filters for gaps
    final optimizedFilters = await _ndk.fetchedRanges.getOptimizedFilters(
      filter: baseFilter,
      since: since ?? 0,
      until: until,
    );

    if (optimizedFilters.isEmpty) return;

    for (final gapFilter in optimizedFilters.values.expand((f) => f)) {
      final events = await _fetchEvents(gapFilter, dmRelays);
      await _processEmailDeletions(events);
    }
  }

  /// Sync public emails from relays (internal)
  ///
  /// Public emails are kind 1301 events published directly (not gift wrapped).
  /// They must be signed to be valid.
  Future<void> _syncPublicEmails(
    String pubkey,
    List<String> writeRelays,
    int? since,
    int until,
  ) async {
    final baseFilter = _publicEmailFilter(pubkey);

    // Check if we have any existing fetched ranges
    final existingRanges = await _ndk.fetchedRanges.getForFilter(baseFilter);

    if (existingRanges.isEmpty) {
      // First sync - fetch the full range
      final filter = baseFilter.clone()
        ..since = since
        ..until = until;
      final events = await _fetchEvents(filter, writeRelays);
      for (final event in events) {
        await _processPublicEmail(event);
      }
      return;
    }

    // Get optimized filters that cover only the gaps (unfetched ranges)
    final optimizedFilters = await _ndk.fetchedRanges.getOptimizedFilters(
      filter: baseFilter,
      since: since ?? 0,
      until: until,
    );

    // If no gaps, nothing to sync
    if (optimizedFilters.isEmpty) return;

    // Fetch each gap
    for (final gapFilter in optimizedFilters.values.expand((f) => f)) {
      final events = await _fetchEvents(gapFilter, writeRelays);
      for (final event in events) {
        await _processPublicEmail(event);
      }
    }
  }

  /// Process a single public email event (kind 1301, not gift wrapped)
  ///
  /// Public emails must be signed to be valid.
  Future<void> _processPublicEmail(Nip01Event event) async {
    // Public emails must be signed
    if (event.sig == null || event.sig!.isEmpty) {
      return; // Skip unsigned public emails
    }

    // Skip if not an email event
    if (event.kind != emailKind) {
      return;
    }

    // The recipient is the local user who received the event
    final recipientPubkey = _ndk.accounts.getPublicKey();
    if (recipientPubkey == null) {
      return;
    }

    // Parse event into Email (handles inline and Blossom emails)
    try {
      final email = await parseEmailEvent(
        event: event,
        ndk: _ndk,
        recipientPubkey: recipientPubkey,
        isPublic: true,
        defaultBlossomServers: _defaultBlossomServers,
      );

      await _store.saveEmail(email);

      _watchController?.add(EmailReceived(email: email, timestamp: email.date));
    } catch (e) {
      // Log error but don't fail the sync
      // TODO: Consider adding error logging
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

  // TODO: store events in a dedicated store before processing (like gift wraps)
  Future<void> _processEmailDeletions(List<Nip01Event> events) async {
    for (final event in events) {
      for (final tag in event.tags) {
        if (tag.isNotEmpty && tag[0] == 'e') {
          final emailId = tag[1];
          final email = await _store.getEmailById(emailId);
          if (email != null) {
            await _store.deleteEmail(emailId);
            await _labelStore.deleteLabelsForEmail(emailId);
            await _giftWrapStore.remove(emailId);
          }
        }
      }
    }
  }

  /// Fetch gift wraps from relays
  Future<List<Nip01Event>> _fetchEmails(
    ndk.Filter filter,
    List<String> relays,
  ) async {
    final response = _ndk.requests.query(
      filter: filter,
      explicitRelays: relays,
    );
    return response.future;
  }

  /// Save and process a gift wrap event if new
  Future<void> _saveAndProcess(Nip01Event event) async {
    final isNew = await _giftWrapStore.save(event);
    if (!isNew) return;
    await _processEvent(event);
  }

  /// Retry processing a single failed gift wrap
  ///
  /// Use this to retry decryption after a bunker comes back online.
  /// Returns true if processing succeeded.
  /// Throws [SignerRequestCancelledException] if user cancels.
  Future<bool> retry(String eventId) async {
    final event = await _giftWrapStore.getUnprocessed(eventId);
    if (event == null) return false;
    return _processEvent(event);
  }

  /// Get count of unprocessed (failed) gift wraps
  Future<int> getFailedCount() => _giftWrapStore.getFailedCount();

  /// Get unprocessed (failed) gift wrap events
  Future<List<Nip01Event>> getFailedEvents() =>
      _giftWrapStore.getUnprocessedEvents();

  /// Process a single gift wrap event
  ///
  /// Returns true if processing succeeded, false otherwise.
  /// Throws [SignerRequestCancelledException] if user cancelled.
  Future<bool> _processEvent(Nip01Event event) async {
    final myPubkey = _ndk.accounts.getPublicKey();

    // Check if we're the recipient (p-tag check)
    final recipientTag = event.getFirstTag('p');
    if (recipientTag != myPubkey) {
      // Not for this account - skip (might be for another account)
      return false;
    }

    try {
      final unwrapped = await _unwrapGiftWrap(event);

      if (unwrapped == null) {
        // Decryption failed (bunker offline) - don't mark, allow retry
        return false;
      }

      final rumor = unwrapped.rumor;
      final seal = unwrapped.seal;

      // Not an email (DM, etc.) - mark processed to skip in future
      if (rumor.kind != emailKind) {
        await _giftWrapStore.updateDecrypted(
          giftWrapId: event.id,
          seal: seal,
          rumor: rumor,
        );
        return false;
      }

      // Extract the real recipient from the 'p' tag of the email event.
      // Fallback to our own pubkey if the rumor has no p-tag (e.g. shared BCC rumor).
      final recipientPubkey = rumor.getFirstTag('p') ?? myPubkey;
      if (recipientPubkey == null) {
        await _giftWrapStore.updateDecrypted(
          giftWrapId: event.id,
          seal: seal,
          rumor: rumor,
        );
        return false;
      }

      // Parse event into Email (handles inline and Blossom emails)
      final email = await parseEmailEvent(
        event: rumor,
        ndk: _ndk,
        recipientPubkey: recipientPubkey,
        isPublic: rumor.getFirstTag('public-ref') != null,
        defaultBlossomServers: _defaultBlossomServers,
      );

      await _store.saveEmail(email);
      await _giftWrapStore.updateDecrypted(
        giftWrapId: event.id,
        seal: seal,
        rumor: rumor,
      );

      _watchController?.add(EmailReceived(email: email, timestamp: email.date));
      return true;
    } on SignerRequestCancelledException {
      // User cancelled - propagate so caller can handle
      rethrow;
    } on SignerRequestRejectedException {
      // Signer rejected - mark as processed since user explicitly rejected
      await _giftWrapStore.markProcessed(event.id);
      return false;
    } catch (e) {
      // Other processing error - don't mark, allow manual retry
      return false;
    }
  }

  /// Send email - auto-detects if recipient is Nostr or legacy email
  ///
  /// [from] is optional. If not provided, defaults to the first identity
  /// from private settings, or falls back to sender's npub@nostr.
  /// [htmlBody] is optional HTML content for rich emails.
  /// [keepCopy] if true, sends a copy to sender for sync between devices (default: true).
  /// [signRumor] if true, signs the rumor event to prove authorship (default: false).
  /// [isPublic] if true, sends email without gift wrap (requires [signRumor] to be true).
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
  }) async {
    final senderPubkey = _ndk.accounts.getPublicKey();
    if (senderPubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }

    final MailAddress finalFrom;
    if (from != null) {
      finalFrom = from;
    } else {
      // Try to use the first identity from private settings
      final settings =
          cachedPrivateSettings ?? await getCachedPrivateSettings();
      if (settings?.identities != null && settings!.identities!.isNotEmpty) {
        finalFrom = settings.identities!.first;
      } else {
        final senderNpub = Nip19.encodePubKey(senderPubkey);
        finalFrom = MailAddress(null, '$senderNpub@nostr');
      }
    }

    // Build RFC 2822 email content using the updated parser
    final rawContent = _parser.build(
      from: finalFrom,
      to: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      body: body,
      htmlBody: htmlBody,
    );

    final message = MimeMessage.parseFromText(rawContent);
    return sendMime(
      message,
      keepCopy: keepCopy,
      signRumor: signRumor,
      isPublic: isPublic,
    );
  }

  /// Send a pre-constructed [MimeMessage].
  ///
  /// This method extracts all recipients (To, Cc, Bcc), resolves their pubkeys,
  /// and sends the email to each of them via Nostr GiftWraps.
  ///
  /// [signRumor] if true, signs the rumor event to prove authorship.
  /// [isPublic] if true, sends email without gift wrap (requires [signRumor] to be true).
  /// [mailFrom] if provided, adds a `mail-from` tag to the rumor event, useful for bridge routing.
  Future<void> sendMime(
    MimeMessage message, {
    bool keepCopy = true,
    bool signRumor = false,
    bool isPublic = false,
    String? mailFrom,
  }) async {
    final senderPubkey = _ndk.accounts.getPublicKey();
    if (senderPubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }

    // Public emails must be signed
    if (isPublic && !signRumor) {
      throw NostrMailException(
        'Public emails must be signed (signRumor must be true)',
      );
    }

    // Extract and resolve all unique recipients
    final recipients = <MailAddress>{};
    if (message.to != null) recipients.addAll(message.to!);
    if (message.cc != null) recipients.addAll(message.cc!);
    if (message.bcc != null) recipients.addAll(message.bcc!);

    if (recipients.isEmpty) {
      throw NostrMailException('No recipients found in MimeMessage');
    }

    final fromAddress = message.fromEmail;

    // Resolve all unique pubkeys in parallel and map back to addresses
    final resolutionFutures = recipients.map((addr) async {
      final pubkey = await resolveRecipient(
        to: addr.encode(),
        from: fromAddress,
        nip05Overrides: nip05Overrides,
      );
      return MapEntry(addr, pubkey);
    });
    final resolutionResults = await Future.wait(resolutionFutures);
    final Map<MailAddress, String> addressToPubkey = Map.fromEntries(
      resolutionResults,
    );
    final Set<String> recipientPubkeys = addressToPubkey.values.toSet();

    // Separate recipients into public (TO, CC) and private (BCC)
    final publicRecipientPubkeys = <String>{};
    if (message.to != null) {
      publicRecipientPubkeys.addAll(
        message.to!.map((a) => addressToPubkey[a]).whereType<String>(),
      );
    }
    if (message.cc != null) {
      publicRecipientPubkeys.addAll(
        message.cc!.map((a) => addressToPubkey[a]).whereType<String>(),
      );
    }

    final bccRecipientPubkeys = <String>{};
    if (message.bcc != null) {
      bccRecipientPubkeys.addAll(
        message.bcc!.map((a) => addressToPubkey[a]).whereType<String>(),
      );
    }

    final rawContent = message.renderMessage();
    final rawContentBytes = utf8.encode(rawContent);

    // Prepare common event components
    final Set<String> targetPubkeys = {...recipientPubkeys};
    if (keepCopy) targetPubkeys.add(senderPubkey);

    final List<List<String>> baseTags = [];
    if (mailFrom != null) {
      baseTags.add(['mail-from', mailFrom]);
    }
    final String content;

    if (rawContentBytes.length < maxInlineSize) {
      content = ''; // Will be set per recipient
    } else {
      final encryptedBlob = await encryptBlob(
        Uint8List.fromList(rawContentBytes),
      );

      // Collect Blossom servers from all unique pubkeys involved (recipients + sender)
      final Set<String> allInvolvedPubkeys = {...recipientPubkeys};
      if (keepCopy) allInvolvedPubkeys.add(senderPubkey);

      final List<String> allBlossomServers = [];
      final servers = await _ndk.blossomUserServerList.getUserServerList(
        pubkeys: allInvolvedPubkeys.toList(),
      );
      if (servers != null) allBlossomServers.addAll(servers);

      // Fallback to defaults if no servers found
      if (allBlossomServers.isEmpty) {
        allBlossomServers.addAll(_defaultBlossomServers);
      }

      final uploadResults = await _ndk.blossom.uploadBlob(
        data: encryptedBlob.bytes,
        serverUrls: allBlossomServers.toSet().toList(), // Remove duplicates
      );

      final successfulUpload = uploadResults.firstWhere(
        (result) => result.success && result.descriptor != null,
        orElse: () => throw NostrMailException('Failed to upload to Blossom'),
      );
      final sha256Hash = successfulUpload.descriptor!.sha256;

      baseTags
        ..add(['x', sha256Hash])
        ..add(['encryption-algorithm', 'aes-gcm'])
        ..add(['decryption-key', encryptedBlob.key])
        ..add(['decryption-nonce', encryptedBlob.nonce]);

      content = '';
    }

    // Public emails: send a single event for TO/CC, and individual gift wraps for BCC
    if (isPublic) {
      // For public emails, send to public recipients in a single event
      // Don't include BCC headers in public emails
      final targetContent = removeBccHeaders(rawContent);

      final String finalContent;
      final targetContentBytes = utf8.encode(targetContent);
      if (targetContentBytes.length < maxInlineSize) {
        finalContent = targetContent;
      } else {
        finalContent = content; // Empty, uses tags
      }

      // Create tags with public recipients only (no BCC leak)
      final tags = List<List<String>>.from(baseTags);
      for (final pubkey in publicRecipientPubkeys) {
        tags.add(['p', pubkey]);
      }

      final emailEvent = Nip01Event(
        pubKey: senderPubkey,
        kind: emailKind,
        tags: tags,
        content: finalContent,
      );

      // Sign the rumor (required for public emails)
      final signedPublicEvent = await _ndk.accounts.sign(emailEvent);

      // Publish to write relays
      final writeRelays = await _getWriteRelays(senderPubkey);
      final broadcast = _ndk.broadcast.broadcast(
        nostrEvent: signedPublicEvent,
        specificRelays: writeRelays,
      );
      await broadcast.broadcastDoneFuture;

      // Send shared gift-wrapped rumor to BCC recipients (signed once)
      final bccTags = List<List<String>>.from(baseTags);
      // Add public-ref tag as per protocol
      bccTags.add(['public-ref', signedPublicEvent.id, ...writeRelays]);

      final bccRumor = Nip01Event(
        pubKey: senderPubkey,
        kind: emailKind,
        tags: bccTags,
        content: finalContent,
      );

      // Sign the BCC rumor exactly once for all recipients
      final signedBccRumor = await _ndk.accounts.sign(bccRumor);

      final bccFutures = bccRecipientPubkeys.map((pubkey) async {
        await _publishGiftWrapped(signedBccRumor, pubkey);
      });

      // Also send a copy to sender if requested
      if (keepCopy) {
        final senderTags = List<List<String>>.from(baseTags);
        senderTags.add(['p', senderPubkey]);

        final senderEmailEvent = Nip01Event(
          pubKey: senderPubkey,
          kind: emailKind,
          tags: senderTags,
          content: rawContent, // Full content including BCC headers
        );

        final signedSenderRumor = signRumor
            ? await _ndk.accounts.sign(senderEmailEvent)
            : senderEmailEvent;

        await _publishGiftWrapped(signedSenderRumor, senderPubkey);
      }

      await Future.wait(bccFutures);
    } else {
      // Private emails: gift wrap to each recipient individually
      final sendFutures = targetPubkeys.map((pubkey) async {
        // Determine which version of the message to send
        String targetContent;
        if (keepCopy && pubkey == senderPubkey) {
          // Sender sees all recipients
          targetContent = rawContent;
        } else {
          // All recipients (TO, CC, BCC) don't see BCC headers
          targetContent = removeBccHeaders(rawContent);
        }

        final String finalContent;
        final targetContentBytes = utf8.encode(targetContent);
        if (targetContentBytes.length < maxInlineSize) {
          finalContent = targetContent;
        } else {
          // Use Blossom upload
          finalContent = content; // Empty, uses tags
        }

        final tags = List<List<String>>.from(baseTags);
        tags.insert(0, ['p', pubkey]);

        final emailEvent = Nip01Event(
          pubKey: senderPubkey,
          kind: emailKind,
          tags: tags,
          content: finalContent,
        );

        // Sign the rumor if requested
        final Nip01Event eventToPublish;
        if (signRumor) {
          eventToPublish = await _ndk.accounts.sign(emailEvent);
        } else {
          eventToPublish = emailEvent;
        }

        // Send gift wrapped to this recipient
        await _publishGiftWrapped(eventToPublish, pubkey);
      });

      await Future.wait(sendFutures);
    }
  }

  /// Unwrap a NIP-59 gift-wrapped event
  ///
  /// Returns the unwrapped seal and rumor, or null if decryption failed.
  /// Throws [SignerRequestCancelledException] if the user cancelled locally.
  /// Throws [SignerRequestRejectedException] if the signer rejected the request.
  Future<UnwrappedGiftWrap?> _unwrapGiftWrap(Nip01Event giftWrapEvent) async {
    try {
      final seal = await _ndk.giftWrap.unwrapEvent(wrappedEvent: giftWrapEvent);
      final rumor = await _ndk.giftWrap.unsealRumor(sealedEvent: seal);
      return UnwrappedGiftWrap(seal: seal, rumor: rumor);
    } on SignerRequestCancelledException {
      // User cancelled - propagate to caller
      rethrow;
    } on SignerRequestRejectedException {
      // Signer rejected - propagate to caller
      rethrow;
    } catch (e) {
      // Other errors (bunker offline, etc.) - return null for retry
      return null;
    }
  }

  /// Gift wrap and publish an event to recipient's relays
  Future<void> _publishGiftWrapped(
    Nip01Event event,
    String recipientPubkey,
  ) async {
    // Gift wrap the event
    final giftWrapEvent = await _ndk.giftWrap.toGiftWrap(
      rumor: event,
      recipientPubkey: recipientPubkey,
    );

    // Publish to relays
    final broadcast = _ndk.broadcast.broadcast(nostrEvent: giftWrapEvent);
    await broadcast.broadcastDoneFuture;
  }

  /// Get user's DM relays from NIP-17 kind 10050 event
  ///
  /// Falls back to default relays if user has none configured.
  Future<List<String>> _getDmRelays(String pubkey) async {
    final response = _ndk.requests.query(
      filter: ndk.Filter(kinds: [dmRelayListKind], authors: [pubkey], limit: 1),
    );

    final events = await response.future;
    if (events.isEmpty) return _defaultDmRelays;

    // Get the most recent event
    final event = events.reduce((a, b) => a.createdAt > b.createdAt ? a : b);

    final relays = event.tags
        .where((t) => t.isNotEmpty && t[0] == 'relay')
        .map((t) => t[1])
        .toList();

    return relays.isNotEmpty ? relays : _defaultDmRelays;
  }

  /// Get user's write relays from NIP-65 kind 10002 event
  ///
  /// Falls back to default relays if user has none configured.
  Future<List<String>> _getWriteRelays(String pubkey) async {
    final response = _ndk.requests.query(
      filter: ndk.Filter(kinds: [relayListKind], authors: [pubkey], limit: 1),
    );

    final events = await response.future;
    if (events.isEmpty) return _defaultDmRelays;

    // Get the most recent event
    final event = events.reduce((a, b) => a.createdAt > b.createdAt ? a : b);

    // NIP-65: 'r' tags with optional read/write marker
    // ['r', 'wss://relay.example.com', 'write'] or just ['r', 'wss://relay.example.com']
    final relays = event.tags
        .where(
          (t) =>
              t.isNotEmpty &&
              t[0] == 'r' &&
              (t.length == 2 || t.length == 3 && t[2] != 'read'),
        )
        .map((t) => t[1])
        .toList();

    return relays.isNotEmpty ? relays : _defaultDmRelays;
  }
}
