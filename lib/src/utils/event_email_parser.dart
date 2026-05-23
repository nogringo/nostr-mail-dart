import 'dart:convert';
import 'dart:typed_data';

import 'package:blossom_cache/blossom_cache.dart';
import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart';

import '../constants.dart';
import '../exceptions.dart';
import '../models/email.dart';
import 'attachment_extractor.dart';
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
  required BlossomCache blossomCache,
  bool isPublic = false,
  List<String>? defaultBlossomServers,
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
    defaultBlossomServers: defaultBlossomServers,
    blossomCache: blossomCache,
  );

  // Parse RFC 2822 MIME, extract attachments into the blob cache, and keep
  // a light envelope (headers + bodies) for fast querying.
  final mimeMessage = MimeMessage.parseFromText(mimeString);
  final extracted = await extractAttachments(
    mime: mimeMessage,
    cache: blossomCache,
  );

  return Email(
    id: event.id,
    senderPubkey: event.pubKey,
    recipientPubkey: recipientPubkey,
    lightMimeText: extracted.lightMimeText,
    attachmentRefs: extracted.refs,
    blossomHash: blossomHash,
    decryptionKey: decryptionKey,
    decryptionNonce: decryptionNonce,
    createdAt: DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
    isPublic: isPublic,
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
  required BlossomCache blossomCache,
  String? blossomHash,
  String? decryptionKey,
  String? decryptionNonce,
  List<String>? defaultBlossomServers,
}) async {
  if (rawContent.isEmpty && blossomHash != null) {
    if (decryptionKey == null || decryptionNonce == null) {
      throw EmailParseException(
        'Missing decryption key or nonce for Blossom email (hash: $blossomHash)',
      );
    }

    // Source-of-truth blob is pinned: if it ever gets evicted we lose the
    // ability to reconstruct attachments without going back to the relays.
    Uint8List? encryptedBytes = await blossomCache.get(blossomHash);

    if (encryptedBytes == null) {
      // Get recipient's Blossom servers (BUD-03) or use default
      final blossomServers = await ndk.blossomUserServerList.getUserServerList(
        pubkeys: [recipientPubkey],
      );

      // Download from recipient's servers or default
      final downloadResult = await ndk.blossom.getBlob(
        sha256: blossomHash,
        serverUrls:
            blossomServers ??
            defaultBlossomServers ??
            recommendedBlossomServers,
      );
      encryptedBytes = downloadResult.data;

      await blossomCache.put(
        encryptedBytes,
        sha256: blossomHash,
        type: 'application/octet-stream',
        pinned: true,
      );
    }

    // Decrypt with AES-GCM
    final decryptedBytes = await decryptBlob(
      encryptedBytes: encryptedBytes,
      key: decryptionKey,
      nonce: decryptionNonce,
    );

    return utf8.decode(decryptedBytes);
  }

  return rawContent;
}
