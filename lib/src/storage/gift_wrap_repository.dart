import 'package:ndk/ndk.dart' show Nip01Event, Nip01EventModel;
import 'package:sembast/sembast.dart';

/// Repository for raw NIP-59 gift-wrap events.
class GiftWrapRepository {
  final Database _db;
  final _store = stringMapStoreFactory.store('gift_wraps');

  GiftWrapRepository(this._db);

  /// Save a gift wrap event if new. Returns true if it was inserted.
  Future<bool> save(Nip01Event event, {required String recipientPubkey}) async {
    final existing = await _store.record(event.id).get(_db);
    if (existing != null) return false;
    await _store.record(event.id).put(_db, {
      'recipientPubkey': recipientPubkey,
      'event': Nip01EventModel.fromEntity(event).toJson(),
      'processed': false,
    });
    return true;
  }

  /// Get a gift wrap record by its globally unique outer event ID.
  Future<Map<String, dynamic>?> getById(String giftWrapId) async {
    final record = await _store.record(giftWrapId).get(_db);
    if (record == null) return null;
    return record.cast<String, dynamic>();
  }

  /// Get a gift wrap by ID only if it belongs to [recipientPubkey].
  Future<Map<String, dynamic>?> getByIdForRecipient(
    String giftWrapId, {
    required String recipientPubkey,
  }) async {
    final record = await getById(giftWrapId);
    if (record == null) return null;
    if (record['recipientPubkey'] != recipientPubkey) return null;
    return record;
  }

  /// Update a gift wrap with its decrypted seal and rumor.
  Future<void> updateDecrypted({
    required String giftWrapId,
    required Nip01Event seal,
    required Nip01Event rumor,
  }) async {
    final existing = await _store.record(giftWrapId).get(_db);
    if (existing == null) return;
    await _store.record(giftWrapId).put(_db, {
      ...existing,
      'seal': Nip01EventModel.fromEntity(seal).toJson(),
      'rumor': Nip01EventModel.fromEntity(rumor).toJson(),
      'rumorId': rumor.id,
      'processed': true,
    });
  }

  /// Get gift wrap record by its decrypted rumor ID (email ID).
  Future<Map<String, dynamic>?> getByRumorId(String rumorId) async {
    final finder = Finder(filter: Filter.equals('rumorId', rumorId));
    final record = await _store.findFirst(_db, finder: finder);
    return record?.value;
  }

  /// Get a gift wrap by rumor ID only if it belongs to [recipientPubkey].
  Future<Map<String, dynamic>?> getByRumorIdForRecipient(
    String rumorId, {
    required String recipientPubkey,
  }) async {
    final finder = Finder(
      filter: Filter.and([
        Filter.equals('rumorId', rumorId),
        Filter.equals('recipientPubkey', recipientPubkey),
      ]),
    );
    final record = await _store.findFirst(_db, finder: finder);
    return record?.value;
  }

  /// Mark a gift wrap as processed.
  Future<void> markProcessed(String eventId) async {
    final existing = await _store.record(eventId).get(_db);
    if (existing == null) return;
    await _store.record(eventId).put(_db, {...existing, 'processed': true});
  }

  /// Remove a gift wrap record.
  Future<void> remove(String eventId) async {
    await _store.record(eventId).delete(_db);
  }

  /// Remove gift wrap records by their decrypted rumor ids.
  Future<void> removeByRumorIds(Iterable<String> rumorIds) async {
    final uniqueIds = rumorIds.toSet().toList();
    if (uniqueIds.isEmpty) return;

    final finder = Finder(filter: Filter.inList('rumorId', uniqueIds));
    final keys = await _store.findKeys(_db, finder: finder);
    final recordsToDelete = {...keys, ...uniqueIds};
    for (final key in recordsToDelete) {
      await _store.record(key).delete(_db);
    }
  }

  /// Remove gift wrap records by rumor id only if they belong to [recipientPubkey].
  Future<void> removeByRumorIdsForRecipient(
    Iterable<String> rumorIds, {
    required String recipientPubkey,
  }) async {
    final uniqueIds = rumorIds.toSet().toList();
    if (uniqueIds.isEmpty) return;

    final finder = Finder(
      filter: Filter.and([
        Filter.inList('rumorId', uniqueIds),
        Filter.equals('recipientPubkey', recipientPubkey),
      ]),
    );
    final recordsToDelete = await _store.findKeys(_db, finder: finder);
    for (final key in recordsToDelete) {
      await _store.record(key).delete(_db);
    }
  }

  /// Get a single unprocessed gift wrap event by ID.
  Future<Nip01Event?> getUnprocessed(
    String eventId, {
    String? recipientPubkey,
  }) async {
    final record = recipientPubkey == null
        ? await getById(eventId)
        : await getByIdForRecipient(eventId, recipientPubkey: recipientPubkey);
    if (record == null || record['processed'] == true) return null;
    return Nip01EventModel.fromJson(record['event'] as Map);
  }

  /// Get unprocessed gift wrap events.
  Future<List<Nip01Event>> getUnprocessedEvents({
    String? recipientPubkey,
    int? limit,
  }) async {
    final filters = <Filter>[
      Filter.equals('processed', false),
      if (recipientPubkey != null)
        Filter.equals('recipientPubkey', recipientPubkey),
    ];
    final finder = Finder(
      filter: filters.length == 1 ? filters.first : Filter.and(filters),
      limit: limit,
    );
    final records = await _store.find(_db, finder: finder);
    return records
        .map((r) => Nip01EventModel.fromJson(r.value['event'] as Map))
        .cast<Nip01Event>()
        .toList();
  }

  /// Get count of unprocessed (failed) events.
  Future<int> getFailedCount({String? recipientPubkey}) async {
    final filters = <Filter>[
      Filter.equals('processed', false),
      if (recipientPubkey != null)
        Filter.equals('recipientPubkey', recipientPubkey),
    ];
    return _store.count(
      _db,
      filter: filters.length == 1 ? filters.first : Filter.and(filters),
    );
  }

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
