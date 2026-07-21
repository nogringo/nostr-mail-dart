// A gift wrap can reach onGiftWrap while it is no longer the active
// account's: a live subscription or an in-flight fetch keeps delivering
// after `switchAccount`. Its fetched range is already marked covered, so
// dropping it would lose the wrap until a manual resync.

import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:nostr_mail/src/client/event_bus.dart';
import 'package:nostr_mail/src/client/relay_resolver.dart';
import 'package:nostr_mail/src/client/sync_engine.dart';
import 'package:nostr_mail/src/storage/email_repository.dart';
import 'package:nostr_mail/src/storage/gift_wrap_repository.dart';
import 'package:nostr_mail/src/storage/label_repository.dart';
import 'package:nostr_mail/src/storage/tombstone_repository.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:test/test.dart';

import '../../helpers/test_blossom_cache.dart';

void main() {
  group('SyncEngine.onGiftWrap account attribution', () {
    late Database db;
    late Ndk ndk;
    late GiftWrapRepository giftWraps;
    late SyncEngine sync;
    late String alice;
    late String bob;

    setUp(() async {
      db = await databaseFactoryMemory.openDatabase(
        'sync_engine_${DateTime.now().microsecondsSinceEpoch}',
      );

      ndk = Ndk(
        NdkConfig(
          eventVerifier: Bip340EventVerifier(),
          cache: MemCacheManager(),
          bootstrapRelays: const [],
          fetchedRangesEnabled: true,
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
      sync = SyncEngine(
        ndk,
        EmailRepository(db),
        LabelRepository(db),
        giftWraps,
        TombstoneRepository(db),
        EventBus(),
        RelayResolver(ndk),
        blossomCache: await openTestBlossomCache('sync_engine_test'),
      );
    });

    tearDown(() async {
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
