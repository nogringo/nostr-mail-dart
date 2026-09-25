// A label travels signed inside a gift wrap addressed to the account, without
// a seal, and is removed by a deletion naming the wrap (nostr-mail-labels).

import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:ndk/shared/nips/nip01/key_pair.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:nostr_mail/src/client/event_bus.dart';
import 'package:nostr_mail/src/client/mail_sync.dart';
import 'package:nostr_mail/src/client/relay_resolver.dart';
import 'package:nostr_mail/src/storage/email_repository.dart';
import 'package:nostr_mail/src/storage/gift_wrap_repository.dart';
import 'package:nostr_mail/src/storage/label_repository.dart';
import 'package:nostr_mail/src/storage/tombstone_repository.dart';
import 'package:sembast/sembast_memory.dart' hide Filter;
import 'package:sync_engine_shim_for_ndk/sync_engine_shim_for_ndk.dart';
import 'package:test/test.dart';

import '../../helpers/test_blossom_cache.dart';
import '../../helpers/test_database.dart';

void main() {
  group('MailSync wrapped labels', () {
    late Database db;
    late Ndk ndk;
    late LabelRepository labels;
    late GiftWrapRepository giftWraps;
    late SyncEngine engine;
    late MailSync sync;
    late KeyPair aliceKeys;
    late String alice;

    const emailId = 'email-1';

    setUp(() async {
      db = await databaseFactoryMemory.openDatabase(
        'wrapped_label_${DateTime.now().microsecondsSinceEpoch}',
      );

      ndk = Ndk(
        NdkConfig(
          eventVerifier: Bip340EventVerifier(),
          cache: MemCacheManager(),
          bootstrapRelays: const [],
        ),
      );

      aliceKeys = Bip340.generatePrivateKey();
      alice = aliceKeys.publicKey;
      ndk.accounts.loginPrivateKey(
        pubkey: alice,
        privkey: aliceKeys.privateKey!,
      );

      final database = testDatabase();
      labels = LabelRepository(database);
      giftWraps = GiftWrapRepository(database);
      engine = SyncEngine(ndk, db: db);
      sync = MailSync(
        ndk,
        engine,
        EmailRepository(database),
        labels,
        giftWraps,
        TombstoneRepository(database),
        EventBus(),
        RelayResolver(ndk),
        blossomCache: await openTestBlossomCache('wrapped_label_test'),
      );
    });

    tearDown(() async {
      await engine.dispose();
      await ndk.destroy();
      await db.close();
    });

    /// A label on [emailId] signed with [signer], claiming [author], wrapped
    /// to alice.
    Future<Nip01Event> wrappedLabel(
      String label, {
      KeyPair? signer,
      String? author,
      int createdAt = 1000,
      List<List<String>> extraTags = const [],
    }) async {
      final event = Nip01Event(
        pubKey: author ?? alice,
        kind: labelKind,
        createdAt: createdAt,
        tags: [
          ['L', labelNamespace],
          ['l', label, labelNamespace],
          ['e', emailId, '', 'labelled'],
          ...extraTags,
        ],
        content: '',
      );
      final signed = event.copyWith(
        sig: Bip340.sign(event.id, (signer ?? aliceKeys).privateKey!),
      );
      return GiftWrap.wrapEvent(
        recipientPublicKey: alice,
        sealEvent: signed,
        eventSignerFactory: ndk.giftWrap.eventSignerFactory,
        randomizeCreatedAtBefore: createdAt,
      );
    }

    Nip01Event deletionOf(String wrapId) => Nip01Event(
      id: 'deletion-of-$wrapId',
      pubKey: alice,
      createdAt: 1000,
      kind: deletionRequestKind,
      tags: [
        ['e', wrapId],
        ['k', giftWrapKind.toString()],
      ],
      content: '',
      sig: 'sig',
    );

    Future<bool> isRead() =>
        labels.hasLabel(emailId, 'state:read', recipientPubkey: alice);

    test('a wrapped label is applied and deleted by its wrap', () async {
      final wrap = await wrappedLabel('state:read');

      await sync.onGiftWrap(wrap);

      expect(await isRead(), isTrue);
      final row = await labels.getLabelEvent(wrap.id, recipientPubkey: alice);
      expect(row?.wrapId, wrap.id);
      expect((await giftWraps.getById(wrap.id))!['stage'], 'stored');

      await sync.onDeletion(deletionOf(wrap.id));
      expect(await isRead(), isFalse);
    });

    test('a trash label keeps the folder the email left', () async {
      final wrap = await wrappedLabel(
        'folder:trash',
        extraTags: [
          ['prev-folder', '9f2c1a7b4d3e5f60'],
        ],
      );

      await sync.onGiftWrap(wrap);

      final row = await labels.getLabelEvent(wrap.id, recipientPubkey: alice);
      expect(row?.prevFolder, '9f2c1a7b4d3e5f60');
    });

    test('a wrap deleted before it lands is never applied', () async {
      final wrap = await wrappedLabel('state:read');

      await sync.onDeletion(deletionOf(wrap.id));
      await sync.onGiftWrap(wrap);

      expect(await isRead(), isFalse);
    });

    test('a label added again survives the deletion of the first one, in '
        'either order', () async {
      final first = await wrappedLabel('state:read');
      final again = await wrappedLabel('state:read', createdAt: 2000);

      await sync.onGiftWrap(first);
      await sync.onGiftWrap(again);
      await sync.onDeletion(deletionOf(first.id));
      expect(await isRead(), isTrue);

      await sync.onDeletion(deletionOf(again.id));
      expect(await isRead(), isFalse);

      final third = await wrappedLabel('state:read', createdAt: 3000);
      final fourth = await wrappedLabel('state:read', createdAt: 4000);
      await sync.onGiftWrap(third);
      await sync.onDeletion(deletionOf(third.id));
      await sync.onGiftWrap(fourth);
      expect(await isRead(), isTrue);
    });

    test('a label whose signature is not the account\'s is ignored', () async {
      final forged = await wrappedLabel(
        'folder:trash',
        signer: Bip340.generatePrivateKey(),
      );
      final bob = Bip340.generatePrivateKey();
      final foreign = await wrappedLabel(
        'folder:trash',
        signer: bob,
        author: bob.publicKey,
      );

      await sync.onGiftWrap(forged);
      await sync.onGiftWrap(foreign);

      expect(
        await labels.hasLabel(emailId, 'folder:trash', recipientPubkey: alice),
        isFalse,
      );
      expect((await giftWraps.getById(forged.id))!['stage'], 'stored');
    });
  });
}
