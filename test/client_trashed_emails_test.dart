import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:nostr_mail/src/storage/email_store.dart';
import 'package:nostr_mail/src/storage/label_store.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:test/test.dart';

void main() {
  group('NostrMailClient - Trashed Emails', () {
    late Ndk ndk;
    late NostrMailClient client;
    late EmailStore emailStore;
    late LabelStore labelStore;

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

      emailStore = EmailStore(db);
      labelStore = LabelStore(db);
      client = NostrMailClient(ndk: ndk, db: db);
    });

    tearDown(() async {
      await ndk.destroy();
    });

    Email createTestEmail(String id) {
      final parser = EmailParser();
      final rawContent = parser.build(
        from: MailAddress(null, 'from@test.com'),
        to: [MailAddress(null, 'to@test.com')],
        subject: 'Test Subject',
        body: 'Test Body',
      );
      return Email(
        id: id,
        senderPubkey: 'sender-pubkey',
        recipientPubkey: 'recipient-pubkey',
        rawContent: rawContent,
        createdAt: DateTime.now(),
        isPublic: false,
      );
    }

    test('getTrashedEmailsOlderThan returns only old trashed emails', () async {
      // 1. Create two emails
      final oldEmail = createTestEmail('old-email-id');
      final newEmail = createTestEmail('new-email-id');

      await emailStore.saveEmail(oldEmail);
      await emailStore.saveEmail(newEmail);

      final now = DateTime.now();
      final currentTimestamp = now.millisecondsSinceEpoch ~/ 1000;
      final oldTimestamp =
          now.subtract(const Duration(days: 35)).millisecondsSinceEpoch ~/ 1000;

      // 2. Add labels manually to control the timestamp
      await labelStore.saveLabel(
        emailId: oldEmail.id,
        label: 'folder:trash',
        labelEventId: 'label-event-old',
        timestamp: oldTimestamp,
      );

      await labelStore.saveLabel(
        emailId: newEmail.id,
        label: 'folder:trash',
        labelEventId: 'label-event-new',
        timestamp: currentTimestamp,
      );

      // 3. Query emails older than 30 days
      final oldTrashedEmails = await client.getTrashedEmailsOlderThan(
        const Duration(days: 30),
      );

      // 4. Verify results
      expect(oldTrashedEmails.length, 1);
      expect(oldTrashedEmails.first.id, oldEmail.id);
    });
  });
}
