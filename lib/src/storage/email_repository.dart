import 'package:drift/drift.dart';

import '../models/attachment_ref.dart';
import 'database.dart';
import 'models/email_query.dart';
import 'models/email_record.dart';

/// Repository for stored emails.
///
/// Reads go through the `email_states` view, which derives the folder, read
/// and starred state from the labels table, and through the FTS5 index for
/// free-text search.
///
/// Every read takes a [recipientPubkey] and filters on it: this is what
/// keeps multi-account data isolated when several accounts share one
/// database. A row whose [EmailRecord.recipientPubkey] does not match the
/// caller is invisible (and unreachable, even by id).
class EmailRepository {
  final NostrMailDatabase _db;

  EmailRepository(this._db);

  /// Insert or replace the email and its attachment refs. The state fields
  /// of [record] are not written: labels own them.
  Future<void> save(EmailRecord record) => _db.transaction(() async {
    await _db.into(_db.emails).insertOnConflictUpdate(_toRow(record));
    await (_db.delete(
      _db.attachments,
    )..where((a) => a.emailId.equals(record.id))).go();
    await _db.batch(
      (b) => b.insertAll(_db.attachments, [
        for (final (i, ref) in record.attachmentRefs.indexed)
          AttachmentRow(
            emailId: record.id,
            position: i,
            filename: ref.filename,
            contentType: ref.contentType,
            size: ref.size,
            sha256: ref.sha256,
            contentId: ref.contentId,
          ),
      ]),
    );
  });

