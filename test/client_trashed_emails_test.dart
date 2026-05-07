import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:nostr_mail/src/storage/email_repository.dart';
import 'package:nostr_mail/src/storage/label_repository.dart';
import 'package:nostr_mail/src/storage/models/email_record.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:test/test.dart';

void main() {
  group('NostrMailClient - Trashed Emails', () {
    late Ndk ndk;
    late NostrMailClient client;
    late EmailRepository emailRepo;
    late LabelRepository labelRepo;

    setUp(() async {
      final db = await databaseFactoryMemory.openDatabase(
        'test_db_${DateTime.now().microsecondsSinceEpoch}',
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

      emailRepo = EmailRepository(db);
      labelRepo = LabelRepository(db);
      client = NostrMailClient(ndk: ndk, db: db);
    });

    tearDown(() async {
      await ndk.destroy();
    });

    EmailRecord createTestRecord(String id, {int? date}) {
      return EmailRecord(
        id: id,
        senderPubkey: 'sender-pubkey',
        recipientPubkey: 'recipient-pubkey',
        rawContent: 'From: from@test.com\r\nSubject: Test\r\n\r\nTest Body',
        isPublic: false,
        createdAt: date ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
        date: date ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
        from: 'from@test.com',
        subject: 'Test',
        bodyPlain: 'Test Body',
        searchText: 'from@test.com test test body',
        attachmentCount: 0,
        folder: 'inbox',
        isRead: false,
        isStarred: false,
        labels: [],
        isBridged: false,
      );
    }

    test('getTrashedEmailsOlderThan returns only old trashed emails', () async {
      final now = DateTime.now();
      final currentTimestamp = now.millisecondsSinceEpoch ~/ 1000;
      final oldTimestamp =
          now.subtract(const Duration(days: 35)).millisecondsSinceEpoch ~/ 1000;

      final oldRecord = createTestRecord('old-email-id', date: oldTimestamp);
      final newRecord = createTestRecord(
        'new-email-id',
        date: currentTimestamp,
      );

      await emailRepo.save(oldRecord);
      await emailRepo.save(newRecord);

      // Add labels manually to control the timestamp
      await labelRepo.saveLabel(
        emailId: oldRecord.id,
        label: 'folder:trash',
        labelEventId: 'label-event-old',
        timestamp: oldTimestamp,
      );

      await labelRepo.saveLabel(
        emailId: newRecord.id,
        label: 'folder:trash',
        labelEventId: 'label-event-new',
        timestamp: currentTimestamp,
      );

      final oldTrashedEmails = await client.getTrashedEmailsOlderThan(
        const Duration(days: 30),
      );

      expect(oldTrashedEmails.length, 1);
      expect(oldTrashedEmails.first.id, oldRecord.id);
    });
  });
}
