import 'database.dart';
import 'match_repository.dart';

/// Local cache for decrypted private settings (NIP-78).
///
/// Settings are keyed by pubkey to support multi-account scenarios.
class SettingsRepository {
  final NostrMailDatabase _db;
  final MatchRepository _matches;

  SettingsRepository(this._db) : _matches = MatchRepository(_db);

  /// Save decrypted settings JSON for a specific pubkey, and move the emails
  /// its folder and tag conditions now hold.
  Future<void> save({required String pubkey, required String json}) =>
      _db.transaction(() async {
        final before = await load(pubkey: pubkey);
        await _db
            .into(_db.settings)
            .insertOnConflictUpdate(SettingsRow(pubkey: pubkey, json: json));
        if (MatchRepository.rulesChanged(before, json)) {
          await _matches.rebuild(pubkey);
        }
      });

  /// Load cached decrypted settings JSON for a specific pubkey.
  Future<String?> load({required String pubkey}) async {
    final row = await (_db.select(
      _db.settings,
    )..where((s) => s.pubkey.equals(pubkey))).getSingleOrNull();
    return row?.json;
  }

  /// Clear cached settings for a specific pubkey or all.
  Future<void> clear({String? pubkey}) => _db.transaction(() async {
    final settings = _db.delete(_db.settings);
    final matches = _db.delete(_db.matches);
    if (pubkey != null) {
      settings.where((s) => s.pubkey.equals(pubkey));
      matches.where((m) => m.recipientPubkey.equals(pubkey));
    }
    await settings.go();
    await matches.go();
  });
}