  /// Returns the email iff it belongs to [recipientPubkey].
  Future<EmailRecord?> getById(
    String id, {
    required String recipientPubkey,
  }) async {
    final row =
        await (_db.select(_db.emailStates)..where(
              (v) =>
                  v.id.equals(id) & v.recipientPubkey.equals(recipientPubkey),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    final records = await _load([row], recipientPubkey: recipientPubkey);
    return records.single;
  }

  Expression<bool> _matches(EmailStates v, EmailQuery q) {
    var expr = v.recipientPubkey.equals(q.recipientPubkey);
    if (q.folder != null) expr = expr & v.folder.equals(q.folder!);
    if (q.isRead != null) expr = expr & v.isRead.equals(q.isRead!);
    if (q.isStarred != null) expr = expr & v.isStarred.equals(q.isStarred!);
    if (q.hasAttachments != null) {
      final hasAttachments = existsQuery(
        _db.select(_db.attachments)..where((a) => a.emailId.equalsExp(v.id)),
      );
      expr = expr & (q.hasAttachments! ? hasAttachments : hasAttachments.not());
    }
    final pattern = _ftsPattern(q.search);
    if (pattern != null) {
      final matching =
          _db.selectOnly(_db.emails).join([
              innerJoin(
                _db.emailSearch,
                const CustomExpression<int>(
                  'email_search.rowid',
                ).equalsExp(_db.emails.rowId),
              ),
            ])
            ..addColumns([_db.emails.id])
            ..where(_Fts5Match(pattern));
      expr = expr & v.id.isInQuery(matching);
    }
    return expr;
  }

  /// Count emails matching [q] without loading any records.
  /// Use this for badge counters where the records themselves aren't needed.
  Future<int> count(EmailQuery q) async {
    final total = countAll();
    final row =
        await (_db.selectOnly(_db.emailStates)
              ..addColumns([total])
              ..where(_matches(_db.emailStates, q)))
            .getSingle();
    return row.read(total)!;
  }

  /// Query emails with filters, sorting and pagination.
  Future<PaginatedResult<EmailRecord>> query(EmailQuery q) async {
    final total = await count(q);

    final statement = _db.select(_db.emailStates)
      ..where((v) => _matches(v, q))
      ..orderBy([
        (v) => OrderingTerm(
          expression: v.date,
          mode: q.sort == EmailSort.dateDesc
              ? OrderingMode.desc
              : OrderingMode.asc,
        ),
      ]);
    if (q.limit != null || q.offset != null) {
      statement.limit(q.limit ?? -1, offset: q.offset);
    }

    final rows = await statement.get();
    final items = await _load(rows, recipientPubkey: q.recipientPubkey);
    return PaginatedResult(items: items, total: total, offset: q.offset ?? 0);
  }

  /// Get emails by a list of IDs, sorted by date descending.
  /// Rows belonging to other accounts are silently skipped.
  Future<List<EmailRecord>> getByIds(
    List<String> ids, {
    required String recipientPubkey,
  }) async {
    if (ids.isEmpty) return [];
    final rows =
        await (_db.select(_db.emailStates)
              ..where(
                (v) =>
                    v.recipientPubkey.equals(recipientPubkey) & v.id.isIn(ids),
              )
              ..orderBy([(v) => OrderingTerm.desc(v.date)]))
            .get();
    return _load(rows, recipientPubkey: recipientPubkey);
  }

  /// Search emails by words or word prefixes across from, subject and body.
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

  /// Delete the email iff it belongs to [recipientPubkey].
  Future<void> delete(String id, {required String recipientPubkey}) async {
    await (_db.delete(_db.emails)..where(
          (e) => e.id.equals(id) & e.recipientPubkey.equals(recipientPubkey),
        ))
        .go();
  }

  /// Delete emails whose ids are in [ids], scoped to [recipientPubkey].
  Future<void> deleteByIds(
    Iterable<String> ids, {
    required String recipientPubkey,
  }) async {
    final uniqueIds = ids.toSet().toList();
    if (uniqueIds.isEmpty) return;
    await (_db.delete(_db.emails)..where(
          (e) =>
              e.recipientPubkey.equals(recipientPubkey) & e.id.isIn(uniqueIds),
        ))
        .go();
  }

  /// Delete every email belonging to [recipientPubkey].
  /// Pass `null` to wipe the entire store across all accounts.
  Future<void> clearAll({String? recipientPubkey}) async {
    final statement = _db.delete(_db.emails);
    if (recipientPubkey != null) {
      statement.where((e) => e.recipientPubkey.equals(recipientPubkey));
    }
    await statement.go();
  }

  /// Attach the refs and custom labels of [rows], in one query each.
  Future<List<EmailRecord>> _load(
    List<EmailState> rows, {
    required String recipientPubkey,
  }) async {
    if (rows.isEmpty) return [];
    final ids = rows.map((r) => r.id).toList();

    final attachments =
        await (_db.select(_db.attachments)
              ..where((a) => a.emailId.isIn(ids))
              ..orderBy([(a) => OrderingTerm.asc(a.position)]))
            .get();
    final refs = <String, List<AttachmentRef>>{};
    for (final a in attachments) {
      refs
          .putIfAbsent(a.emailId, () => [])
          .add(
            AttachmentRef(
              filename: a.filename,
              contentType: a.contentType,
              size: a.size,
              sha256: a.sha256,
              contentId: a.contentId,
            ),
          );
    }

    final labels =
        await (_db.select(_db.labels)..where(
              (l) =>
                  l.emailId.isIn(ids) &
                  l.recipientPubkey.equals(recipientPubkey),
            ))
            .get();
    final customLabels = <String, List<String>>{};
    for (final l in labels) {
      if (_isStateLabel(l.label)) continue;
      customLabels.putIfAbsent(l.emailId, () => []).add(l.label);
    }

    return [
      for (final row in rows)
        EmailRecord(
          id: row.id,
          senderPubkey: row.senderPubkey,
          recipientPubkey: row.recipientPubkey,
          isPublic: row.isPublic,
          isBridged: row.isBridged,
          lightMimeText: row.lightMimeText,
          attachmentRefs: refs[row.id] ?? const [],
          blossomHash: row.blossomHash,
          decryptionKey: row.decryptionKey,
          decryptionNonce: row.decryptionNonce,
          createdAt: row.createdAt,
          date: row.date,
          from: row.fromAddress,
          subject: row.subject,
          bodyPlain: row.bodyPlain,
          folder: row.folder,
          isRead: row.isRead,
          isStarred: row.isStarred,
          labels: customLabels[row.id] ?? const [],
        ),
    ];
  }

  static bool _isStateLabel(String label) =>
      label.startsWith('folder:') ||
      label == 'state:read' ||
      label == 'flag:starred';

  static EmailRow _toRow(EmailRecord r) => EmailRow(
    id: r.id,
    senderPubkey: r.senderPubkey,
    recipientPubkey: r.recipientPubkey,
    isPublic: r.isPublic,
    isBridged: r.isBridged,
    lightMimeText: r.lightMimeText,
    blossomHash: r.blossomHash,
    decryptionKey: r.decryptionKey,
    decryptionNonce: r.decryptionNonce,
    createdAt: r.createdAt,
    date: r.date,
    fromAddress: r.from,
    subject: r.subject,
    bodyPlain: r.bodyPlain,
  );

  /// Every word of [search] as a quoted prefix term, so user input never
  /// reaches the FTS5 query parser as syntax.
  static String? _ftsPattern(String? search) {
    if (search == null) return null;
    final words = search
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty);
    if (words.isEmpty) return null;
    return words.map((w) => '"${w.replaceAll('"', '""')}"*').join(' ');
  }
}

class _Fts5Match extends Expression<bool> {
  final String pattern;

  const _Fts5Match(this.pattern);

  @override
  void writeInto(GenerationContext context) {
    context.buffer.write('email_search MATCH ');
    Variable<String>(pattern).writeInto(context);
  }
}
