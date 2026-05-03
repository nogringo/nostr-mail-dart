import 'package:sembast/sembast.dart';

import 'models/email_query.dart';
import 'models/email_record.dart';

/// Repository for denormalized email records.
///
/// All queries run against a single Sembast store so filtering, sorting and
/// pagination are native and fast.
class EmailRepository {
  final Database _db;
  final _store = stringMapStoreFactory.store('emails');

  EmailRepository(this._db);

  Future<void> save(EmailRecord record) async {
    await _store.record(record.id).put(_db, record.toJson());
  }

  Future<EmailRecord?> getById(String id) async {
    final record = await _store.record(id).get(_db);
    if (record == null) return null;
    return EmailRecord.fromJson(record as Map<String, dynamic>);
  }

  /// Query emails with filters, sorting and pagination.
  Future<PaginatedResult<EmailRecord>> query(EmailQuery q) async {
    final filters = <Filter>[
      if (q.folder != null) Filter.equals('folder', q.folder),
      if (q.isRead != null) Filter.equals('isRead', q.isRead),
      if (q.isStarred != null) Filter.equals('isStarred', q.isStarred),
      if (q.hasAttachments != null)
        q.hasAttachments!
            ? Filter.greaterThan('attachmentCount', 0)
            : Filter.equals('attachmentCount', 0),
      if (q.search != null && q.search!.trim().isNotEmpty)
        Filter.matchesRegExp(
          'searchText',
          RegExp(
            RegExp.escape(q.search!.trim().toLowerCase()),
            caseSensitive: false,
          ),
        ),
    ];

    final filter = filters.isEmpty
        ? null
        : (filters.length == 1 ? filters.first : Filter.and(filters));

    final sortOrder = q.sort == EmailSort.dateDesc
        ? SortOrder('date', false)
        : SortOrder('date', true);

    final total = await _store.count(_db, filter: filter);

    final finder = Finder(
      filter: filter,
      sortOrders: [sortOrder],
      limit: q.limit,
      offset: q.offset,
    );

    final records = await _store.find(_db, finder: finder);
    final items = records
        .map((r) => EmailRecord.fromJson(r.value as Map<String, dynamic>))
        .toList();

    return PaginatedResult(items: items, total: total, offset: q.offset ?? 0);
  }

  /// Get emails by a list of IDs, sorted by date descending.
  Future<List<EmailRecord>> getByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final finder = Finder(
      filter: Filter.inList('id', ids),
      sortOrders: [SortOrder('date', false)],
    );
    final records = await _store.find(_db, finder: finder);
    return records
        .map((r) => EmailRecord.fromJson(r.value as Map<String, dynamic>))
        .toList();
  }

  /// Search emails by free text across from, subject and body.
  ///
  /// Prefer [query] with the [search] field for combined filters.
  Future<List<EmailRecord>> search(
    String text, {
    int? limit,
    int? offset,
  }) async {
    return query(
      EmailQuery(search: text, limit: limit, offset: offset),
    ).then((r) => r.items);
  }

  /// Update denormalized label fields on an email record.
  /// Used by [LabelRepository] to keep the email store consistent.
  Future<void> updateLabels(
    String emailId, {
    String? folder,
    bool? isRead,
    bool? isStarred,
    List<String>? labels,
  }) async {
    final existing = await getById(emailId);
    if (existing == null) return;
    final updated = existing.copyWith(
      folder: folder,
      isRead: isRead,
      isStarred: isStarred,
      labels: labels,
    );
    await save(updated);
  }

  Future<void> delete(String id) async {
    await _store.record(id).delete(_db);
  }

  Future<void> clearAll() async {
    await _store.delete(_db);
  }
}
