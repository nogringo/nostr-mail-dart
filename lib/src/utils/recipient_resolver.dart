import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/entities.dart' as ndk_entities;
import 'package:ndk/ndk.dart';

import '../exceptions.dart';
import '../models/recipient.dart';

/// Resolves a NIP-05 identifier to a typed result. Injectable for tests.
typedef NdkNip05Resolver =
    Future<ndk_entities.Nip05ResolveResult> Function(String identifier);

/// Classify a recipient address into an explicit [Recipient].
///
/// Convenience for callers that only have a raw address; the send path itself
/// takes already-resolved [Recipient]s.
///
/// - npub / hex / `npub@domain` -> [NostrRecipient] (no network)
/// - `user@domain`:
///   - NIP-05 found -> [NostrRecipient]
///   - NIP-05 not found (server reachable, name absent) -> [SmtpRecipient]
///   - network error or malformed response -> throws, rather than guessing a
///     transport. A transient NIP-05 failure must never silently route a Nostr
///     recipient to the SMTP bridge.
Future<Recipient> resolveRecipient({
  required String to,
  required Ndk ndk,
  Map<String, String>? nip05Overrides,
  NdkNip05Resolver? nip05Resolver,
}) async {
  // Accept formatted addresses ("Name" <address>); fall back to the raw value.
  String toAddress = to;
  try {
    toAddress = MailAddress.parse(to).email;
  } catch (_) {
    // Not a formatted address; use the raw value.
  }

  final mailAddress = MailAddress(null, toAddress);
  final bech32Part = toAddress.split('@').first;

  if (toAddress.startsWith('npub1')) {
    try {
      return NostrRecipient(
        pubkey: Nip19.decode(bech32Part),
        mailAddress: mailAddress,
      );
    } catch (_) {
      throw RecipientResolutionException(to);
    }
  }

  if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(toAddress)) {
    return NostrRecipient(
      pubkey: toAddress.toLowerCase(),
      mailAddress: mailAddress,
    );
  }

  if (toAddress.contains('@')) {
    if (nip05Overrides != null && nip05Overrides.containsKey(toAddress)) {
      return NostrRecipient(
        pubkey: nip05Overrides[toAddress]!,
        mailAddress: mailAddress,
      );
    }

    final result = await (nip05Resolver ?? ndk.nip05.resolve)(toAddress);
    return switch (result) {
      ndk_entities.Nip05Found(:final data) => NostrRecipient(
        pubkey: data.pubKey,
        mailAddress: mailAddress,
      ),
      ndk_entities.Nip05NotFound() => SmtpRecipient.fromMailAddress(mailAddress),
      ndk_entities.Nip05ResolveNetworkError() ||
      ndk_entities.Nip05ResolveInvalidResponse() => throw NostrMailException(
        'Cannot classify "$toAddress": its NIP-05 lookup failed. Pass an '
        'explicit NostrRecipient or SmtpRecipient instead of a raw address.',
      ),
    };
  }

  throw RecipientResolutionException(to);
}
