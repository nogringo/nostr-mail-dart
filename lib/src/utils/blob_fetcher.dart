import 'dart:typed_data';

import 'package:blossom_cache/blossom_cache.dart';
import 'package:ndk/ndk.dart';

import '../constants.dart';

/// The [BlossomCache] pin holder for [pubkey]'s blobs. Prefixed because the
/// cache belongs to the caller and may be shared with other consumers.
String blobPinHolder(String pubkey) => 'nostr_mail:$pubkey';

/// Return the encrypted Blossom blob for [blossomHash], pinned on behalf of
/// [pubkey] so it is exempt from LRU eviction until that account releases it.
///
/// Fast path: read from [cache] if present.
///
/// Slow path: download from [serverUrls], then store the bytes in [cache].
///
/// Throws whatever the underlying [Ndk.blossom.getBlob] call throws when no
/// server in [serverUrls] holds the blob.
Future<Uint8List> fetchOrLoadEncryptedBlob({
  required String blossomHash,
  required List<String> serverUrls,
  required BlossomCache cache,
  required Ndk ndk,
  required String pubkey,
}) async {
  final cached = await cache.get(blossomHash);
  if (cached != null) {
    // Another account may hold the only pin and release it on logout.
    await cache.pin(blossomHash, by: blobPinHolder(pubkey));
    return cached;
  }

  final downloadResult = await ndk.blossom.getBlob(
    sha256: blossomHash,
    serverUrls: serverUrls,
  );

  await cache.put(
    downloadResult.data,
    sha256: blossomHash,
    type: 'application/octet-stream',
    pinBy: blobPinHolder(pubkey),
  );

  return downloadResult.data;
}

/// Build the ordered, deduplicated list of Blossom servers to query when
/// downloading a blob involving [pubkeys].
///
/// Order of priority:
/// 1. BUD-03 published servers for every involved pubkey (sender plus
///    recipients). Including every involved pubkey mirrors the upload
///    policy and protects against the case where the recipient never
///    published a list but the sender did.
/// 2. [defaultBlossomServers] supplied by the consumer (typically a test
///    injection point, or an organization's preferred servers).
/// 3. [recommendedBlossomServers] as a public last resort.
///
/// All three are merged into a single deduplicated list so the actual
/// fetch hits every plausible source rather than committing to one tier.
/// Blossom blobs are content-addressed and un-authenticated, so any server
/// holding the bytes can serve them.
Future<List<String>> resolveBlobServers({
  required Ndk ndk,
  required List<String> pubkeys,
  List<String>? defaultBlossomServers,
}) async {
  // LinkedHashSet preserves first-insertion order while deduping.
  final ordered = <String>{};
  final published = await ndk.blossomUserServerList.getUserServerList(
    pubkeys: pubkeys,
  );
  if (published != null) ordered.addAll(published);
  if (defaultBlossomServers != null) ordered.addAll(defaultBlossomServers);
  ordered.addAll(recommendedBlossomServers);
  return ordered.toList();
}
