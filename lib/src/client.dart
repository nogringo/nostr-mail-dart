import 'dart:async';

import 'package:ndk/ndk.dart' hide Filter;
import 'package:ndk/domain_layer/entities/filter.dart' as ndk;
import 'package:sembast/sembast.dart';

import 'exceptions.dart';
import 'models/email.dart';
import 'models/mail_event.dart';
import 'services/bridge_resolver.dart';
import 'services/email_parser.dart';
import 'storage/email_store.dart';
import 'storage/gift_wrap_store.dart';
import 'storage/label_store.dart';

const _emailKind = 1301;
const _dmRelayListKind = 10050;
const _deletionRequestKind = 5;
const _giftWrapKind = 1059;
const _labelKind = 1985;
const _relayListKind = 10002;
const _labelNamespace = 'mail';
const _defaultDmRelays = [
  'wss://auth.nostr1.com',
  'wss://nostr-01.uid.ovh',
  'wss://nostr-02.uid.ovh',
];

class NostrMailClient {
  final Ndk _ndk;
  final EmailStore _store;
  final LabelStore _labelStore;
  final GiftWrapStore _giftWrapStore;
  final EmailParser _parser;
  final BridgeResolver _bridgeResolver;

  /// Cached broadcast stream for watch()
  StreamController<MailEvent>? _watchController;
  Stream<MailEvent>? _watchBroadcastStream;

  NostrMailClient({required Ndk ndk, required Database db})
    : _ndk = ndk,
      _store = EmailStore(db),
      _labelStore = LabelStore(db),
      _giftWrapStore = GiftWrapStore(db),
      _parser = EmailParser(),
      _bridgeResolver = BridgeResolver();

  /// Get cached emails from local DB
  Future<List<Email>> getEmails({int? limit, int? offset}) {
    return _store.getEmails(limit: limit, offset: offset);
  }

  /// Get single email by ID
  Future<Email?> getEmail(String id) {
    return _store.getEmailById(id);
  }

