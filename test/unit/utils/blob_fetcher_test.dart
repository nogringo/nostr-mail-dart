import 'dart:typed_data';

import 'package:ndk/ndk.dart';
import 'package:nostr_mail/src/utils/blob_fetcher.dart';
import 'package:test/test.dart';

import '../../helpers/test_blossom_cache.dart';

void main() {
  test('a blob stays pinned until every account reading it lets go', () async {
    final cache = await openTestBlossomCache('blob_fetcher_pins');
    final ndk = Ndk(
      NdkConfig(
        eventVerifier: Bip340EventVerifier(),
        cache: MemCacheManager(),
        bootstrapRelays: [],
      ),
    );
    addTearDown(ndk.destroy);

    final blob = await cache.put(Uint8List.fromList([1, 2, 3]));
    for (final pubkey in ['alice', 'bob']) {
      await fetchOrLoadEncryptedBlob(
        blossomHash: blob.sha256,
        serverUrls: const [],
        cache: cache,
        ndk: ndk,
        pubkey: pubkey,
      );
    }

    await cache.unpinAll(blobPinHolder('alice'));
    expect((await cache.head(blob.sha256))!.pinnedBy, {blobPinHolder('bob')});
  });
}
