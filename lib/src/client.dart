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

  /// Delete email from local DB
  Future<void> delete(String id) {
    return _store.deleteEmail(id);
  }

  /// Watch for new emails from relays (real-time)
  Stream<Email> watchInbox() async* {
    final pubkey = _ndk.accounts.getPublicKey();
    if (pubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }

    final response = _ndk.requests.subscription(
      filters: [
        ndk.Filter(kinds: [GiftWrap.kGiftWrapEventkind], pTags: [pubkey]),
      ],
    );

    await for (final event in response.stream) {
      // Skip already processed events
      if (await _store.isProcessed(event.id)) continue;

      try {
        // Unwrap the gift-wrapped event
        final unwrapped = await _unwrapGiftWrap(event);
        if (unwrapped == null || unwrapped.kind != _emailKind) continue;

        // Parse the email from RFC 2822 content
        final email = _parser.parse(
          rawContent: unwrapped.content,
          eventId: unwrapped.id,
          senderPubkey: unwrapped.pubKey,
          recipientPubkey: pubkey,
        );

        // Save to local DB and mark as processed
        await _store.saveEmail(email);
        await _store.markProcessed(event.id);

        yield email;
      } catch (e) {
        // Skip malformed events
        continue;
      }
    }
  }

  /// Sync emails from relays (fetch historical + store in DB)
  Future<void> sync() async {
    final pubkey = _ndk.accounts.getPublicKey();
    if (pubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }

    final response = _ndk.requests.query(
      filters: [
        ndk.Filter(kinds: [GiftWrap.kGiftWrapEventkind], pTags: [pubkey]),
      ],
    );

    await for (final event in response.stream) {
      if (await _store.isProcessed(event.id)) continue;

      try {
        final unwrapped = await _unwrapGiftWrap(event);
        if (unwrapped == null || unwrapped.kind != _emailKind) continue;

        final email = _parser.parse(
          rawContent: unwrapped.content,
          eventId: unwrapped.id,
          senderPubkey: unwrapped.pubKey,
          recipientPubkey: pubkey,
        );

        await _store.saveEmail(email);
        await _store.markProcessed(event.id);
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
}
