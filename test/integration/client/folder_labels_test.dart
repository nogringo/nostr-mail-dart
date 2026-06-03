import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:test/test.dart';

import '../../helpers/test_blossom_cache.dart';
import '../../mocks/mock_relay.dart';

void main() {
  group('Folder label mutual exclusion', () {
    late Ndk ndk;
    late NostrMailClient client;
    late MockRelay relay;

    setUp(() async {
      relay = MockRelay(name: 'relay', explicitPort: 19013);
      await relay.startServer();

      final db = await databaseFactoryMemory.openDatabase(
        'test_db_${DateTime.now().microsecondsSinceEpoch}',
      );
      ndk = Ndk(
        NdkConfig(
          bootstrapRelays: [relay.url],
          eventVerifier: Bip340EventVerifier(),
          cache: MemCacheManager(),
          fetchedRangesEnabled: true,
        ),
      );

      final keyPair = Bip340.generatePrivateKey();
      ndk.accounts.loginPrivateKey(
        pubkey: keyPair.publicKey,
        privkey: keyPair.privateKey!,
      );

      client = await NostrMailClient.create(
        ndk: ndk,
        db: db,
        blossomCache: await openTestBlossomCache('folder_labels_test'),
        defaultDmRelays: [relay.url],
      );
    });

    tearDown(() async {
      await ndk.destroy();
      await relay.stopServer();
    });

    test('moveToTrash removes a previously-set folder:archive label', () async {
      const emailId = 'test-email-1';

      await client.moveToArchive(emailId);

      expect(await client.isArchived(emailId), isTrue);
      expect(await client.isTrashed(emailId), isFalse);

      await client.moveToTrash(emailId);

      expect(await client.isArchived(emailId), isFalse);
      expect(await client.isTrashed(emailId), isTrue);

      final labels = await client.getLabels(emailId);
      expect(labels, ['folder:trash']);
    });
  });
}
