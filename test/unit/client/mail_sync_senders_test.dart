// The senders list is an append-only list (kinds 1990/1991) whose entries
// travel in content encrypted to the account itself.

import 'dart:convert';

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
import 'package:nostr_mail/src/storage/sender_repository.dart';
import 'package:nostr_mail/src/storage/tombstone_repository.dart';
import 'package:sembast/sembast_memory.dart' hide Filter;
import 'package:sync_engine_shim_for_ndk/sync_engine_shim_for_ndk.dart';
import 'package:test/test.dart';

import '../../helpers/test_blossom_cache.dart';
import '../../helpers/test_database.dart';

/// A signer standing for a remote one: it counts its decryptions, and fails
/// them on demand.
class _RemoteSigner extends Bip340EventSigner {
  _RemoteSigner(KeyPair keys)
    : super(privateKey: keys.privateKey, publicKey: keys.publicKey);

  int decryptions = 0;
  bool refuses = false;

  @override
  Future<String?> decryptNip44({
    required String ciphertext,
    required String senderPubKey,
  }) {
    decryptions++;
    if (refuses) throw Exception('refused');
    return super.decryptNip44(
      ciphertext: ciphertext,
      senderPubKey: senderPubKey,
    );
  }
}

void main() {
  group('MailSync senders list', () {
    late Database db;
    late Ndk ndk;
    late NostrMailDatabase database;
    late SenderRepository senders;
    late TombstoneRepository tombstones;
    late EventBus bus;
    late SyncEngine engine;
    late MailSync sync;
    late KeyPair keys;
    late String alice;

    setUp(() async {
      db = await databaseFactoryMemory.openDatabase(
        'senders_${DateTime.now().microsecondsSinceEpoch}',
      );
      ndk = Ndk(
        NdkConfig(
          eventVerifier: Bip340EventVerifier(),
          cache: MemCacheManager(),
          bootstrapRelays: const [],
        ),
      );
      keys = Bip340.generatePrivateKey();
      alice = keys.publicKey;

      database = testDatabase();
      senders = SenderRepository(database);
      tombstones = TombstoneRepository(database);
      bus = EventBus();
      engine = SyncEngine(ndk, db: db);
      sync = MailSync(
        ndk,
        engine,
        EmailRepository(database),
        LabelRepository(database),
        GiftWrapRepository(database),
        tombstones,
        senders,
        bus,
        RelayResolver(ndk),
        blossomCache: await openTestBlossomCache('senders_test'),
      );
    });

    tearDown(() async {
      await engine.dispose();
      await ndk.destroy();
      await db.close();
    });

    void loginLocal() =>
        ndk.accounts.loginPrivateKey(pubkey: alice, privkey: keys.privateKey!);

    _RemoteSigner loginRemote() {
      final signer = _RemoteSigner(keys);
      ndk.accounts.loginExternalSigner(signer: signer);
      return signer;
    }

    Future<Nip01Event> listEvent(
      List<List<String>> entries, {
      int kind = listAddKind,
      int createdAt = 1000,
      String? author,
      String dTag = sendersListDTag,
      String? content,
    }) async => Nip01Event(
      pubKey: author ?? alice,
      kind: kind,
      createdAt: createdAt,
      tags: [
        ['d', dTag],
      ],
      content:
          content ??
          (await Bip340EventSigner(
            privateKey: keys.privateKey,
            publicKey: alice,
          ).encryptNip44(
            plaintext: jsonEncode(entries),
            recipientPubKey: alice,
          ))!,
    );

    Nip01Event deletionOf(String eventId) => Nip01Event(
      pubKey: alice,
      createdAt: 2000,
      kind: deletionRequestKind,
      tags: [
        ['e', eventId],
        ['k', listAddKind.toString()],
      ],
      content: '',
    );

    Future<SenderVerdict?> verdictOf(String key) =>
        senders.verdictOf(key, recipientPubkey: alice);

    test('applies an Add of the account and announces the change', () async {
      loginLocal();
      final events = <MailEvent>[];
      bus.stream.listen(events.add);

      await sync.onSendersList(
        await listEvent([
          ['sender', 'bob', 'allow'],
          ['sender', 'bridge:spam@example.com', 'block'],
        ]),
      );
      await pumpEventQueue();

      expect(await verdictOf('bob'), SenderVerdict.allow);
      expect(await verdictOf('bridge:spam@example.com'), SenderVerdict.block);
      expect(
        events.whereType<SenderVerdictChanged>().map(
          (e) => (e.senderKey, e.verdict),
        ),
        unorderedEquals([
          ('bob', SenderVerdict.allow),
          ('bridge:spam@example.com', SenderVerdict.block),
        ]),
      );
    });

    test('applies a later Remove', () async {
      loginLocal();
      await sync.onSendersList(
        await listEvent([
          ['sender', 'bob', 'allow'],
        ]),
      );
      await sync.onSendersList(
        await listEvent(
          [
            ['sender', 'bob'],
          ],
          kind: listRemoveKind,
          createdAt: 1001,
        ),
      );

      expect(await verdictOf('bob'), isNull);
    });

    test('reads public sender tags without a signer', () async {
      ndk.accounts.loginPublicKey(pubkey: alice);
      final event = Nip01Event(
        pubKey: alice,
        kind: listAddKind,
        createdAt: 1000,
        tags: [
          ['d', sendersListDTag],
          ['sender', 'bob', 'block'],
        ],
        content: '',
      );

      await sync.onSendersList(event);

      expect(await verdictOf('bob'), SenderVerdict.block);
    });

    test('ignores another author, another list and a deleted event', () async {
      loginLocal();
      final entries = [
        ['sender', 'bob', 'allow'],
      ];
      await sync.onSendersList(
        await listEvent(entries, author: Bip340.generatePrivateKey().publicKey),
      );
      await sync.onSendersList(await listEvent(entries, dTag: 'mail/contacts'));
      final deleted = await listEvent(entries);
      await tombstones.add(deleted.id, recipientPubkey: alice);
      await sync.onSendersList(deleted);

      expect(await verdictOf('bob'), isNull);
    });

    test('a deletion reverts the event, and keeps it out', () async {
      loginLocal();
      final allow = await listEvent([
        ['sender', 'bob', 'allow'],
      ]);
      final block = await listEvent([
        ['sender', 'bob', 'block'],
      ], createdAt: 1001);
      await sync.onSendersList(allow);
      await sync.onSendersList(block);
      final events = <MailEvent>[];
      bus.stream.listen(events.add);

      await sync.onDeletion(deletionOf(block.id));
      await pumpEventQueue();

      expect(await verdictOf('bob'), SenderVerdict.allow);
      expect(events.whereType<SenderVerdictChanged>().map((e) => e.verdict), [
        SenderVerdict.allow,
      ]);

      await sync.onSendersList(block);
      expect(await verdictOf('bob'), SenderVerdict.allow);
    });

    test('a rebuilt projection does not ask the signer again', () async {
      final signer = loginRemote();
      final event = await listEvent([
        ['sender', 'bob', 'allow'],
      ]);
      await sync.onSendersList(event);
      expect(signer.decryptions, 1);

      await database.delete(database.senderOps).go();
      await sync.onSendersList(event);

      expect(signer.decryptions, 1);
      expect(await verdictOf('bob'), SenderVerdict.allow);
    });

    test('a remote signer that keeps failing is given up on', () async {
      final signer = loginRemote()..refuses = true;
      final event = await listEvent([
        ['sender', 'bob', 'allow'],
      ]);

      for (var i = 0; i < maxSignerAttempts + 2; i++) {
        await sync.onSendersList(event);
      }

      expect(signer.decryptions, maxSignerAttempts);
      expect(await verdictOf('bob'), isNull);
    });

    test('a content our own key cannot open is never retried', () async {
      loginLocal();
      final event = await listEvent(const [], content: 'not a ciphertext');

      await sync.onSendersList(event);
      await sync.onSendersList(event);

      final row = await senders.getDecryption(event.id, recipientPubkey: alice);
      expect(row?.failure, GiftWrapFailure.permanent.name);
      expect(row?.attempts, 1);
    });
  });
}
