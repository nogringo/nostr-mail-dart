import 'package:sembast/sembast.dart';

import '../models/email.dart';

class EmailStore {
  final Database _db;
  final _emailsStore = stringMapStoreFactory.store('emails');
  final _processedIdsStore = stringMapStoreFactory.store('processed_ids');

  EmailStore(this._db);

  Future<void> saveEmail(Email email) async {
    await _emailsStore.record(email.id).put(_db, email.toJson());
  }

  Future<List<Email>> getEmails({int? limit, int? offset}) async {
    final finder = Finder(
      sortOrders: [SortOrder('date', false)],
      limit: limit,
      offset: offset,
    );

    final records = await _emailsStore.find(_db, finder: finder);
    return records
        .map((r) => Email.fromJson(r.value as Map<String, dynamic>))
        .toList();
  }

  Future<Email?> getEmailById(String id) async {
    final record = await _emailsStore.record(id).get(_db);
    if (record == null) return null;
    return Email.fromJson(record as Map<String, dynamic>);
  }

  /// Get multiple emails by IDs in a single batch query, sorted by date descending
  Future<List<Email>> getEmailsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final finder = Finder(
      filter: Filter.inList('id', ids),
      sortOrders: [SortOrder('date', false)],
    );
    final records = await _emailsStore.find(_db, finder: finder);
    return records
        .map((r) => Email.fromJson(r.value as Map<String, dynamic>))
        .toList();
  }

  Future<void> deleteEmail(String id) async {
    await _emailsStore.record(id).delete(_db);
  }

  Future<bool> isProcessed(String eventId) async {
    final record = await _processedIdsStore.record(eventId).get(_db);
    return record != null;
  }

  Future<void> markProcessed(String eventId) async {
    await _processedIdsStore.record(eventId).put(_db, {'processed': true});
  }
}
