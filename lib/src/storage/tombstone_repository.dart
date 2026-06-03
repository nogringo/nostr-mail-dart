import 'package:sembast/sembast.dart';

/// Records event IDs that have been deleted via NIP-09 so they are not
/// re-applied when re-fetched from relays (or re-served from a stale
/// NDK cache that does not yet honor the deletion).
///
/// Scoped per recipient pubkey for account isolation.
class TombstoneRepository {
  final Database _db;
  final _store = stringMapStoreFactory.store('tombstones');

  TombstoneRepository(this._db);

  /// Record [eventId] as deleted for [recipientPubkey]. Idempotent.
  Future<void> add(String eventId, {required String recipientPubkey}) async {
    await _store.record(eventId).put(_db, {
      'recipientPubkey': recipientPubkey,
      'createdAt': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
  }

  /// Record every id in [eventIds] as deleted for [recipientPubkey].
  Future<void> addMany(
    Iterable<String> eventIds, {
    required String recipientPubkey,
  }) async {
    final uniqueIds = eventIds.toSet().toList();
    if (uniqueIds.isEmpty) return;

    final createdAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _db.transaction((txn) async {
      for (final eventId in uniqueIds) {
        await _store.record(eventId).put(txn, {
          'recipientPubkey': recipientPubkey,
          'createdAt': createdAt,
        });
      }
    });
  }

  /// True if [eventId] has been tombstoned for [recipientPubkey].
  Future<bool> contains(
    String eventId, {
    required String recipientPubkey,
  }) async {
    final record = await _store.record(eventId).get(_db);
    if (record == null) return false;
    return record['recipientPubkey'] == recipientPubkey;
  }

  /// Delete all tombstones for [recipientPubkey], or pass `null` to wipe
  /// the entire store across all accounts.
  Future<void> clearAll({String? recipientPubkey}) async {
    if (recipientPubkey == null) {
      await _store.delete(_db);
      return;
    }
    await _store.delete(
      _db,
      finder: Finder(filter: Filter.equals('recipientPubkey', recipientPubkey)),
    );
  }
}
