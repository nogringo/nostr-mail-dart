import 'package:ndk/ndk.dart';
import 'package:nostr_mail/src/storage/gift_wrap_repository.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:test/test.dart';

void main() {
  group('GiftWrapRepository', () {
    late GiftWrapRepository repo;

    Nip01Event makeEvent(
      String id, {
      String pubKey = 'test-pubkey',
      int kind = 1059,
      List<List<String>> tags = const [],
      String content = 'test content',
      String sig = 'test-sig',
      int? createdAt,
    }) {
      return Nip01Event(
        id: id,
        pubKey: pubKey,
        createdAt: createdAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
        kind: kind,
        tags: tags,
        content: content,
        sig: sig,
      );
    }

    setUp(() async {
      final db = await databaseFactoryMemory.openDatabase(
        'test_gw_${DateTime.now().microsecondsSinceEpoch}',
      );
      repo = GiftWrapRepository(db);
    });

    Future<bool> save(
      Nip01Event event, {
      String recipientPubkey = 'recipient',
    }) {
      return repo.save(event, recipientPubkey: recipientPubkey);
    }

    Future<void> store({
      required String giftWrapId,
      required Nip01Event seal,
      required Nip01Event rumor,
    }) async {
      await repo.updateUnsealed(
        giftWrapId: giftWrapId,
        seal: seal,
        rumor: rumor,
      );
      await repo.markStored(giftWrapId);
    }

    test('save returns true for a new event', () async {
      expect(await save(makeEvent('event-1')), isTrue);
    });

    test('save returns false for an already-stored event', () async {
      await save(makeEvent('event-1'));
      expect(await save(makeEvent('event-1')), isFalse);
    });

    test('getById returns a stored gift wrap by outer event id', () async {
      await save(makeEvent('event-1', content: 'wrapped content'));

      final record = await repo.getById('event-1');

      expect(record, isNotNull);
      expect(record!['stage'], 'saved');
      expect(record['event']['content'], 'wrapped content');
      expect(record['recipientPubkey'], 'recipient');
    });

    test('save does not overwrite a stored entry', () async {
      await save(makeEvent('event-1'));
      await repo.markStored('event-1');
      await save(makeEvent('event-1'));

      final unprocessed = await repo.getUnfinished();
      expect(unprocessed.map((w) => w.event.id), isNot(contains('event-1')));
    });

    test('markStored removes event from unprocessed list', () async {
      await save(makeEvent('event-1'));
      await repo.markStored('event-1');

      final unprocessed = await repo.getUnfinished();
      expect(unprocessed.map((w) => w.event.id), isNot(contains('event-1')));
    });

    test('getUnfinished returns only unprocessed events', () async {
      await save(makeEvent('event-1'));
      await save(makeEvent('event-2'));
      await save(makeEvent('event-3'));
      await repo.markStored('event-2');

      final unprocessed = await repo.getUnfinished();
      expect(
        unprocessed.map((w) => w.event.id),
        containsAll(['event-1', 'event-3']),
      );
      expect(unprocessed.map((w) => w.event.id), isNot(contains('event-2')));
    });

    test('getUnfinished respects limit', () async {
      await save(makeEvent('event-1'));
      await save(makeEvent('event-2'));
      await save(makeEvent('event-3'));

      final unprocessed = await repo.getUnfinished(limit: 2);
      expect(unprocessed.length, 2);
    });

    test('getFailedCount returns the number of unprocessed events', () async {
      await save(makeEvent('event-1'));
      await save(makeEvent('event-2'));
      await save(makeEvent('event-3'));
      await repo.markStored('event-2');

      expect(await repo.getFailedCount(), 2);
    });

    test('getUnfinished preserves the full event payload', () async {
      final event = makeEvent(
        'test-id',
        pubKey: 'test-pubkey-123',
        createdAt: 1234567890,
        tags: [
          ['p', 'recipient'],
        ],
        content: 'encrypted content',
        sig: 'signature-123',
      );
      await save(event);

      final unprocessed = await repo.getUnfinished();
      expect(unprocessed, hasLength(1));
      final stored = unprocessed.single.event;
      expect(stored.id, 'test-id');
      expect(stored.pubKey, 'test-pubkey-123');
      expect(stored.createdAt, 1234567890);
      expect(stored.kind, 1059);
      expect(stored.tags, [
        ['p', 'recipient'],
      ]);
      expect(stored.content, 'encrypted content');
      expect(stored.sig, 'signature-123');
    });

    test('removeByRumorIds removes processed gift wraps by email id', () async {
      await save(makeEvent('wrap-1'));
      await save(makeEvent('wrap-2'));
      await save(makeEvent('wrap-3'));
      await store(
        giftWrapId: 'wrap-1',
        seal: makeEvent('seal-1', kind: 13),
        rumor: makeEvent('email-1', kind: 1301),
      );
      await store(
        giftWrapId: 'wrap-2',
        seal: makeEvent('seal-2', kind: 13),
        rumor: makeEvent('email-2', kind: 1301),
      );
      await store(
        giftWrapId: 'wrap-3',
        seal: makeEvent('seal-3', kind: 13),
        rumor: makeEvent('email-3', kind: 1301),
      );

      await repo.removeByRumorIds(['email-1', 'email-2']);

      expect(await repo.getByRumorId('email-1'), isNull);
      expect(await repo.getByRumorId('email-2'), isNull);
      expect(await repo.getByRumorId('email-3'), isNotNull);
    });

    test('removeByRumorIdsForRecipient preserves other accounts', () async {
      await save(makeEvent('alice-wrap'), recipientPubkey: 'alice');
      await save(makeEvent('bob-wrap'), recipientPubkey: 'bob');
      await store(
        giftWrapId: 'alice-wrap',
        seal: makeEvent('alice-seal', kind: 13),
        rumor: makeEvent('same-email-id', kind: 1301),
      );
      await store(
        giftWrapId: 'bob-wrap',
        seal: makeEvent('bob-seal', kind: 13),
        rumor: makeEvent('same-email-id', kind: 1301),
      );

      await repo.removeByRumorIdsForRecipient([
        'same-email-id',
      ], recipientPubkey: 'alice');

      expect(
        await repo.getByIdForRecipient('alice-wrap', recipientPubkey: 'alice'),
        isNull,
      );
      expect(
        await repo.getByIdForRecipient('bob-wrap', recipientPubkey: 'bob'),
        isNotNull,
      );
    });

    test('clearAll removes all gift wraps', () async {
      await save(makeEvent('event-1'));
      await save(makeEvent('event-2'));
      await repo.markStored('event-1');

      await repo.clearAll();

      expect(await repo.getUnfinished(), isEmpty);
      expect(await repo.getFailedCount(), 0);
    });

    test('scoped queries only return gift wraps for that account', () async {
      await save(makeEvent('alice-1'), recipientPubkey: 'alice');
      await save(makeEvent('bob-1'), recipientPubkey: 'bob');
      await store(
        giftWrapId: 'alice-1',
        seal: makeEvent('alice-seal', kind: 13),
        rumor: makeEvent('alice-email', kind: 1301),
      );
      await store(
        giftWrapId: 'bob-1',
        seal: makeEvent('bob-seal', kind: 13),
        rumor: makeEvent('bob-email', kind: 1301),
      );

      final aliceEvents = await repo.getUnfinished(recipientPubkey: 'alice');

      expect(aliceEvents, isEmpty);
      expect(
        await repo.getByIdForRecipient('bob-1', recipientPubkey: 'alice'),
        isNull,
      );
      expect(
        await repo.getByRumorIdForRecipient(
          'bob-email',
          recipientPubkey: 'alice',
        ),
        isNull,
      );
      expect(
        await repo.getByRumorIdForRecipient(
          'alice-email',
          recipientPubkey: 'alice',
        ),
        isNotNull,
      );
    });

    test('clearAll with recipientPubkey preserves other accounts', () async {
      await save(makeEvent('alice-1'), recipientPubkey: 'alice');
      await save(makeEvent('bob-1'), recipientPubkey: 'bob');

      await repo.clearAll(recipientPubkey: 'alice');

      expect(await repo.getUnfinished(recipientPubkey: 'alice'), isEmpty);
      expect(
        (await repo.getUnfinished(
          recipientPubkey: 'bob',
        )).map((w) => w.event.id),
        ['bob-1'],
      );
    });
  });
}
