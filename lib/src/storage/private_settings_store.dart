import 'package:sembast/sembast.dart';

/// Local storage for decrypted private settings.
///
/// Caches the decrypted NIP-78 event content so it can be read without
/// requiring the signer (bunker) to be available.
///
/// Settings are keyed by pubkey to support multi-account scenarios.
class PrivateSettingsStore {
  static final _store = StoreRef<String, String>('private_settings');
  final Database _db;

  PrivateSettingsStore(this._db);

  /// Build the storage key for a given pubkey.
  static String _keyFor(String pubkey) => 'settings:$pubkey';

  /// Save decrypted settings JSON to local cache for a specific pubkey.
  Future<void> save({required String pubkey, required String json}) async {
    await _store.record(_keyFor(pubkey)).put(_db, json);
  }

  /// Load cached decrypted settings JSON from local cache for a specific pubkey.
  /// Returns `null` if nothing has been cached for this pubkey.
  Future<String?> load({required String pubkey}) async {
    return _store.record(_keyFor(pubkey)).get(_db);
  }

  /// Clear the cached settings for a specific pubkey.
  Future<void> clear({String? pubkey}) async {
    if (pubkey != null) {
      await _store.record(_keyFor(pubkey)).delete(_db);
    } else {
      await _store.delete(_db);
    }
  }
}
