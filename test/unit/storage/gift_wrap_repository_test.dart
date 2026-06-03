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

    test('save returns true for a new event', () async {
      expect(await repo.save(makeEvent('event-1')), isTrue);
    });

    test('save returns false for an already-stored event', () async {
      await repo.save(makeEvent('event-1'));
      expect(await repo.save(makeEvent('event-1')), isFalse);
    });

    test('save does not overwrite a processed entry', () async {
      await repo.save(makeEvent('event-1'));
      await repo.markProcessed('event-1');
      await repo.save(makeEvent('event-1'));

      final unprocessed = await repo.getUnprocessedEvents();
      expect(unprocessed.map((e) => e.id), isNot(contains('event-1')));
    });

    test('markProcessed removes event from unprocessed list', () async {
      await repo.save(makeEvent('event-1'));
      await repo.markProcessed('event-1');

      final unprocessed = await repo.getUnprocessedEvents();
      expect(unprocessed.map((e) => e.id), isNot(contains('event-1')));
    });

    test('getUnprocessedEvents returns only unprocessed events', () async {
      await repo.save(makeEvent('event-1'));
      await repo.save(makeEvent('event-2'));
      await repo.save(makeEvent('event-3'));
      await repo.markProcessed('event-2');

      final unprocessed = await repo.getUnprocessedEvents();
      expect(unprocessed.map((e) => e.id), containsAll(['event-1', 'event-3']));
      expect(unprocessed.map((e) => e.id), isNot(contains('event-2')));
    });

    test('getUnprocessedEvents respects limit', () async {
      await repo.save(makeEvent('event-1'));
      await repo.save(makeEvent('event-2'));
      await repo.save(makeEvent('event-3'));

      final unprocessed = await repo.getUnprocessedEvents(limit: 2);
      expect(unprocessed.length, 2);
    });

    test('getFailedCount returns the number of unprocessed events', () async {
      await repo.save(makeEvent('event-1'));
      await repo.save(makeEvent('event-2'));
      await repo.save(makeEvent('event-3'));
      await repo.markProcessed('event-2');

      expect(await repo.getFailedCount(), 2);
    });

    test('getUnprocessedEvents preserves the full event payload', () async {
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
      await repo.save(event);

      final unprocessed = await repo.getUnprocessedEvents();
      expect(unprocessed, hasLength(1));
      final stored = unprocessed.single;
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
      await repo.save(makeEvent('wrap-1'));
      await repo.save(makeEvent('wrap-2'));
      await repo.save(makeEvent('wrap-3'));
      await repo.updateDecrypted(
        giftWrapId: 'wrap-1',
        seal: makeEvent('seal-1', kind: 13),
        rumor: makeEvent('email-1', kind: 1301),
      );
      await repo.updateDecrypted(
        giftWrapId: 'wrap-2',
        seal: makeEvent('seal-2', kind: 13),
        rumor: makeEvent('email-2', kind: 1301),
      );
      await repo.updateDecrypted(
        giftWrapId: 'wrap-3',
        seal: makeEvent('seal-3', kind: 13),
        rumor: makeEvent('email-3', kind: 1301),
      );

      await repo.removeByRumorIds(['email-1', 'email-2']);

      expect(await repo.getByRumorId('email-1'), isNull);
      expect(await repo.getByRumorId('email-2'), isNull);
      expect(await repo.getByRumorId('email-3'), isNotNull);
    });

    test('clearAll removes all gift wraps', () async {
      await repo.save(makeEvent('event-1'));
      await repo.save(makeEvent('event-2'));
      await repo.markProcessed('event-1');

      await repo.clearAll();

      expect(await repo.getUnprocessedEvents(), isEmpty);
      expect(await repo.getFailedCount(), 0);
    });
  });
}
