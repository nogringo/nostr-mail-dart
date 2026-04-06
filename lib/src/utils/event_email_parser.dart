import 'dart:convert';

import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart';

import '../constants.dart';
import '../exceptions.dart';
import '../models/email.dart';
import 'decrypt_blob.dart';

/// Parse a NIP-01 event (kind 1301) into a local [Email] object.
///
/// Handles both inline and Blossom emails automatically:
/// - **Inline emails (< 32KB)**: MIME is in `event.content`
/// - **Blossom emails (≥ 32KB)**: MIME is downloaded from Blossom and decrypted
///
/// ## Usage
/// ```dart
/// final email = await parseEmailEvent(
///   event: event,
///   ndk: ndk,
///   recipientPubkey: pubkey,
/// );
/// ```
///
/// ## Parameters
/// - [event]: The unwrapped NIP-01 event (kind 1301)
/// - [ndk]: NDK instance for Blossom operations
/// - [recipientPubkey]: The recipient's pubkey (for local storage metadata)
///
/// ## Returns
/// A fully parsed [Email] object ready for local storage and display.
///
/// ## Throws
/// [EmailParseException] if:
/// - Blossom download fails
/// - Decryption fails
/// - MIME parsing fails
Future<Email> parseEmailEvent({
  required Nip01Event event,
  required Ndk ndk,
  required String recipientPubkey,
}) async {
  // Extract Blossom tags (NIP-17 style)
  final blossomHash = event.getFirstTag('x');
  final decryptionKey = event.getFirstTag('decryption-key');
  final decryptionNonce = event.getFirstTag('decryption-nonce');

  // Parse MIME (inline or from Blossom)
  final mimeString = await _parseMime(
    ndk: ndk,
    rawContent: event.content,
    blossomHash: blossomHash,
    decryptionKey: decryptionKey,
    decryptionNonce: decryptionNonce,
    recipientPubkey: recipientPubkey,
  );

  // Parse RFC 2822 MIME
  final mimeMessage = MimeMessage.parseFromText(mimeString);

  return Email(
    id: event.id,
    senderPubkey: event.pubKey,
    recipientPubkey: recipientPubkey,
    rawContent: mimeString,
    createdAt: DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
    mimeMessage: mimeMessage,
  );
}

/// Internal: Parse MIME from inline content or Blossom.
///
/// Returns the unfolded MIME string.
Future<String> _parseMime({
  required Ndk ndk,
  required String rawContent,
  required String recipientPubkey,
  String? blossomHash,
  String? decryptionKey,
  String? decryptionNonce,
}) async {
  if (rawContent.isEmpty && blossomHash != null) {
    // Get recipient's Blossom servers (BUD-03) or use default
    final blossomServers = await ndk.blossomUserServerList.getUserServerList(
      pubkeys: [recipientPubkey],
    );

    // Download from recipient's servers or default
    final downloadResult = await ndk.blossom.getBlob(
      sha256: blossomHash,
      serverUrls: blossomServers ?? defaultBlossomServers,
    );

    if (decryptionKey == null || decryptionNonce == null) {
      throw EmailParseException(
        'Missing decryption key or nonce for Blossom email (hash: $blossomHash)',
      );
    }

    // Decrypt with AES-GCM
    final decryptedBytes = await decryptBlob(
      encryptedBytes: downloadResult.data,
      key: decryptionKey,
      nonce: decryptionNonce,
    );

    return utf8.decode(decryptedBytes);
  }

  // Inline email: unfold headers and return
  return rawContent.replaceAll(RegExp(r'\r?\n[ \t]+'), '');
}
