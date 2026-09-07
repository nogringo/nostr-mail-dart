import 'package:drift/drift.dart';

import 'database.dart';

/// Records event IDs that have been deleted via NIP-09 so they are not
/// re-applied when re-fetched from relays (or re-served from a stale
/// NDK cache that does not yet honor the deletion).
///
/// Scoped per recipient pubkey for account isolation.
class TombstoneRepository {
  final NostrMailDatabase _db;

  TombstoneRepository(this._db);

  /// Record [eventId] as deleted for [recipientPubkey]. Idempotent.
  Future<void> add(String eventId, {required String recipientPubkey}) =>
      addMany([eventId], recipientPubkey: recipientPubkey);

  /// Record every id in [eventIds] as deleted for [recipientPubkey].
  Future<void> addMany(
    Iterable<String> eventIds, {
    required String recipientPubkey,
  }) async {
    final uniqueIds = eventIds.toSet();
    if (uniqueIds.isEmpty) return;

    final createdAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _db.batch(
      (b) => b.insertAllOnConflictUpdate(_db.tombstones, [
        for (final eventId in uniqueIds)
          TombstoneRow(
            eventId: eventId,
            recipientPubkey: recipientPubkey,
            createdAt: createdAt,
          ),
      ]),
    );
  }

  /// True if [eventId] has been tombstoned for [recipientPubkey].
  Future<bool> contains(
    String eventId, {
    required String recipientPubkey,
  }) async {
    final row =
        await (_db.select(_db.tombstones)..where(
              (t) =>
                  t.eventId.equals(eventId) &
                  t.recipientPubkey.equals(recipientPubkey),
            ))
            .getSingleOrNull();
    return row != null;
  }

  /// Delete all tombstones for [recipientPubkey], or pass `null` to wipe
  /// the entire store across all accounts.
  Future<void> clearAll({String? recipientPubkey}) async {
    final statement = _db.delete(_db.tombstones);
    if (recipientPubkey != null) {
      statement.where((t) => t.recipientPubkey.equals(recipientPubkey));
    }
    await statement.go();
  }
}
