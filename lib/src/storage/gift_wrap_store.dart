import 'package:ndk/ndk.dart' show Nip01Event, Nip01EventModel;
import 'package:sembast/sembast.dart';

class GiftWrapStore {
  final Database _db;
  final _store = stringMapStoreFactory.store('gift_wraps');

  GiftWrapStore(this._db);

  /// Save a gift wrap event (not yet processed)
  Future<void> save(Nip01Event event) async {
    final existing = await _store.record(event.id).get(_db);
    if (existing != null) return; // Already known
    await _store.record(event.id).put(_db, {
      'event': Nip01EventModel.fromEntity(event).toJson(),
      'processed': false,
    });
  }

  /// Save multiple gift wrap events in a batch
  Future<void> saveBatch(List<Nip01Event> events) async {
    if (events.isEmpty) return;
    await _db.transaction((txn) async {
      for (final event in events) {
        final existing = await _store.record(event.id).get(txn);
        if (existing == null) {
          await _store.record(event.id).put(txn, {
            'event': Nip01EventModel.fromEntity(event).toJson(),
            'processed': false,
          });
        }
      }
    });
  }

  /// Mark a gift wrap as processed (keeps the event data)
  Future<void> markProcessed(String eventId) async {
    final existing = await _store.record(eventId).get(_db);
    if (existing == null) return;
    await _store.record(eventId).put(_db, {...existing, 'processed': true});
  }

  /// Mark multiple gift wraps as processed in a batch
  Future<void> markProcessedBatch(List<String> eventIds) async {
    await _db.transaction((txn) async {
      for (final id in eventIds) {
        final existing = await _store.record(id).get(txn);
        if (existing == null) continue;
        await _store.record(id).put(txn, {...existing, 'processed': true});
      }
    });
  }

  /// Remove a gift wrap record (when email is deleted)
  Future<void> remove(String eventId) async {
    await _store.record(eventId).delete(_db);
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
