import 'package:ndk/ndk.dart' show Nip01Event, Nip01EventModel;
import 'package:sembast/sembast.dart';

class GiftWrapStore {
  final Database _db;
  final _store = stringMapStoreFactory.store('gift_wraps');

  GiftWrapStore(this._db);

  /// Save a gift wrap event if new, returns true if it was new
  Future<bool> save(Nip01Event event) async {
    final existing = await _store.record(event.id).get(_db);
    if (existing != null) return false;
    await _store.record(event.id).put(_db, {
      'event': Nip01EventModel.fromEntity(event).toJson(),
      'processed': false,
    });
    return true;
  }

  /// Mark a gift wrap as processed
  Future<void> markProcessed(String eventId) async {
    final existing = await _store.record(eventId).get(_db);
    if (existing == null) return;
    await _store.record(eventId).put(_db, {...existing, 'processed': true});
  }

  /// Remove a gift wrap record
  Future<void> remove(String eventId) async {
    await _store.record(eventId).delete(_db);
  }

  /// Get a single unprocessed gift wrap event by ID
  Future<Nip01Event?> getUnprocessed(String eventId) async {
    final record = await _store.record(eventId).get(_db);
    if (record == null || record['processed'] == true) return null;
    return Nip01EventModel.fromJson(record['event'] as Map);
  }

  /// Get unprocessed gift wrap events
  Future<List<Nip01Event>> getUnprocessedEvents({int? limit}) async {
    final finder = Finder(
      filter: Filter.equals('processed', false),
      limit: limit,
    );
    final records = await _store.find(_db, finder: finder);
    return records
        .map((r) => Nip01EventModel.fromJson(r.value['event'] as Map))
        .cast<Nip01Event>()
        .toList();
  }

  /// Get count of unprocessed (failed) events
  Future<int> getFailedCount() async {
    return await _store.count(_db, filter: Filter.equals('processed', false));
  }

  /// Delete all gift wraps
  Future<void> clearAll() async {
    await _store.delete(_db);
  }
}
