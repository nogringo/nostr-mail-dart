import 'package:sembast/sembast.dart';

import 'models/email_query.dart';
import 'models/email_record.dart';

/// Repository for denormalized email records.
///
/// All queries run against a single Sembast store so filtering, sorting and
/// pagination are native and fast.
///
/// Every read takes a [recipientPubkey] and filters on it — this is what
/// keeps multi-account data isolated when several accounts share one DB.
/// A row whose [EmailRecord.recipientPubkey] does not match the caller is
/// invisible (and unreachable, even by id).
class EmailRepository {
  final Database _db;
  final _store = stringMapStoreFactory.store('emails');

  EmailRepository(this._db);

  Future<void> save(EmailRecord record) async {
    await _store.record(record.id).put(_db, record.toJson());
  }

  /// Returns the email iff it belongs to [recipientPubkey].
  Future<EmailRecord?> getById(
    String id, {
    required String recipientPubkey,
  }) async {
    final record = await _store.record(id).get(_db);
    if (record == null) return null;
    final email = EmailRecord.fromJson(record as Map<String, dynamic>);
    if (email.recipientPubkey != recipientPubkey) return null;
    return email;
  }

  Filter _buildFilter(EmailQuery q) {
    final filters = <Filter>[
      Filter.equals('recipientPubkey', q.recipientPubkey),
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
    return filters.length == 1 ? filters.first : Filter.and(filters);
  }

  /// Count emails matching [q] without loading any records.
  /// Use this for badge counters where the records themselves aren't needed.
  Future<int> count(EmailQuery q) {
    return _store.count(_db, filter: _buildFilter(q));
  }

  /// Query emails with filters, sorting and pagination.
  Future<PaginatedResult<EmailRecord>> query(EmailQuery q) async {
    final filter = _buildFilter(q);

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
  /// Rows belonging to other accounts are silently skipped.
  Future<List<EmailRecord>> getByIds(
    List<String> ids, {
    required String recipientPubkey,
  }) async {
    if (ids.isEmpty) return [];
    final finder = Finder(
      filter: Filter.and([
        Filter.equals('recipientPubkey', recipientPubkey),
        Filter.inList('id', ids),
      ]),
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
    required String recipientPubkey,
    int? limit,
    int? offset,
  }) async {
    return query(
      EmailQuery(
        recipientPubkey: recipientPubkey,
        search: text,
        limit: limit,
        offset: offset,
      ),
    ).then((r) => r.items);
  }

  /// Update denormalized label fields on an email record.
  /// Used by [LabelRepository] to keep the email store consistent.
  Future<void> updateLabels(
    String emailId, {
    required String recipientPubkey,
    String? folder,
    bool? isRead,
    bool? isStarred,
    List<String>? labels,
  }) async {
    final existing = await getById(emailId, recipientPubkey: recipientPubkey);
    if (existing == null) return;
    final updated = existing.copyWith(
      folder: folder,
      isRead: isRead,
      isStarred: isStarred,
      labels: labels,
    );
    await save(updated);
  }

  /// Delete the email iff it belongs to [recipientPubkey].
  Future<void> delete(String id, {required String recipientPubkey}) async {
    final existing = await getById(id, recipientPubkey: recipientPubkey);
    if (existing == null) return;
    await _store.record(id).delete(_db);
  }

  /// Delete every email belonging to [recipientPubkey].
  /// Pass `null` to wipe the entire store across all accounts.
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
