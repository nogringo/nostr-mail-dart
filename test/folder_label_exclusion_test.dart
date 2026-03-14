import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:test/test.dart';

void main() {
  group('Folder Label Mutual Exclusion Bug', () {
    late Ndk ndk;
    late NostrMailClient client;

    setUp(() async {
      final db = await databaseFactoryMemory.openDatabase(
        'test_db_${DateTime.now().millisecondsSinceEpoch}',
      );
      ndk = Ndk(
        NdkConfig(
          bootstrapRelays: ['wss://nostr-01.uid.ovh'],
          eventVerifier: Bip340EventVerifier(),
          cache: MemCacheManager(),
        ),
      );

      final keyPair = Bip340.generatePrivateKey();
      ndk.accounts.loginPrivateKey(
        pubkey: keyPair.publicKey,
        privkey: keyPair.privateKey!,
      );

      client = NostrMailClient(ndk: ndk, db: db);
    });

    tearDown(() async {
      await ndk.destroy();
    });

    test('adding folder:trash should remove folder:archive label', () async {
      final emailId = 'test-email-1';

      await client.moveToArchive(emailId);

      bool isArchived = await client.isArchived(emailId);
      bool isTrashed = await client.isTrashed(emailId);
      expect(isArchived, isTrue);
      expect(isTrashed, isFalse);

      await client.moveToTrash(emailId);

      isArchived = await client.isArchived(emailId);
      isTrashed = await client.isTrashed(emailId);

      expect(isArchived, isFalse);
      expect(isTrashed, isTrue);

      final labels = await client.getLabels(emailId);

      expect(labels.length, 1);
      expect(labels, isNot(contains('folder:archive')));
      expect(labels, contains('folder:trash'));
    });
  });
}
