import 'package:nostr_mail/src/models/gift_wrap_state.dart';
import 'package:nostr_mail/src/models/sender_verdict.dart';
import 'package:nostr_mail/src/storage/sender_repository.dart';
import 'package:test/test.dart';

import '../../helpers/test_database.dart';

void main() {
  const rpk = 'rpk';
  late SenderRepository repo;

  setUp(() => repo = SenderRepository(testDatabase()));

  Future<Map<String, SenderVerdict?>> add(
    String eventId,
    int createdAt,
    String? verdict, {
    String key = 'alice',
    String recipientPubkey = rpk,
  }) => repo.saveEntries(
    eventId: eventId,
    recipientPubkey: recipientPubkey,
    isAdd: true,
    createdAt: createdAt,
    entries: [(key: key, verdict: verdict)],
  );

  Future<Map<String, SenderVerdict?>> remove(
    String eventId,
    int createdAt, {
    String key = 'alice',
  }) => repo.saveEntries(
    eventId: eventId,
    recipientPubkey: rpk,
    isAdd: false,
    createdAt: createdAt,
    entries: [(key: key, verdict: null)],
  );

  Future<SenderVerdict?> verdict([String key = 'alice']) =>
      repo.verdictOf(key, recipientPubkey: rpk);

  group('verdict', () {
    test('is none without any event', () async {
      expect(await verdict(), isNull);
    });

    test('is the verdict of an Add', () async {
      await add('e1', 1, 'allow');
      expect(await verdict(), SenderVerdict.allow);
    });

    test('is none once a Remove is strictly later', () async {
      await add('e1', 1, 'allow');
      await remove('e2', 2);
      expect(await verdict(), isNull);
    });

    test('survives a Remove in the same second', () async {
      await add('e1', 1, 'allow');
      await remove('e2', 1);
      expect(await verdict(), SenderVerdict.allow);
    });

    test('ignores a Remove older than the Add', () async {
      await remove('e1', 1);
      await add('e2', 2, 'block');
      expect(await verdict(), SenderVerdict.block);
    });

    test('is the most recent Add, whatever the arrival order', () async {
      await add('e2', 2, 'block');
      await add('e1', 1, 'allow');
      expect(await verdict(), SenderVerdict.block);
    });

    test(
      'goes to the lowest event id between Adds of the same second',
      () async {
        await add('bb', 5, 'allow');
        await add('aa', 5, 'block');
        expect(await verdict(), SenderVerdict.block);

        await add('cc', 5, 'allow');
        expect(await verdict(), SenderVerdict.block);
      },
    );

    test('is none when the most recent Add holds no verdict', () async {
      await add('e1', 1, 'allow');
      await add('e2', 2, 'maybe');
      expect(await verdict(), isNull);

      await add('e3', 3, null);
      expect(await verdict(), isNull);
    });

    test('belongs to its account', () async {
      await add('e1', 1, 'allow', recipientPubkey: 'other');
      expect(await verdict(), isNull);
    });
  });

  group('saveEntries', () {
    test('reports the senders whose verdict changed', () async {
      final changes = await repo.saveEntries(
        eventId: 'e1',
        recipientPubkey: rpk,
        isAdd: true,
        createdAt: 1,
        entries: const [
          (key: 'alice', verdict: 'allow'),
          (key: 'bob', verdict: 'block'),
        ],
      );
      expect(changes, {
        'alice': SenderVerdict.allow,
        'bob': SenderVerdict.block,
      });

      expect(await add('e2', 2, 'allow'), isEmpty);
      expect(await add('e3', 3, 'block'), {'alice': SenderVerdict.block});
      expect(await remove('e4', 4), {'alice': null});
    });

    test('is idempotent', () async {
      await add('e1', 1, 'allow');
      expect(await add('e1', 1, 'allow'), isEmpty);
      expect(await repo.hasEvent('e1', recipientPubkey: rpk), isTrue);
      expect(await repo.hasEvent('e1', recipientPubkey: 'other'), isFalse);
    });
  });

  test('removeEvent falls back to the previous Add', () async {
    await add('e1', 1, 'allow');
    await add('e2', 2, 'block');
    await repo.saveDecryption(
      eventId: 'e2',
      recipientPubkey: rpk,
      plaintext: '[]',
    );

    expect(await repo.removeEvent('e2', recipientPubkey: rpk), {
      'alice': SenderVerdict.allow,
    });
    expect(await repo.hasEvent('e2', recipientPubkey: rpk), isFalse);
    expect(await repo.getDecryption('e2', recipientPubkey: rpk), isNull);
    expect(await repo.removeEvent('e2', recipientPubkey: rpk), isEmpty);
  });

  test('latestCreatedAt counts Adds and Removes', () async {
    expect(await repo.latestCreatedAt('alice', recipientPubkey: rpk), isNull);
    await add('e1', 1, 'allow');
    await remove('e2', 7);
    await add('e3', 3, 'allow', key: 'bob');
    expect(await repo.latestCreatedAt('alice', recipientPubkey: rpk), 7);
  });

  group('decryptions', () {
    test('count failures, and a success clears the failure', () async {
      await repo.recordFailure(
        eventId: 'e1',
        recipientPubkey: rpk,
        failure: GiftWrapFailure.signer,
      );
      await repo.recordFailure(
        eventId: 'e1',
        recipientPubkey: rpk,
        failure: GiftWrapFailure.signer,
      );
      var row = await repo.getDecryption('e1', recipientPubkey: rpk);
      expect(row?.failure, 'signer');
      expect(row?.attempts, 2);
      expect(row?.plaintext, isNull);

      await repo.saveDecryption(
        eventId: 'e1',
        recipientPubkey: rpk,
        plaintext: '[]',
      );
      row = await repo.getDecryption('e1', recipientPubkey: rpk);
      expect(row?.failure, isNull);
      expect(row?.plaintext, '[]');
    });

    test('belong to their account', () async {
      await repo.saveDecryption(
        eventId: 'e1',
        recipientPubkey: rpk,
        plaintext: '[]',
      );
      expect(await repo.getDecryption('e1', recipientPubkey: 'other'), isNull);
    });
  });

  test('clearAll wipes one account, events and decryptions', () async {
    await add('e1', 1, 'allow');
    await add('e2', 1, 'allow', recipientPubkey: 'other');
    await repo.saveDecryption(
      eventId: 'e1',
      recipientPubkey: rpk,
      plaintext: '[]',
    );

    await repo.clearAll(recipientPubkey: rpk);

    expect(await verdict(), isNull);
    expect(await repo.getDecryption('e1', recipientPubkey: rpk), isNull);
    expect(
      await repo.verdictOf('alice', recipientPubkey: 'other'),
      SenderVerdict.allow,
    );
  });
}
