import 'package:drift/drift.dart';

import '../models/attachment_ref.dart';
import '../models/email_summary.dart';
import '../models/paginated_result.dart';
import 'database.dart';
import 'mail_address_codec.dart';
import 'match_repository.dart';
import 'models/email_query.dart';
import 'models/email_record.dart';

/// Repository for stored emails.
///
/// Reads go through the `email_states` view, which derives the folder, read
/// and starred state from the labels and matches tables, and through the FTS5
/// index for free-text search.
///
/// Every read takes a [recipientPubkey] and filters on it: this is what
/// keeps multi-account data isolated when several accounts share one
/// database. A row whose [EmailRecord.recipientPubkey] does not match the
/// caller is invisible (and unreachable, even by id).
class EmailRepository {
  final NostrMailDatabase _db;
  final MatchRepository _matchIndex;

  EmailRepository(this._db) : _matchIndex = MatchRepository(_db);

  /// Insert or replace the email and its attachment refs. The state fields
  /// of [record] are not written: labels and matches own them.
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
    await _matchIndex.index(
      emailId: record.id,
      recipientPubkey: record.recipientPubkey,
      from: record.from,
      subject: record.subject,
      hasAttachment: record.attachmentRefs.isNotEmpty,
    );
  });

  /// The folder [id] is in, or null when [recipientPubkey] has no such email.
  Future<String?> folderOf(String id, {required String recipientPubkey}) {
    final v = _db.emailStates;
    return (_db.selectOnly(v)
          ..addColumns([v.folder])
          ..where(v.id.equals(id) & v.recipientPubkey.equals(recipientPubkey)))
        .map((row) => row.read(v.folder)!)
        .getSingleOrNull();
  }

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
    if (q.senderPubkey != null) {
      expr = expr & v.senderPubkey.equals(q.senderPubkey!);
    }
    if (q.fromAddress != null) {
      // Both sides in SQL: SQLite's lower() folds ASCII only, Dart's Unicode.
      expr =
          expr &
          v.fromAddress.lower().equalsExp(
            Variable<String>(q.fromAddress!).lower(),
          );
    }
    if (q.tag != null) {
      final labelled = existsQuery(
        _db.select(_db.labels)..where(
          (l) =>
              l.emailId.equalsExp(v.id) &
              l.recipientPubkey.equals(q.recipientPubkey) &
              l.label.equals('tag:${q.tag}'),
        ),
      );
      final matched = existsQuery(
        _db.select(_db.matches)..where(
          (m) =>
              m.emailId.equalsExp(v.id) &
              m.entryId.equals(q.tag!) &
              m.isFolder.not(),
        ),
      );
      expr = expr & (labelled | matched) & v.folder.isNotIn(['trash', 'spam']);
    }
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

  /// Query the columns a mailbox listing draws, without reading
  /// `light_mime_text` and without parsing any MIME.
  ///
  /// Prefer this over [query] wherever the body is not shown: a row costs a
  /// few hundred bytes instead of the whole message. Attachment refs and
  /// custom labels take one batched query each for the page, never one per
  /// row, and the preview is computed at insert so no full body crosses into
  /// Dart.
  Future<PaginatedResult<EmailSummary>> querySummaries(EmailQuery q) async {
    final total = await count(q);
    final items = await _summaries(
      (v) => _matches(v, q),
      recipientPubkey: q.recipientPubkey,
      sort: q.sort,
      limit: q.limit,
      offset: q.offset,
    );
    return PaginatedResult(items: items, total: total, offset: q.offset ?? 0);
  }

  /// The summary of [id], or null when [recipientPubkey] has no such email.
  Future<EmailSummary?> getSummary(
    String id, {
    required String recipientPubkey,
  }) async {
    final items = await _summaries(
      (v) => v.id.equals(id) & v.recipientPubkey.equals(recipientPubkey),
      recipientPubkey: recipientPubkey,
    );
    return items.singleOrNull;
  }

  Future<List<EmailSummary>> _summaries(
    Expression<bool> Function(EmailStates v) where, {
    required String recipientPubkey,
    EmailSort sort = EmailSort.dateDesc,
    int? limit,
    int? offset,
  }) async {
    final v = _db.emailStates;
    final statement = _db.selectOnly(v)
      ..addColumns([
        v.id,
        v.senderPubkey,
        v.fromAddress,
        v.fromName,
        v.toAddresses,
        v.ccAddresses,
        v.bccAddresses,
        v.subject,
        v.date,
        v.folder,
        v.isRead,
        v.isStarred,
        v.isPublic,
        v.isBridged,
        v.preview,
      ])
      ..where(where(v))
      ..orderBy([
        OrderingTerm(
          expression: v.date,
          mode: sort == EmailSort.dateDesc
              ? OrderingMode.desc
              : OrderingMode.asc,
        ),
      ]);
    if (limit != null || offset != null) {
      statement.limit(limit ?? -1, offset: offset);
    }

    final rows = await statement.get();
    if (rows.isEmpty) return [];

    final ids = [for (final row in rows) row.read(v.id)!];
    final (refs, customLabels, tags) = await (
      _attachmentRefs(ids),
      _customLabels(ids, recipientPubkey: recipientPubkey),
      _tags(ids, recipientPubkey: recipientPubkey),
    ).wait;

    return [
      for (final row in rows)
        EmailSummary(
          id: row.read(v.id)!,
          senderPubkey: row.read(v.senderPubkey)!,
          from: row.read(v.fromAddress)!,
          fromName: row.read(v.fromName),
          to: decodeAddresses(row.read(v.toAddresses)!),
          cc: decodeAddresses(row.read(v.ccAddresses)!),
          bcc: decodeAddresses(row.read(v.bccAddresses)!),
          subject: row.read(v.subject)!,
          preview: row.read(v.preview)!,
          date: DateTime.fromMillisecondsSinceEpoch(row.read(v.date)! * 1000),
          folder: row.read(v.folder)!,
          isRead: row.read(v.isRead)!,
          isStarred: row.read(v.isStarred)!,
          isPublic: row.read(v.isPublic)!,
          isBridged: row.read(v.isBridged)!,
          attachmentRefs: refs[row.read(v.id)!] ?? const [],
          labels: customLabels[row.read(v.id)!] ?? const [],
          tags: tags[row.read(v.id)!] ?? const [],
        ),
    ];
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

  /// Attach the refs, custom labels and tags of [rows], in one query each.
  Future<List<EmailRecord>> _load(
    List<EmailState> rows, {
    required String recipientPubkey,
  }) async {
    if (rows.isEmpty) return [];
    final ids = rows.map((r) => r.id).toList();

    final (refs, customLabels, tags) = await (
      _attachmentRefs(ids),
      _customLabels(ids, recipientPubkey: recipientPubkey),
      _tags(ids, recipientPubkey: recipientPubkey),
    ).wait;

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
          fromName: row.fromName,
          to: decodeAddresses(row.toAddresses),
          cc: decodeAddresses(row.ccAddresses),
          bcc: decodeAddresses(row.bccAddresses),
          subject: row.subject,
          bodyPlain: row.bodyPlain,
          preview: row.preview,
          folder: row.folder,
          isRead: row.isRead,
          isStarred: row.isStarred,
          labels: customLabels[row.id] ?? const [],
          tags: tags[row.id] ?? const [],
        ),
    ];
  }

  /// Attachment metadata for [ids], keyed by email id, in MIME tree order.
  Future<Map<String, List<AttachmentRef>>> _attachmentRefs(
    List<String> ids,
  ) async {
    final rows =
        await (_db.select(_db.attachments)
              ..where((a) => a.emailId.isIn(ids))
              ..orderBy([(a) => OrderingTerm.asc(a.position)]))
            .get();
    final refs = <String, List<AttachmentRef>>{};
    for (final row in rows) {
      refs
          .putIfAbsent(row.emailId, () => [])
          .add(
            AttachmentRef(
              filename: row.filename,
              contentType: row.contentType,
              size: row.size,
              sha256: row.sha256,
              contentId: row.contentId,
            ),
          );
    }
    return refs;
  }

  /// Non-folder labels of [ids], keyed by email id.
  Future<Map<String, List<String>>> _customLabels(
    List<String> ids, {
    required String recipientPubkey,
  }) async {
    final rows =
        await (_db.select(_db.labels)..where(
              (l) =>
                  l.emailId.isIn(ids) &
                  l.recipientPubkey.equals(recipientPubkey),
            ))
            .get();
    final byEmail = <String, Set<String>>{};
    for (final row in rows) {
      if (_isStateLabel(row.label)) continue;
      byEmail.putIfAbsent(row.emailId, () => {}).add(row.label);
    }
    return byEmail.map((id, labels) => MapEntry(id, labels.toList()));
  }

  /// Ids of the user tags holding [ids], by label or by match, keyed by
  /// email id.
  Future<Map<String, List<String>>> _tags(
    List<String> ids, {
    required String recipientPubkey,
  }) async {
    final (labelled, matched) = await (
      (_db.select(_db.labels)..where(
            (l) =>
                l.emailId.isIn(ids) &
                l.recipientPubkey.equals(recipientPubkey) &
                l.label.like('tag:%'),
          ))
          .get(),
      (_db.select(
        _db.matches,
      )..where((m) => m.emailId.isIn(ids) & m.isFolder.not())).get(),
    ).wait;
    final byEmail = <String, Set<String>>{};
    for (final row in labelled) {
      byEmail.putIfAbsent(row.emailId, () => {}).add(row.label.substring(4));
    }
    for (final row in matched) {
      byEmail.putIfAbsent(row.emailId, () => {}).add(row.entryId);
    }
    return byEmail.map((id, tags) => MapEntry(id, tags.toList()));
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
    fromName: r.fromName,
    toAddresses: encodeAddresses(r.to),
    ccAddresses: encodeAddresses(r.cc),
    bccAddresses: encodeAddresses(r.bcc),
    subject: r.subject,
    bodyPlain: r.bodyPlain,
    preview: r.preview,
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
