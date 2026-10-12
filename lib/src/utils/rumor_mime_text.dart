import 'dart:convert';

import 'package:blossom_cache/blossom_cache.dart';
import 'package:ndk/ndk.dart';

import 'blob_fetcher.dart';
import 'decrypt_blob.dart';

/// The MIME text a rumor carries: inline in its `content`, or an encrypted
/// Blossom blob referenced by its `x`/`decryption-*` tags, pinned for
/// [pinFor].
///
/// Null when the rumor carries no text, or when its Blossom reference lacks a
/// key or nonce. Throws when the blob is neither cached nor downloadable.
Future<String?> rumorMimeText(
  Nip01Event rumor, {
  required Ndk ndk,
  required BlossomCache cache,
  required String pinFor,
  List<String>? defaultBlossomServers,
}) async {
  final hash = rumor.getFirstTag('x');
  if (hash == null) return rumor.content.isEmpty ? null : rumor.content;
  final key = rumor.getFirstTag('decryption-key');
  final nonce = rumor.getFirstTag('decryption-nonce');
  if (key == null || nonce == null) return null;
  final encrypted = await fetchOrLoadEncryptedBlob(
    blossomHash: hash,
    involvedPubkeys: [rumor.pubKey],
    defaultBlossomServers: defaultBlossomServers,
    cache: cache,
    ndk: ndk,
    pinFor: pinFor,
  );
  final decrypted = await decryptBlob(
    encryptedBytes: encrypted,
    key: key,
    nonce: nonce,
  );
  return utf8.decode(decrypted);
}
