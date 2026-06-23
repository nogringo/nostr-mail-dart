import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart';

import '../exceptions.dart';
import '../models/resolved_recipient.dart';
import '../services/bridge_resolver.dart';

/// Resolve recipient address to a Nostr pubkey (and, for legacy recipients,
/// the bridge route).
///
/// Handles:
/// - npub (with or without @domain)
/// - hex pubkey (64 chars)
/// - NIP-05 (user@domain.com)
/// - Legacy email via bridge
/// - Formatted addresses: "Name" <address>
///
/// [to] The recipient address (npub, hex, or email)
/// [from] The sender's address (required for legacy email routing)
Future<ResolvedRecipient> resolveRecipient({
  required String to,
  required Ndk ndk,
  String? from,
  Map<String, String>? nip05Overrides,
}) async {
  final bridgeResolver = BridgeResolver(
    ndk: ndk,
    nip05Overrides: nip05Overrides,
  );

  // Try to parse formatted address (e.g., "Name" <address>)
  // If it fails, use the raw address
  String toAddress = to;
  try {
    final parsedTo = MailAddress.parse(to);
    toAddress = parsedTo.email;
  } catch (_) {
    // Not a valid mail address format, use raw to
  }

  // Extract bech32 part (before @ if present)
  final bech32Part = toAddress.split('@').first;

  // Check if it's an npub
  if (toAddress.startsWith('npub1')) {
    try {
      return ResolvedRecipient(pubkey: Nip19.decode(bech32Part));
    } catch (e) {
      throw RecipientResolutionException(to);
    }
  }

  // Check if it's a 64-char hex pubkey
  if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(toAddress)) {
    return ResolvedRecipient(pubkey: toAddress.toLowerCase());
  }

  // It's an email format - try NIP-05 first
  if (toAddress.contains('@')) {
    final nip05Pubkey = await bridgeResolver.resolveNip05(toAddress);
    if (nip05Pubkey != null) {
      return ResolvedRecipient(pubkey: nip05Pubkey);
    }

    // NIP-05 failed, route via bridge at sender's domain
    if (from == null) {
      throw NostrMailException(
        'from address is required when sending to legacy email addresses',
      );
    }

    // Extract email address from formatted address (e.g., "Name" <email@domain>)
    final parsedFrom = MailAddress.parse(from);
    final fromEmail = parsedFrom.email;

    if (!fromEmail.contains('@')) {
      throw NostrMailException(
        'from address is required when sending to legacy email addresses',
      );
    }

    final domain = fromEmail.split('@').last;
    final bridgePubkey = await bridgeResolver.resolveBridgePubkey(domain);
    return ResolvedRecipient(pubkey: bridgePubkey, legacyAddress: toAddress);
  }

  throw RecipientResolutionException(to);
}
