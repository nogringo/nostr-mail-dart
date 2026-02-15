import 'package:sembast/sembast.dart';

import '../models/email.dart';

class EmailStore {
  final Database _db;
  final _emailsStore = stringMapStoreFactory.store('emails');

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

  /// Get emails sent by a specific pubkey, sorted by date descending
  Future<List<Email>> getEmailsBySender(
    String senderPubkey, {
    int? limit,
    int? offset,
  }) async {
    final finder = Finder(
      filter: Filter.equals('senderPubkey', senderPubkey),
      sortOrders: [SortOrder('date', false)],
      limit: limit,
      offset: offset,
    );
    final records = await _emailsStore.find(_db, finder: finder);
    return records
        .map((r) => Email.fromJson(r.value as Map<String, dynamic>))
        .toList();
  }

  /// Get emails received by a specific pubkey (excluding sent), sorted by date descending
  Future<List<Email>> getEmailsByRecipient(
    String recipientPubkey, {
    int? limit,
    int? offset,
  }) async {
    final finder = Finder(
      filter: Filter.and([
        Filter.equals('recipientPubkey', recipientPubkey),
        Filter.notEquals('senderPubkey', recipientPubkey),
      ]),
      sortOrders: [SortOrder('date', false)],
      limit: limit,
      offset: offset,
    );
    final records = await _emailsStore.find(_db, finder: finder);
    return records
        .map((r) => Email.fromJson(r.value as Map<String, dynamic>))
        .toList();
  }

  /// Delete all emails
  Future<void> clearAll() async {
    await _emailsStore.delete(_db);
  }
}
