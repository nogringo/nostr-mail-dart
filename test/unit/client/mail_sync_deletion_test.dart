// A deletion names the gift wrap a relay holds, while every other device of
// the account stores the email under the rumor id inside it.

import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:nostr_mail/src/client/event_bus.dart';
import 'package:nostr_mail/src/client/mail_sync.dart';
import 'package:nostr_mail/src/client/relay_resolver.dart';
import 'package:nostr_mail/src/storage/email_repository.dart';
import 'package:nostr_mail/src/storage/gift_wrap_repository.dart';
import 'package:nostr_mail/src/storage/label_repository.dart';
import 'package:nostr_mail/src/storage/models/email_record.dart';
import 'package:nostr_mail/src/storage/tombstone_repository.dart';
import 'package:sembast/sembast_memory.dart' hide Filter;
import 'package:sync_engine_shim_for_ndk/sync_engine_shim_for_ndk.dart';
import 'package:test/test.dart';

import '../../helpers/test_blossom_cache.dart';
import '../../helpers/test_database.dart';

void main() {
  group('MailSync.onDeletion', () {
    late NostrMailDatabase database;
    late Database db;
    late Ndk ndk;
    late EmailRepository emails;
    late GiftWrapRepository giftWraps;
    late TombstoneRepository tombstones;
    late SyncEngine engine;
    late MailSync sync;
    late String alice;

    const emailId = 'rumor-1';
    const wrapId = 'wrap-1';

    setUp(() async {
      db = await databaseFactoryMemory.openDatabase(
        'deletion_${DateTime.now().microsecondsSinceEpoch}',
      );

      ndk = Ndk(
        NdkConfig(
          eventVerifier: Bip340EventVerifier(),
          cache: MemCacheManager(),
          bootstrapRelays: const [],
        ),
      );

      final aliceKeys = Bip340.generatePrivateKey();
      alice = aliceKeys.publicKey;
      ndk.accounts.loginPrivateKey(
        pubkey: alice,
        privkey: aliceKeys.privateKey!,
      );

      database = testDatabase();
      emails = EmailRepository(database);
      giftWraps = GiftWrapRepository(database);
      tombstones = TombstoneRepository(database);
      engine = SyncEngine(ndk, db: db);
      sync = MailSync(
        ndk,
        engine,
        emails,
        LabelRepository(database),
        giftWraps,
        tombstones,
        EventBus(),
        RelayResolver(ndk),
        blossomCache: await openTestBlossomCache('deletion_test'),
      );

      await giftWraps.saveOpened(
        Nip01Event(
          id: wrapId,
          pubKey: 'ephemeral-pubkey',
          createdAt: 1000,
          kind: giftWrapKind,
          tags: [
            ['p', alice],
          ],
          content: 'encrypted',
          sig: 'sig',
        ),
        recipientPubkey: alice,
        seal: Nip01Event(
          pubKey: 'sender-pubkey',
          createdAt: 1000,
          kind: 13,
          tags: const [],
          content: 'sealed',
        ),
        rumor: Nip01Event(
          id: emailId,
          pubKey: 'sender-pubkey',
          createdAt: 1000,
          kind: emailKind,
          tags: const [],
          content: 'mime',
        ),
      );
      await emails.save(
        EmailRecord(
          id: emailId,
          senderPubkey: 'sender-pubkey',
          recipientPubkey: alice,
          lightMimeText: 'From: from@test.com\r\nSubject: Test\r\n\r\nBody',
          attachmentRefs: const [],
          isPublic: false,
          createdAt: 1000,
          date: 1000,
          from: 'from@test.com',
          subject: 'Test',
          bodyPlain: 'Body',
          folder: 'inbox',
          isBridged: false,
        ),
      );
    });

    tearDown(() async {
      await engine.dispose();
      await ndk.destroy();
      await db.close();
    });

    Nip01Event deletionOf(String targetId) => Nip01Event(
      pubKey: alice,
      createdAt: 1000,
      kind: deletionRequestKind,
      tags: [
        ['e', targetId],
        ['k', giftWrapKind.toString()],
      ],
      content: '',
      sig: 'sig',
    );

    test('removes the email carried by the wrap it names', () async {
      await sync.onDeletion(deletionOf(wrapId));

      expect(await emails.getById(emailId, recipientPubkey: alice), isNull);
      expect(await giftWraps.getById(wrapId), isNull);
      expect(
        await tombstones.contains(emailId, recipientPubkey: alice),
        isTrue,
      );
    });

    test('still removes an email named by its rumor id', () async {
      await sync.onDeletion(deletionOf(emailId));

      expect(await emails.getById(emailId, recipientPubkey: alice), isNull);
      expect(await tombstones.contains(wrapId, recipientPubkey: alice), isTrue);
    });
  });
}
