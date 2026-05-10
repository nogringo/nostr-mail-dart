import 'dart:typed_data';

import 'package:idb_shim/idb_client_memory.dart';
import 'package:nostr_mail/src/storage/idb_blob_store.dart';
import 'package:test/test.dart';

void main() {
  group('IdbBlobStore', () {
    late IdbBlobStore store;

    setUp(() {
      // newIdbFactoryMemory gives a fresh in-memory factory per test, so
      // the database starts empty even with the same dbName.
      store = IdbBlobStore(newIdbFactoryMemory());
    });

    tearDown(() async {
      await store.close();
    });

    Uint8List bytes(List<int> values) => Uint8List.fromList(values);

    test('has returns false for an unknown blob', () async {
      expect(await store.has('deadbeef'), isFalse);
    });

    test('get returns null for an unknown blob', () async {
      expect(await store.get('deadbeef'), isNull);
    });

    test('put then get round-trips bytes', () async {
      final payload = bytes([0, 1, 2, 3, 250, 251, 252, 253]);
      await store.put('abc123', payload);

      final retrieved = await store.get('abc123');
      expect(retrieved, isA<Uint8List>());
      expect(retrieved, equals(payload));
    });

    test('has returns true after put', () async {
      await store.put('abc123', bytes([1, 2, 3]));
      expect(await store.has('abc123'), isTrue);
    });

    test('put overwrites an existing blob', () async {
      await store.put('abc123', bytes([1, 2, 3]));
      await store.put('abc123', bytes([4, 5, 6]));

      expect(await store.get('abc123'), equals(bytes([4, 5, 6])));
    });

    test('delete removes a blob', () async {
      await store.put('abc123', bytes([1, 2, 3]));
      await store.delete('abc123');

      expect(await store.has('abc123'), isFalse);
      expect(await store.get('abc123'), isNull);
    });

    test('delete is a no-op for an unknown blob', () async {
      await store.delete('unknown');
      expect(await store.has('unknown'), isFalse);
    });

    test('clear removes every blob', () async {
      await store.put('a', bytes([1]));
      await store.put('b', bytes([2]));
      await store.put('c', bytes([3]));

      await store.clear();

      expect(await store.has('a'), isFalse);
      expect(await store.has('b'), isFalse);
      expect(await store.has('c'), isFalse);
    });

    test('different keys are stored independently', () async {
      await store.put('a', bytes([1]));
      await store.put('b', bytes([2]));

      expect(await store.get('a'), equals(bytes([1])));
      expect(await store.get('b'), equals(bytes([2])));
    });

    test('large payloads round-trip correctly', () async {
      final payload = Uint8List.fromList(
        List<int>.generate(64 * 1024, (i) => i % 256),
      );
      await store.put('big', payload);

      final retrieved = await store.get('big');
      expect(retrieved, equals(payload));
    });

    test('reuses a single underlying database across operations', () async {
      // Sanity check that the factory open() is memoized: many calls in a
      // row should not throw or reopen.
      for (var i = 0; i < 10; i++) {
        await store.put('k$i', bytes([i]));
      }
      for (var i = 0; i < 10; i++) {
        expect(await store.get('k$i'), equals(bytes([i])));
      }
    });

    test('close lets a fresh store reopen the same database', () async {
      final factory = newIdbFactoryMemory();
      final s1 = IdbBlobStore(factory, dbName: 'shared');
      await s1.put('persisted', bytes([42]));
      await s1.close();

      final s2 = IdbBlobStore(factory, dbName: 'shared');
      expect(await s2.get('persisted'), equals(bytes([42])));
      await s2.close();
    });
  });
}
