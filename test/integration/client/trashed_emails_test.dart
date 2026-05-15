import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:nostr_mail/src/storage/email_repository.dart';
import 'package:nostr_mail/src/storage/label_repository.dart';
import 'package:nostr_mail/src/storage/models/email_record.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:test/test.dart';

import '../../mocks/mock_relay.dart';

void main() {
  group('NostrMailClient.getTrashedEmailsOlderThan', () {
    late Ndk ndk;
    late NostrMailClient client;
    late EmailRepository emailRepo;
    late LabelRepository labelRepo;
    late MockRelay relay;
    late String accountPubkey;

    setUp(() async {
      relay = MockRelay(name: 'relay', explicitPort: 19015);
      await relay.startServer();

      final db = await databaseFactoryMemory.openDatabase(
        'test_db_${DateTime.now().microsecondsSinceEpoch}',
      );
      ndk = Ndk(
        NdkConfig(
          bootstrapRelays: [relay.url],
          eventVerifier: Bip340EventVerifier(),
          cache: MemCacheManager(),
        ),
      );

      final keyPair = Bip340.generatePrivateKey();
      accountPubkey = keyPair.publicKey;
      ndk.accounts.loginPrivateKey(
        pubkey: keyPair.publicKey,
        privkey: keyPair.privateKey!,
      );

      emailRepo = EmailRepository(db);
      labelRepo = LabelRepository(db);
      client = await NostrMailClient.create(
        ndk: ndk,
        db: db,
        defaultDmRelays: [relay.url],
      );
    });

    tearDown(() async {
      await ndk.destroy();
      await relay.stopServer();
    });

    EmailRecord makeRecord(String id, {int? date}) {
      final ts = date ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return EmailRecord(
        id: id,
        senderPubkey: 'sender-pubkey',
        recipientPubkey: accountPubkey,
        rawContent: 'From: from@test.com\r\nSubject: Test\r\n\r\nTest Body',
        isPublic: false,
        createdAt: ts,
        date: ts,
        from: 'from@test.com',
        subject: 'Test',
        bodyPlain: 'Test Body',
        searchText: 'from@test.com test test body',
        attachmentCount: 0,
        folder: 'inbox',
        isRead: false,
        isStarred: false,
        labels: const [],
        isBridged: false,
      );
    }

    test('returns only emails trashed before the threshold', () async {
      final now = DateTime.now();
      final currentTimestamp = now.millisecondsSinceEpoch ~/ 1000;
      final oldTimestamp =
          now.subtract(const Duration(days: 35)).millisecondsSinceEpoch ~/ 1000;

      await emailRepo.save(makeRecord('old-email-id', date: oldTimestamp));
      await emailRepo.save(makeRecord('new-email-id', date: currentTimestamp));

      // Add labels manually to control the timestamp.
      await labelRepo.saveLabel(
        emailId: 'old-email-id',
        label: 'folder:trash',
        labelEventId: 'label-event-old',
        timestamp: oldTimestamp,
        recipientPubkey: accountPubkey,
      );

      await labelRepo.saveLabel(
        emailId: 'new-email-id',
        label: 'folder:trash',
        labelEventId: 'label-event-new',
        timestamp: currentTimestamp,
        recipientPubkey: accountPubkey,
      );

      final old = await client.getTrashedEmailsOlderThan(
        const Duration(days: 30),
      );

      expect(old, hasLength(1));
      expect(old.first.id, 'old-email-id');
    });
  });
}
