import 'package:sembast/sembast.dart';

class GiftWrapStore {
  final Database _db;
  final _store = stringMapStoreFactory.store('gift_wraps');

  GiftWrapStore(this._db);

  /// Mark a gift wrap as fetched (not yet processed)
  Future<void> markFetched(String eventId) async {
    final existing = await _store.record(eventId).get(_db);
    if (existing != null) return; // Already known
    await _store.record(eventId).put(_db, {'processed': false});
  }

  /// Mark multiple gift wraps as fetched in a batch
  Future<void> markFetchedBatch(List<String> eventIds) async {
    await _db.transaction((txn) async {
      for (final id in eventIds) {
        final existing = await _store.record(id).get(txn);
        if (existing == null) {
          await _store.record(id).put(txn, {'processed': false});
        }
      }
    });
  }

  /// Mark a gift wrap as processed
  Future<void> markProcessed(String eventId) async {
    await _store.record(eventId).put(_db, {'processed': true});
  }

  /// Mark multiple gift wraps as processed in a batch
  Future<void> markProcessedBatch(List<String> eventIds) async {
    await _db.transaction((txn) async {
      for (final id in eventIds) {
        await _store.record(id).put(txn, {'processed': true});
      }
    });
  }

  /// Get unprocessed gift wrap IDs
  Future<List<String>> getUnprocessed({int? limit}) async {
    final finder = Finder(
      filter: Filter.equals('processed', false),
      limit: limit,
    );
    final records = await _store.find(_db, finder: finder);
    return records.map((r) => r.key).toList();
  }

  /// Check if a gift wrap is already known (fetched or processed)
  Future<bool> isKnown(String eventId) async {
    final record = await _store.record(eventId).get(_db);
    return record != null;
  }

  /// Check if a gift wrap is processed
  Future<bool> isProcessed(String eventId) async {
    final record = await _store.record(eventId).get(_db);
    if (record == null) return false;
    return record['processed'] == true;
  }
}
