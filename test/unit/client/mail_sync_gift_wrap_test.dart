// A gift wrap can reach onGiftWrap while it is no longer the active
// account's: a live subscription or an in-flight fetch keeps delivering
// after `switchAccount`. Dropping it would lose the wrap for the account it
// belongs to, so it is stored under its own recipient.

import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:nostr_mail/src/client/event_bus.dart';
import 'package:nostr_mail/src/client/relay_resolver.dart';
import 'package:nostr_mail/src/client/mail_sync.dart';
import 'package:nostr_mail/src/storage/email_repository.dart';
import 'package:nostr_mail/src/storage/gift_wrap_repository.dart';
import 'package:nostr_mail/src/storage/label_repository.dart';
import 'package:nostr_mail/src/storage/tombstone_repository.dart';
import 'package:sembast/sembast_memory.dart' hide Filter;
import 'package:sync_engine_shim_for_ndk/sync_engine_shim_for_ndk.dart';
import 'package:test/test.dart';

import '../../helpers/test_blossom_cache.dart';

void main() {
  group('MailSync.onGiftWrap account attribution', () {
    late Database db;
    late Ndk ndk;
    late GiftWrapRepository giftWraps;
    late TombstoneRepository tombstones;
    late SyncEngine engine;
    late MailSync sync;
    late String alice;
    late String bob;

    setUp(() async {
      db = await databaseFactoryMemory.openDatabase(
        'mail_sync_${DateTime.now().microsecondsSinceEpoch}',
      );

      ndk = Ndk(
        NdkConfig(
          eventVerifier: Bip340EventVerifier(),
          cache: MemCacheManager(),
          bootstrapRelays: const [],
        ),
      );

      final aliceKeys = Bip340.generatePrivateKey();
      final bobKeys = Bip340.generatePrivateKey();
      alice = aliceKeys.publicKey;
      bob = bobKeys.publicKey;

      ndk.accounts.loginPrivateKey(
        pubkey: alice,
        privkey: aliceKeys.privateKey!,
      );
      ndk.accounts.loginPrivateKey(pubkey: bob, privkey: bobKeys.privateKey!);

      giftWraps = GiftWrapRepository(db);
      tombstones = TombstoneRepository(db);
      engine = SyncEngine(ndk, db: db);
      sync = MailSync(
        ndk,
        engine,
        EmailRepository(db),
        LabelRepository(db),
        giftWraps,
        tombstones,
        EventBus(),
        RelayResolver(ndk),
        blossomCache: await openTestBlossomCache('mail_sync_test'),
      );
    });

    tearDown(() async {
      await engine.dispose();
      await ndk.destroy();
      await db.close();
    });

    Nip01Event wrapFor(String recipient, {required String id}) {
      return Nip01Event(
        id: id,
        pubKey: 'sender',
        createdAt: 1000,
        kind: 1059,
        tags: [
          ['p', recipient],
        ],
        content: 'encrypted',
        sig: 'sig',
      );
    }

    test('keeps a wrap addressed to another local account', () async {
      await sync.onGiftWrap(wrapFor(alice, id: 'alice-wrap'));

      expect(
        await giftWraps.getByIdForRecipient(
          'alice-wrap',
          recipientPubkey: alice,
        ),
        isNotNull,
      );
      expect(
        await giftWraps.getByIdForRecipient('alice-wrap', recipientPubkey: bob),
        isNull,
      );
      expect(
        (await giftWraps.getUnprocessedEvents(
          recipientPubkey: alice,
        )).map((e) => e.id),
        ['alice-wrap'],
      );
      expect(
        await giftWraps.getUnprocessedEvents(recipientPubkey: bob),
        isEmpty,
      );
    });

    // The wrap of a deleted email is still served by relays that hold it. It
    // carries no readable link to the email, so only a tombstone on its own id
    // can spare the decryption it would otherwise cost on every replay.
    test('ignores a wrap whose own id is tombstoned', () async {
      await tombstones.add('alice-wrap', recipientPubkey: alice);

      await sync.onGiftWrap(wrapFor(alice, id: 'alice-wrap'));

      expect(await giftWraps.getById('alice-wrap'), isNull);
    });

    test('ignores a wrap addressed to an unknown pubkey', () async {
      await sync.onGiftWrap(wrapFor('stranger', id: 'stranger-wrap'));

      expect(await giftWraps.getById('stranger-wrap'), isNull);
    });

    test('ignores a wrap without a p tag', () async {
      final untagged = Nip01Event(
        id: 'untagged-wrap',
        pubKey: 'sender',
        createdAt: 1000,
        kind: 1059,
        tags: const [],
        content: 'encrypted',
        sig: 'sig',
      );

      await sync.onGiftWrap(untagged);

      expect(await giftWraps.getById('untagged-wrap'), isNull);
    });
  });
}
