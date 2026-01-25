import 'dart:async';

import 'package:ndk/ndk.dart' hide Filter;
import 'package:ndk/domain_layer/entities/filter.dart' as ndk;
import 'package:sembast/sembast.dart';

import 'exceptions.dart';
import 'models/email.dart';
import 'services/bridge_resolver.dart';
import 'services/email_parser.dart';
import 'storage/email_store.dart';

const _emailKind = 1301;
const _dmRelayListKind = 10050;
const _deletionRequestKind = 5;
const _giftWrapKind = 1059;
const _defaultDmRelays = [
  'wss://auth.nostr1.com',
  'wss://nostr-01.uid.ovh',
  'wss://nostr-02.uid.ovh',
];

class NostrMailClient {
  final Ndk _ndk;
  final EmailStore _store;
  final EmailParser _parser;
  final BridgeResolver _bridgeResolver;

  NostrMailClient({required Ndk ndk, required Database db})
    : _ndk = ndk,
      _store = EmailStore(db),
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
    final event = events.reduce(
      (a, b) => a.createdAt > b.createdAt ? a : b,
    );

    final relays = event.tags
        .where((t) => t.isNotEmpty && t[0] == 'relay')
        .map((t) => t[1])
        .toList();

    return relays.isNotEmpty ? relays : _defaultDmRelays;
  }
}
