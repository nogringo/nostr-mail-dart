// Regression test for nostr-mail-client issue #22:
// "Cache stores every account's emails"
//
// When two accounts share a single sembast database (the documented
// initialization pattern in README.md), reads must scope to the active
// account's recipientPubkey. Each test simulates Alice reading the store
// and asserts that none of Bob's data is reachable.

import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:ndk/shared/nips/nip01/key_pair.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:nostr_mail/src/client/filters.dart';
import 'package:nostr_mail/src/storage/email_repository.dart';
import 'package:nostr_mail/src/storage/gift_wrap_repository.dart';
import 'package:nostr_mail/src/storage/label_repository.dart';
import 'package:nostr_mail/src/storage/models/email_query.dart';
import 'package:nostr_mail/src/storage/models/email_record.dart';
import 'package:nostr_mail/src/storage/settings_repository.dart';
import 'package:nostr_mail/src/storage/tombstone_repository.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:test/test.dart';

import '../../helpers/test_blossom_cache.dart';
import '../../mocks/mock_relay.dart';

void main() {
  final aliceKeys = Bip340.generatePrivateKey();
  final bobKeys = Bip340.generatePrivateKey();
  final senderKeys = Bip340.generatePrivateKey();
  final alice = aliceKeys.publicKey;
  final bob = bobKeys.publicKey;
  final sender = senderKeys.publicKey;

  EmailRecord makeRecord({
    required String id,
    required String recipientPubkey,
    String folder = 'inbox',
    String subject = 'sub',
    String body = 'body',
  }) {
    return EmailRecord(
      id: id,
      senderPubkey: sender,
      recipientPubkey: recipientPubkey,
      lightMimeText: 'raw',
      attachmentRefs: const [],
      isPublic: false,
      createdAt: 1000,
      date: 1000,
      from: 'sender@example.com',
      subject: subject,
      bodyPlain: body,
      searchText: '$subject $body',
      attachmentCount: 0,
      folder: folder,
      isRead: false,
      isStarred: false,
      labels: const [],
      isBridged: false,
    );
  }

  group('Multi-account isolation (issue #22)', () {
    late EmailRepository emails;
    late LabelRepository labels;

    setUp(() async {
      final db = await databaseFactoryMemoryFs.openDatabase(
        'iso_${DateTime.now().microsecondsSinceEpoch}',
      );
      emails = EmailRepository(db);
      labels = LabelRepository(db);
    });

    test("inbox query for Alice does not leak Bob's emails", () async {
      await emails.save(makeRecord(id: 'a1', recipientPubkey: alice));
      await emails.save(makeRecord(id: 'a2', recipientPubkey: alice));
      await emails.save(makeRecord(id: 'b1', recipientPubkey: bob));

      final result = await emails.query(
        EmailQuery.inbox(recipientPubkey: alice),
      );

      expect(
        result.items.map((e) => e.id).toSet(),
        {'a1', 'a2'},
        reason: "Alice's inbox must not include Bob's emails",
      );
    });

    test('count is per-account, not global', () async {
      await emails.save(makeRecord(id: 'a1', recipientPubkey: alice));
      await emails.save(makeRecord(id: 'b1', recipientPubkey: bob));
      await emails.save(makeRecord(id: 'b2', recipientPubkey: bob));

      final aliceCount = await emails.count(
        EmailQuery.inbox(recipientPubkey: alice),
      );
      expect(aliceCount, 1, reason: 'Alice has 1 inbox email');
    });

    test("search does not return another account's matches", () async {
      await emails.save(
        makeRecord(id: 'a1', recipientPubkey: alice, subject: 'shared keyword'),
      );
      await emails.save(
        makeRecord(id: 'b1', recipientPubkey: bob, subject: 'shared keyword'),
      );

      final hits = await emails.search('shared', recipientPubkey: alice);

      expect(
        hits.map((e) => e.id).toSet(),
        {'a1'},
        reason: 'search results must be scoped to the active account',
      );
    });

    test("getById cannot fetch another account's email", () async {
      await emails.save(makeRecord(id: 'b1', recipientPubkey: bob));

      // Defense in depth on top of the query filter.
      final stolen = await emails.getById('b1', recipientPubkey: alice);
      expect(
        stolen,
        isNull,
        reason: "Alice must not be able to read Bob's email by id",
      );
    });

    test('labels do not leak across accounts', () async {
      await emails.save(makeRecord(id: 'a1', recipientPubkey: alice));
      await emails.save(makeRecord(id: 'b1', recipientPubkey: bob));

      await labels.saveLabel(
        emailId: 'a1',
        label: 'custom:work',
        labelEventId: 'ev_a',
        timestamp: 1000,
        recipientPubkey: alice,
      );
      await labels.saveLabel(
        emailId: 'b1',
        label: 'custom:personal',
        labelEventId: 'ev_b',
        timestamp: 1000,
        recipientPubkey: bob,
      );

      final all = await labels.getAllLabels(recipientPubkey: alice);
      expect(
        all.map((r) => r['emailId']).toSet(),
        {'a1'},
        reason: 'Alice should only see labels attached to her own emails',
      );
    });
  });

  // Reproduces the exact scenario from issue #22: a single NostrMailClient
  // instance is reused across an NDK account switch. The reader's pubkey
  // must be re-read from NDK on every call, not cached at construction.
  group('NDK account switch on a single client', () {
    late MockRelay relay;
    late Database db;
    late Ndk ndk;
    late NostrMailClient client;
    late KeyPair aliceAccount;
    late KeyPair bobAccount;

    setUp(() async {
      relay = MockRelay(name: 'relay', explicitPort: 19020);
      await relay.startServer();

      db = await databaseFactoryMemory.openDatabase(
        'switch_${DateTime.now().microsecondsSinceEpoch}',
      );

      ndk = Ndk(
        NdkConfig(
          eventVerifier: Bip340EventVerifier(),
          cache: MemCacheManager(),
          bootstrapRelays: [relay.url],
          fetchedRangesEnabled: true,
        ),
      );

      aliceAccount = Bip340.generatePrivateKey();
      bobAccount = Bip340.generatePrivateKey();

      ndk.accounts.loginPrivateKey(
        pubkey: aliceAccount.publicKey,
        privkey: aliceAccount.privateKey!,
      );

      client = await NostrMailClient.create(
        ndk: ndk,
        db: db,
        blossomCache: await openTestBlossomCache('account_isolation_test'),
        defaultDmRelays: [relay.url],
      );
    });

    void addBob() {
      ndk.accounts.addAccount(
        pubkey: bobAccount.publicKey,
        type: AccountType.privateKey,
        signer: Bip340EventSigner(
          privateKey: bobAccount.privateKey,
          publicKey: bobAccount.publicKey,
        ),
      );
    }

    tearDown(() async {
      await ndk.destroy();
      await db.close();
      await relay.stopServer();
    });

    /// Seed an email record for [recipient] without going through sync —
    /// the goal here is to test the read path under an account switch,
    /// not the relay round-trip.
    Future<void> seedEmailFor(String recipient, String id) async {
      final repo = EmailRepository(db);
      await repo.save(
        EmailRecord(
          id: id,
          senderPubkey: 'sender',
          recipientPubkey: recipient,
          lightMimeText: 'raw',
          attachmentRefs: const [],
          isPublic: false,
          createdAt: 1000,
          date: 1000,
          from: 'a@b.com',
          subject: 'sub',
          bodyPlain: 'body',
          searchText: 'a@b.com sub body',
          attachmentCount: 0,
          folder: 'inbox',
          isRead: false,
          isStarred: false,
          labels: const [],
          isBridged: false,
        ),
      );
    }

    Nip01Event makeEvent(String id, {int kind = 1059}) {
      return Nip01Event(
        id: id,
        pubKey: 'sender',
        createdAt: 1000,
        kind: kind,
        tags: const [],
        content: 'content',
        sig: 'sig',
      );
    }

    test(
      "reading after switchAccount only returns the new account's emails",
      () async {
        addBob();

        await seedEmailFor(aliceAccount.publicKey, 'alice-1');
        expect((await client.getInboxEmails()).map((e) => e.id), ['alice-1']);

        ndk.accounts.switchAccount(pubkey: bobAccount.publicKey);

        final inbox = await client.getInboxEmails();
        expect(
          inbox,
          isEmpty,
          reason: "Bob must not see Alice's emails after switchAccount",
        );

        expect(await client.getUnreadCount(folder: 'inbox'), 0);
      },
    );

    test(
      'reading after logout + loginPrivateKey only returns the new account',
      () async {
        await seedEmailFor(aliceAccount.publicKey, 'alice-1');
        expect((await client.getInboxEmails()).map((e) => e.id), ['alice-1']);

        ndk.accounts.logout();
        ndk.accounts.loginPrivateKey(
          pubkey: bobAccount.publicKey,
          privkey: bobAccount.privateKey!,
        );

        expect(await client.getInboxEmails(), isEmpty);

        ndk.accounts.logout();
        ndk.accounts.loginPrivateKey(
          pubkey: aliceAccount.publicKey,
          privkey: aliceAccount.privateKey!,
        );
        expect((await client.getInboxEmails()).map((e) => e.id), ['alice-1']);
      },
    );

    test(
      'search after switchAccount does not surface the previous account',
      () async {
        addBob();
        await seedEmailFor(aliceAccount.publicKey, 'alice-1');

        ndk.accounts.switchAccount(pubkey: bobAccount.publicKey);
        final hits = await client.search('sub');
        expect(hits, isEmpty);
      },
    );

    test('clearLocalAccountData removes only the targeted account', () async {
      final emails = EmailRepository(db);
      final labels = LabelRepository(db);
      final giftWraps = GiftWrapRepository(db);
      final settings = SettingsRepository(db);
      final tombstones = TombstoneRepository(db);

      await seedEmailFor(aliceAccount.publicKey, 'alice-email');
      await seedEmailFor(bobAccount.publicKey, 'bob-email');
      await labels.saveLabel(
        emailId: 'alice-email',
        label: 'custom:alice',
        labelEventId: 'alice-label',
        timestamp: 1000,
        recipientPubkey: aliceAccount.publicKey,
      );
      await labels.saveLabel(
        emailId: 'bob-email',
        label: 'custom:bob',
        labelEventId: 'bob-label',
        timestamp: 1000,
        recipientPubkey: bobAccount.publicKey,
      );
      await settings.save(pubkey: aliceAccount.publicKey, json: '{"a":true}');
      await settings.save(pubkey: bobAccount.publicKey, json: '{"b":true}');
      await tombstones.add(
        'alice-deleted',
        recipientPubkey: aliceAccount.publicKey,
      );
      await tombstones.add(
        'bob-deleted',
        recipientPubkey: bobAccount.publicKey,
      );
      await giftWraps.save(
        makeEvent('alice-wrap'),
        recipientPubkey: aliceAccount.publicKey,
      );
      await giftWraps.save(
        makeEvent('bob-wrap'),
        recipientPubkey: bobAccount.publicKey,
      );
      await ndk.fetchedRanges.addRange(
        filter: emailFilter(aliceAccount.publicKey),
        relayUrl: relay.url,
        since: 0,
        until: 1000,
      );
      await ndk.fetchedRanges.addRange(
        filter: emailFilter(bobAccount.publicKey),
        relayUrl: relay.url,
        since: 0,
        until: 1000,
      );

      await client.clearLocalAccountData(pubkey: aliceAccount.publicKey);

      expect(
        await emails.getById(
          'alice-email',
          recipientPubkey: aliceAccount.publicKey,
        ),
        isNull,
      );
      expect(
        await emails.getById(
          'bob-email',
          recipientPubkey: bobAccount.publicKey,
        ),
        isNotNull,
      );
      expect(
        await labels.getAllLabels(recipientPubkey: aliceAccount.publicKey),
        isEmpty,
      );
      expect(
        await labels.getAllLabels(recipientPubkey: bobAccount.publicKey),
        hasLength(1),
      );
      expect(await settings.load(pubkey: aliceAccount.publicKey), isNull);
      expect(await settings.load(pubkey: bobAccount.publicKey), '{"b":true}');
      expect(
        await tombstones.contains(
          'alice-deleted',
          recipientPubkey: aliceAccount.publicKey,
        ),
        isFalse,
      );
      expect(
        await tombstones.contains(
          'bob-deleted',
          recipientPubkey: bobAccount.publicKey,
        ),
        isTrue,
      );
      expect(
        await giftWraps.getByIdForRecipient(
          'alice-wrap',
          recipientPubkey: aliceAccount.publicKey,
        ),
        isNull,
      );
      expect(
        await giftWraps.getByIdForRecipient(
          'bob-wrap',
          recipientPubkey: bobAccount.publicKey,
        ),
        isNotNull,
      );
      expect(
        await ndk.fetchedRanges.getForFilter(
          emailFilter(aliceAccount.publicKey),
        ),
        isEmpty,
      );
      expect(
        await ndk.fetchedRanges.getForFilter(emailFilter(bobAccount.publicKey)),
        isNotEmpty,
      );
    });
  });
}
