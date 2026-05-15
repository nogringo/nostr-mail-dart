import 'package:ndk/ndk.dart' hide Filter;
import 'package:ndk/domain_layer/entities/filter.dart' as ndk;
import 'package:nostr_mail/src/storage/schema_migrator.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:test/test.dart';

Ndk _newNdk() => Ndk(
  NdkConfig(
    eventVerifier: Bip340EventVerifier(),
    cache: MemCacheManager(),
    bootstrapRelays: const [],
  ),
);

Future<Database> _newDb() => databaseFactoryMemory.openDatabase(
  'test_migrator_${DateTime.now().microsecondsSinceEpoch}',
);

final _versionRecord = StoreRef<String, int>('_meta').record(schemaVersionKey);

Future<void> _seedAppStores(Database db) async {
  for (final name in migratableAppStores) {
    await stringMapStoreFactory.store(name).record('row-1').put(db, {'k': 'v'});
  }
}

void main() {
  group('migrateSchemaIfNeeded', () {
    late Database db;
    late Ndk nostrClient;

    setUp(() async {
      db = await _newDb();
      nostrClient = _newNdk();
    });

    tearDown(() async {
      await nostrClient.destroy();
      await db.close();
    });

    test('writes current version on a fresh database', () async {
      final migrated = await migrateSchemaIfNeeded(db: db, ndk: nostrClient);

      expect(migrated, isTrue);
      expect(await _versionRecord.get(db), kSchemaVersion);
    });

    test('does nothing when on-disk version matches', () async {
      await _versionRecord.put(db, kSchemaVersion);
      await _seedAppStores(db);

      final migrated = await migrateSchemaIfNeeded(db: db, ndk: nostrClient);

      expect(migrated, isFalse);
      for (final name in migratableAppStores) {
        final count = await stringMapStoreFactory.store(name).count(db);
        expect(count, 1, reason: 'store $name should be preserved');
      }
    });

    test('drops every app store when on-disk version differs', () async {
      await _versionRecord.put(db, kSchemaVersion - 1);
      await _seedAppStores(db);

      await migrateSchemaIfNeeded(db: db, ndk: nostrClient);

      for (final name in migratableAppStores) {
        final count = await stringMapStoreFactory.store(name).count(db);
        expect(count, 0, reason: 'store $name should be wiped');
      }
      expect(await _versionRecord.get(db), kSchemaVersion);
    });

    test('drops app stores on first run with seeded data', () async {
      await _seedAppStores(db);

      await migrateSchemaIfNeeded(db: db, ndk: nostrClient);

      for (final name in migratableAppStores) {
        final count = await stringMapStoreFactory.store(name).count(db);
        expect(count, 0);
      }
    });

    test('clears ndk fetched ranges on a version mismatch', () async {
      await _versionRecord.put(db, kSchemaVersion - 1);
      final filter = ndk.Filter(kinds: const [1059], authors: const ['pk']);
      await nostrClient.fetchedRanges.addRange(
        filter: filter,
        relayUrl: 'wss://relay.test',
        since: 0,
        until: 1000,
      );
      expect(
        (await nostrClient.fetchedRanges.getForFilter(filter)).isNotEmpty,
        isTrue,
      );

      await migrateSchemaIfNeeded(db: db, ndk: nostrClient);

      expect(
        (await nostrClient.fetchedRanges.getForFilter(filter)).isEmpty,
        isTrue,
      );
    });
  });
}
