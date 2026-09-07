import 'database.dart';

/// Local cache for decrypted private settings (NIP-78).
///
/// Settings are keyed by pubkey to support multi-account scenarios.
class SettingsRepository {
  final NostrMailDatabase _db;

  SettingsRepository(this._db);

  /// Save decrypted settings JSON for a specific pubkey.
  Future<void> save({required String pubkey, required String json}) async {
    await _db
        .into(_db.settings)
        .insertOnConflictUpdate(SettingsRow(pubkey: pubkey, json: json));
  }

  /// Load cached decrypted settings JSON for a specific pubkey.
  Future<String?> load({required String pubkey}) async {
    final row = await (_db.select(
      _db.settings,
    )..where((s) => s.pubkey.equals(pubkey))).getSingleOrNull();
    return row?.json;
  }

  /// Clear cached settings for a specific pubkey or all.
  Future<void> clear({String? pubkey}) async {
    final statement = _db.delete(_db.settings);
    if (pubkey != null) {
      statement.where((s) => s.pubkey.equals(pubkey));
    }
    await statement.go();
  }
}
