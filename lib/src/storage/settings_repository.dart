import 'package:sembast/sembast.dart';

/// Local cache for decrypted private settings (NIP-78).
///
/// Settings are keyed by pubkey to support multi-account scenarios.
class SettingsRepository {
  static final _store = StoreRef<String, String>('private_settings');
  final Database _db;

  SettingsRepository(this._db);

  static String _keyFor(String pubkey) => 'settings:$pubkey';

  /// Save decrypted settings JSON for a specific pubkey.
  Future<void> save({required String pubkey, required String json}) async {
    await _store.record(_keyFor(pubkey)).put(_db, json);
  }

  /// Load cached decrypted settings JSON for a specific pubkey.
  Future<String?> load({required String pubkey}) async {
    return _store.record(_keyFor(pubkey)).get(_db);
  }

  /// Clear cached settings for a specific pubkey or all.
  Future<void> clear({String? pubkey}) async {
    if (pubkey != null) {
      await _store.record(_keyFor(pubkey)).delete(_db);
    } else {
      await _store.delete(_db);
    }
  }
}
