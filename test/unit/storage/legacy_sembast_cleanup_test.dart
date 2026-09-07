import 'package:nostr_mail/src/storage/legacy_sembast_cleanup.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:test/test.dart';

void main() {
  group('dropLegacySembastStores', () {
    late Database db;

    setUp(() async {
      db = await databaseFactoryMemory.openDatabase(
        'legacy_${DateTime.now().microsecondsSinceEpoch}',
      );
    });

    tearDown(() => db.close());

    test('drops every store an earlier version kept', () async {
      for (final name in legacySembastStores) {
        await StoreRef<String, Object>(
          name,
        ).record('row-1').put(db, {'k': 'v'});
      }

      await dropLegacySembastStores(db);

      for (final name in legacySembastStores) {
        expect(await StoreRef<String, Object>(name).count(db), 0, reason: name);
      }
    });

    test('is a no-op without them', () async {
      await dropLegacySembastStores(db);
      await dropLegacySembastStores(db);
    });
  });
}
