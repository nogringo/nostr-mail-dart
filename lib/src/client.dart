import 'dart:async';

import 'package:ndk/ndk.dart' hide Filter;
import 'package:ndk/domain_layer/entities/filter.dart' as ndk;
import 'package:sembast/sembast.dart';

import 'exceptions.dart';
import 'models/email.dart';
import 'services/bridge_resolver.dart';
import 'services/email_parser.dart';
import 'storage/email_store.dart';
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
  final EmailParser _parser;
  final BridgeResolver _bridgeResolver;

  NostrMailClient({required Ndk ndk, required Database db})
    : _ndk = ndk,
      _store = EmailStore(db),
      _labelStore = LabelStore(db),
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
    await broadcast.broadcastDoneFuture;

    // Delete from local DB
    await _store.deleteEmail(id);
    await _labelStore.deleteLabelsForEmail(id);
  }

  /// Add a label to an email (NIP-32)
  ///
  /// Publishes a kind 1985 label event to the user's write relays.
  Future<void> addLabel(String emailId, String label) async {
    final pubkey = _ndk.accounts.getPublicKey();
    if (pubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }

    // Check if label already exists
    if (await _labelStore.hasLabel(emailId, label)) {
      return;
    }

    final writeRelays = await _getWriteRelays(pubkey);

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

    // Sign and broadcast
    final signedEvent = await _ndk.accounts.sign(labelEvent);
    final broadcast = _ndk.broadcast.broadcast(
      nostrEvent: signedEvent,
      specificRelays: writeRelays,
    );
    await broadcast.broadcastDoneFuture;

    // Save to local cache
    await _labelStore.saveLabel(
      emailId: emailId,
      label: label,
      labelEventId: signedEvent.id,
    );
  }

  /// Remove a label from an email
  ///
  /// Publishes a NIP-09 deletion request for the label event.
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

    final writeRelays = await _getWriteRelays(pubkey);

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

    // Sign and broadcast
    final signedEvent = await _ndk.accounts.sign(deletionEvent);
    final broadcast = _ndk.broadcast.broadcast(
      nostrEvent: signedEvent,
      specificRelays: writeRelays,
    );
    await broadcast.broadcastDoneFuture;

    // Remove from local cache
    await _labelStore.removeLabel(emailId, label);
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

  /// Sync labels from relays
  ///
  /// Fetches all NIP-32 label events from write relays and updates local cache.
  /// Also handles deleted labels (kind 5 events).
  Future<void> syncLabels() async {
    final pubkey = _ndk.accounts.getPublicKey();
    if (pubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }

    final writeRelays = await _getWriteRelays(pubkey);

    // Fetch all label events for this user with 'mail' namespace
    final labelResponse = _ndk.requests.query(
      filter: ndk.Filter(kinds: [_labelKind], authors: [pubkey]),
      explicitRelays: writeRelays,
    );

    // Collect all label events
    final labelEvents = <Nip01Event>[];
    await for (final event in labelResponse.stream) {
      labelEvents.add(event);
    }

    // Fetch deletion events for labels (filter by #k tag = 1985)
    final deletionFilter = ndk.Filter(
      kinds: [_deletionRequestKind],
      authors: [pubkey],
    )..setTag('k', [_labelKind.toString()]);
    final deletionResponse = _ndk.requests.query(
      filter: deletionFilter,
      explicitRelays: writeRelays,
    );

    // Collect deleted label event IDs
    final deletedLabelIds = <String>{};
    await for (final event in deletionResponse.stream) {
      for (final tag in event.tags) {
        if (tag.isNotEmpty && tag[0] == 'e') {
          deletedLabelIds.add(tag[1]);
        }
      }
    }

    // Process label events (excluding deleted ones)
    for (final event in labelEvents) {
      // Skip deleted labels
      if (deletedLabelIds.contains(event.id)) continue;

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

  /// Watch for new emails from relays (real-time)
  ///
  /// Subscribes to user's DM relays (NIP-17 kind 10050).
  Stream<Email> watchInbox() async* {
    final pubkey = _ndk.accounts.getPublicKey();
    if (pubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }

    // Get user's DM relays
    final dmRelays = await _getDmRelays(pubkey);

    final response = _ndk.requests.subscription(
      filter: ndk.Filter(
        kinds: [GiftWrap.kGiftWrapEventkind],
        pTags: [pubkey],
        limit: 0,
      ),
      explicitRelays: dmRelays,
    );

    await for (final event in response.stream) {
      // Skip already processed events
      if (await _store.isProcessed(event.id)) continue;

      try {
        // Unwrap the gift-wrapped event
        final unwrapped = await _unwrapGiftWrap(event);
        if (unwrapped == null) continue;

        // Mark as processed to avoid re-decrypting non-email gift wraps (DMs, etc.)
        await _store.markProcessed(event.id);

        // Only process email events (kind 1301)
        if (unwrapped.kind != _emailKind) continue;

        // Parse the email from RFC 2822 content
        final email = _parser.parse(
          rawContent: unwrapped.content,
          eventId: event.id,
          senderPubkey: unwrapped.pubKey,
          recipientPubkey: pubkey,
        );

        // Save to local DB
        await _store.saveEmail(email);

        yield email;
      } catch (e) {
        // Skip malformed events
        continue;
      }
    }
  }

  /// Sync emails from relays (fetch historical + store in DB)
  ///
  /// Uses NDK's fetchedRanges to only fetch gaps (time ranges not yet synced).
  /// Fetches from user's DM relays (NIP-17 kind 10050).
  /// [until] defaults to now if not specified.
  Future<void> sync({int? since, int? until}) async {
    final pubkey = _ndk.accounts.getPublicKey();
    if (pubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final effectiveSince = since;
    final effectiveUntil = until ?? now;

    // Get user's DM relays
    final dmRelays = await _getDmRelays(pubkey);

    final baseFilter = ndk.Filter(
      kinds: [GiftWrap.kGiftWrapEventkind],
      pTags: [pubkey],
    );

    // Check if we have any existing fetched ranges
    final existingRanges = await _ndk.fetchedRanges.getForFilter(baseFilter);

    if (existingRanges.isEmpty) {
      // First sync - fetch the full range
      final filter = baseFilter.clone()
        ..since = effectiveSince
        ..until = effectiveUntil;
      await _fetchAndProcessEvents(filter, pubkey, relays: dmRelays);
      return;
    }

    // Get optimized filters that cover only the gaps (unfetched ranges)
    // since defaults to 0 (all history) for gap calculation
    final optimizedFilters = await _ndk.fetchedRanges.getOptimizedFilters(
      filter: baseFilter,
      since: effectiveSince ?? 0,
      until: effectiveUntil,
    );

    // If no gaps, nothing to sync
    if (optimizedFilters.isEmpty) return;

    // Fetch each gap
    for (final gapFilter in optimizedFilters.values.expand((f) => f)) {
      await _fetchAndProcessEvents(gapFilter, pubkey, relays: dmRelays);
    }
  }

  /// Fetch events from relays and process them
  Future<void> _fetchAndProcessEvents(
    ndk.Filter filter,
    String pubkey, {
    Iterable<String>? relays,
  }) async {
    final response = _ndk.requests.query(
      filter: filter,
      explicitRelays: relays,
    );

    await for (final event in response.stream) {
      if (await _store.isProcessed(event.id)) continue;

      try {
        final unwrapped = await _unwrapGiftWrap(event);
        if (unwrapped == null) continue;

        // Mark as processed to avoid re-decrypting non-email gift wraps (DMs, etc.)
        await _store.markProcessed(event.id);

        // Only process email events (kind 1301)
        if (unwrapped.kind != _emailKind) continue;

        final email = _parser.parse(
          rawContent: unwrapped.content,
          eventId: event.id,
          senderPubkey: unwrapped.pubKey,
          recipientPubkey: pubkey,
        );

        await _store.saveEmail(email);
      } catch (e) {
        continue;
      }
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
  Future<Nip01Event?> _unwrapGiftWrap(Nip01Event giftWrapEvent) async {
    try {
      final unwrapped = await _ndk.giftWrap.fromGiftWrap(
        giftWrap: giftWrapEvent,
      );
      return unwrapped;
    } catch (e) {
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