  /// Get sent emails from local DB
  ///
  /// By default excludes trashed emails. Set [includeTrashed] to true to include them.
  /// Note: pages may have fewer items if some are trashed.
  Future<List<Email>> getSentEmails({
    int? limit,
    int? offset,
    bool includeTrashed = false,
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
    if (includeTrashed) return emails;
    final trashedIds = await getTrashedEmailIds();
    return emails.where((e) => !trashedIds.contains(e.id)).toList();
  }

  /// Get inbox emails from local DB (received, excluding sent)
  ///
  /// By default excludes trashed emails. Set [includeTrashed] to true to include them.
  /// Note: pages may have fewer items if some are trashed.
  Future<List<Email>> getInboxEmails({
    int? limit,
    int? offset,
    bool includeTrashed = false,
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
    if (includeTrashed) return emails;
    final trashedIds = await getTrashedEmailIds();
    return emails.where((e) => !trashedIds.contains(e.id)).toList();
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
      kind: _deletionRequestKind,
      tags: [
        ['e', email.id],
        ['k', _giftWrapKind.toString()],
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
  Future<void> addLabel(String emailId, String label) async {
    final pubkey = _ndk.accounts.getPublicKey();
    if (pubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }

    // Check if label already exists
    if (await _labelStore.hasLabel(emailId, label)) {
      return;
    }

    // Create NIP-32 label event
    final labelEvent = Nip01Event(
      pubKey: pubkey,
      kind: _labelKind,
      tags: [
        ['L', _labelNamespace],
        ['l', label, _labelNamespace],
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
      kind: _deletionRequestKind,
      tags: [
        ['e', labelEventId],
        ['k', _labelKind.toString()],
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

  /// Check if email is read
  Future<bool> isRead(String emailId) => hasLabel(emailId, 'state:read');

  /// Check if email is starred
  Future<bool> isStarred(String emailId) => hasLabel(emailId, 'flag:starred');

  /// Get all trashed email IDs
  Future<List<String>> getTrashedEmailIds() =>
      _labelStore.getEmailIdsWithLabel('folder:trash');

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
        (t) => t.isNotEmpty && t[0] == 'L' && t[1] == _labelNamespace,
        orElse: () => [],
      );
      if (namespaceTag.isEmpty) continue;

      // Get the label value
      final labelTag = event.tags.firstWhere(
        (t) => t.length >= 3 && t[0] == 'l' && t[2] == _labelNamespace,
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
      filter: ndk.Filter(kinds: [_labelKind], authors: [pubkey], limit: 0),
      explicitRelays: writeRelays,
    );

    // Watch label deletions on write relays
    final labelDeletionFilter = ndk.Filter(
      kinds: [_deletionRequestKind],
      authors: [pubkey],
      limit: 0,
    )..setTag('k', [_labelKind.toString()]);
    final labelDeletionResponse = _ndk.requests.subscription(
      filter: labelDeletionFilter,
      explicitRelays: writeRelays,
    );

    // Watch email deletions on DM relays
    final emailDeletionFilter = ndk.Filter(
      kinds: [_deletionRequestKind],
      authors: [pubkey],
      limit: 0,
    )..setTag('k', [_giftWrapKind.toString()]);
    final emailDeletionResponse = _ndk.requests.subscription(
      filter: emailDeletionFilter,
      explicitRelays: dmRelays,
    );

    // Process emails
    emailResponse.stream.listen(_saveAndProcess);

    // Process label additions
    labelResponse.stream.listen((event) async {
      // Check namespace
      final namespaceTag = event.tags.firstWhere(
        (t) => t.isNotEmpty && t[0] == 'L' && t[1] == _labelNamespace,
        orElse: () => [],
      );
      if (namespaceTag.isEmpty) return;

      // Get label value
      final labelTag = event.tags.firstWhere(
        (t) => t.length >= 3 && t[0] == 'l' && t[2] == _labelNamespace,
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

  /// Clear all local data (emails, labels, gift wraps)
  Future<void> clearAll() async {
    await Future.wait([
      _store.clearAll(),
      _labelStore.clearAll(),
      _giftWrapStore.clearAll(),
    ]);
  }

  /// Stream of new emails
  Stream<Email> get onEmail => watch()
      .where((e) => e is EmailReceived)
      .cast<EmailReceived>()
      .asyncMap((e) async => (await getEmail(e.emailId))!);

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
      ndk.Filter(kinds: [_deletionRequestKind], authors: [pubkey])
        ..setTag('k', [_giftWrapKind.toString()]);

  ndk.Filter _labelFilter(String pubkey) =>
      ndk.Filter(kinds: [_labelKind], authors: [pubkey]);

  ndk.Filter _labelDeletionFilter(String pubkey) =>
      ndk.Filter(kinds: [_deletionRequestKind], authors: [pubkey])
        ..setTag('k', [_labelKind.toString()]);

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

      // Not an email (DM, etc.) - mark processed to skip in future
      if (unwrapped.kind != _emailKind) {
        await _giftWrapStore.markProcessed(event.id);
        return false;
      }

      // Extract the real recipient from the 'p' tag of the email event
      final recipientPubkey = unwrapped.getFirstTag('p');
      if (recipientPubkey == null) {
        await _giftWrapStore.markProcessed(event.id);
        return false;
      }

      final email = _parser.parse(
        rawContent: unwrapped.content,
        eventId: event.id,
        senderPubkey: unwrapped.pubKey,
        recipientPubkey: recipientPubkey,
      );

      await _store.saveEmail(email);
      await _giftWrapStore.markProcessed(event.id);

      _watchController?.add(
        EmailReceived(
          emailId: email.id,
          from: email.from,
          subject: email.subject,
          timestamp: email.date,
        ),
      );
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
  /// [from] is required when sending to legacy email addresses (e.g. bob@gmail.com).
  /// The bridge is resolved from the sender's domain.
  /// [htmlBody] is optional HTML content for rich emails.
  /// [keepCopy] if true, sends a copy to sender for sync between devices (default: true).
  Future<void> send({
    required String to,
    required String subject,
    required String body,
    String? from,
    String? htmlBody,
    bool keepCopy = true,
  }) async {
    final senderPubkey = _ndk.accounts.getPublicKey();
    if (senderPubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }

    // Determine recipient pubkey and build email
    final recipientPubkey = await _resolveRecipient(to, from);
    final senderNpub = Nip19.encodePubKey(senderPubkey);
    final fromAddress = from ?? '$senderNpub@nostr';
    final toAddress = _formatAddressForRfc2822(to);

    // Build RFC 2822 email content
    final rawContent = _parser.build(
      from: fromAddress,
      to: toAddress,
      subject: subject,
      body: body,
      htmlBody: htmlBody,
    );

    // Create kind 1301 email event
    final emailEvent = Nip01Event(
      pubKey: senderPubkey,
      kind: _emailKind,
      tags: [
        ['p', recipientPubkey],
      ],
      content: rawContent,
    );

    // Gift wrap and publish to recipient
    await _publishGiftWrapped(emailEvent, recipientPubkey);

    // Gift wrap and publish copy to sender (for sync between devices)
    if (keepCopy && recipientPubkey != senderPubkey) {
      await _publishGiftWrapped(emailEvent, senderPubkey);
    }

    // TODO: Store email locally immediately after sending instead of waiting
    // for the copy to be received back from the relay
  }

  /// Resolve recipient to Nostr pubkey
  Future<String> _resolveRecipient(String to, String? from) async {
    // Check if it's an npub
    if (to.startsWith('npub1')) {
      try {
        final decoded = Nip19.decode(to);
        return decoded;
      } catch (e) {
        throw RecipientResolutionException(to);
      }
    }

    // Check if it's a 64-char hex pubkey
    if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(to)) {
      return to.toLowerCase();
    }

    // It's an email format - try NIP-05 first
    if (to.contains('@')) {
      final nip05Pubkey = await _bridgeResolver.resolveNip05(to);
      if (nip05Pubkey != null) {
        return nip05Pubkey;
      }

      // NIP-05 failed, route via bridge at sender's domain
      if (from == null || !from.contains('@')) {
        throw NostrMailException(
          'from address is required when sending to legacy email addresses',
        );
      }
      final domain = from.split('@').last;
      final bridgePubkey = await _bridgeResolver.resolveBridgePubkey(domain);
      return bridgePubkey;
    }

    throw RecipientResolutionException(to);
  }

  /// Format address for RFC 2822 compatibility
  /// Converts hex to npub and adds @nostr suffix for addresses without a domain
  String _formatAddressForRfc2822(String address) {
    // Already has a domain
    if (address.contains('@')) {
      return address;
    }

    // Already npub - add @nostr
    if (address.startsWith('npub1')) {
      return '$address@nostr';
    }

    // Hex pubkey - convert to npub and add @nostr
    if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(address)) {
      final npub = Nip19.encodePubKey(address.toLowerCase());
      return '$npub@nostr';
    }

    return address;
  }

  /// Unwrap a NIP-59 gift-wrapped event
  ///
  /// Returns the unwrapped event, or null if decryption failed.
  /// Throws [SignerRequestCancelledException] if the user cancelled locally.
  /// Throws [SignerRequestRejectedException] if the signer rejected the request.
  Future<Nip01Event?> _unwrapGiftWrap(Nip01Event giftWrapEvent) async {
    try {
      final unwrapped = await _ndk.giftWrap.fromGiftWrap(
        giftWrap: giftWrapEvent,
      );
      return unwrapped;
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
      filter: ndk.Filter(
        kinds: [_dmRelayListKind],
        authors: [pubkey],
        limit: 1,
      ),
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
      filter: ndk.Filter(kinds: [_relayListKind], authors: [pubkey], limit: 1),
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
