import 'dart:typed_data';

import 'package:idb_shim/idb.dart';

/// Local content-addressed storage for arbitrary binaries.
///
/// Backed by IndexedDB through `idb_shim`, which abstracts the underlying
/// engine across platforms. The caller chooses an [IdbFactory] when
/// constructing the store:
///
/// - Web: `idbFactoryBrowser` from `package:idb_shim/idb_browser.dart`
/// - Flutter native: `getIdbFactorySqflite(databaseFactory)` from
///   `package:idb_sqflite/idb_sqflite.dart`
/// - VM/desktop: `idbFactorySembastIo` from `package:idb_shim/idb_io.dart`
/// - Tests: `newIdbFactoryMemory()` from
///   `package:idb_shim/idb_client_memory.dart`
///
/// Bytes are stored as `Uint8List` and round-tripped without base64
/// encoding on backends that support it natively (browser IndexedDB,
/// SQLite BLOB).
///
/// Typical use cases include caching Blossom attachments, profile avatars
/// and banners for offline access, and providing a local source of truth
/// to rebuild derived stores during a schema migration.
class IdbBlobStore {
  static const _storeName = 'blobs';
  static const _defaultDbName = 'nostr_mail_blobs';
  static const _version = 1;

  final IdbFactory _factory;
  final String _dbName;
  Future<Database>? _opening;

  IdbBlobStore(this._factory, {String dbName = _defaultDbName})
    : _dbName = dbName;

  Future<Database> _open() {
    return _opening ??= _factory.open(
      _dbName,
      version: _version,
      onUpgradeNeeded: (e) {
        final db = e.database;
        if (!db.objectStoreNames.contains(_storeName)) {
          db.createObjectStore(_storeName);
        }
      },
    );
  }

  Future<T> _withStore<T>(
    String mode,
    Future<T> Function(ObjectStore store) action,
  ) async {
    final db = await _open();
    final txn = db.transaction(_storeName, mode);
    final result = await action(txn.objectStore(_storeName));
    await txn.completed;
    return result;
  }

  /// Returns whether a blob for [sha256] is present locally.
  Future<bool> has(String sha256) {
    return _withStore(idbModeReadOnly, (store) async {
      final value = await store.getObject(sha256);
      return value != null;
    });
  }

  /// Returns the bytes for [sha256], or `null` if absent.
  Future<Uint8List?> get(String sha256) {
    return _withStore(idbModeReadOnly, (store) async {
      final value = await store.getObject(sha256);
      if (value == null) return null;
      if (value is Uint8List) return value;
      if (value is List<int>) return Uint8List.fromList(value);
      throw StateError('Unexpected blob type: ${value.runtimeType}');
    });
  }

  /// Persists [bytes] under [sha256]. Overwrites any existing entry.
  Future<void> put(String sha256, Uint8List bytes) {
    return _withStore(idbModeReadWrite, (store) async {
      await store.put(bytes, sha256);
    });
  }

  /// Removes the blob for [sha256] if present. No-op otherwise.
  Future<void> delete(String sha256) {
    return _withStore(idbModeReadWrite, (store) async {
      await store.delete(sha256);
    });
  }

  /// Removes every blob from the store.
  Future<void> clear() {
    return _withStore(idbModeReadWrite, (store) async {
      await store.clear();
    });
  }

  /// Closes the underlying database, if open.
  Future<void> close() async {
    final opening = _opening;
    if (opening == null) return;
    final db = await opening;
    db.close();
    _opening = null;
  }
}
