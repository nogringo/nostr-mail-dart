import 'package:nostr_mail/src/storage/settings_repository.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:test/test.dart';

void main() {
  group('SettingsRepository', () {
    late SettingsRepository repo;

    setUp(() async {
      final db = await databaseFactoryMemoryFs.openDatabase(
        'test_settings_${DateTime.now().microsecondsSinceEpoch}',
      );
      repo = SettingsRepository(db);
    });

    test('save and load roundtrip', () async {
      await repo.save(pubkey: 'pk1', json: '{"signature":"hi"}');
      expect(await repo.load(pubkey: 'pk1'), '{"signature":"hi"}');
    });

    test('clear removes only the targeted pubkey', () async {
      await repo.save(pubkey: 'pk1', json: '{}');
      await repo.clear(pubkey: 'pk1');
      expect(await repo.load(pubkey: 'pk1'), isNull);
    });
  });
}
