import 'package:drift/drift.dart';

import '../models/mail_entry.dart';
import '../models/private_settings.dart';
import 'database.dart';

/// Keeps the `matches` table in step with the `match` conditions of the
/// account's user folders and tags.
///
/// The conditions come from the decrypted settings in the same database, so
/// `SettingsRepository` rebuilds the table when they change and
/// `EmailRepository` indexes each email it saves.
class MatchRepository {
  final NostrMailDatabase _db;

  MatchRepository(this._db);

  /// Recompute every match of [recipientPubkey].
  Future<void> rebuild(String recipientPubkey) => _db.transaction(() async {
    final rules = await _rulesOf(recipientPubkey);
    await (_db.delete(
      _db.matches,
    )..where((m) => m.recipientPubkey.equals(recipientPubkey))).go();
    if (rules.isEmpty) return;

    final e = _db.emails;
    final hasAttachment = existsQuery(
      _db.select(_db.attachments)..where((a) => a.emailId.equalsExp(e.id)),
    );
    final rows =
        await (_db.selectOnly(e)
              ..addColumns([e.id, e.fromAddress, e.subject, hasAttachment])
              ..where(e.recipientPubkey.equals(recipientPubkey)))
            .get();
    await _insert([
      for (final row in rows)
        ...rules.matchesOf(
          emailId: row.read(e.id)!,
          recipientPubkey: recipientPubkey,
          from: row.read(e.fromAddress)!,
          subject: row.read(e.subject)!,
          hasAttachment: row.read(hasAttachment)!,
        ),
    ]);
  });

  /// Recompute the matches of one email.
  Future<void> index({
    required String emailId,
    required String recipientPubkey,
    required String from,
    required String subject,
    required bool hasAttachment,
  }) async {
    await (_db.delete(
      _db.matches,
    )..where((m) => m.emailId.equals(emailId))).go();
    final rules = await _rulesOf(recipientPubkey);
    if (rules.isEmpty) return;
    await _insert(
      rules.matchesOf(
        emailId: emailId,
        recipientPubkey: recipientPubkey,
        from: from,
        subject: subject,
        hasAttachment: hasAttachment,
      ),
    );
  }

  /// Whether going from [before] to [after] settings moves any email.
  static bool rulesChanged(String? before, String after) =>
      _Rules.parse(before).key != _Rules.parse(after).key;

  // A settings event can repeat an id across folders and tags: the first wins.
  Future<void> _insert(List<MatchRow> rows) => _db.batch(
    (b) => b.insertAll(_db.matches, rows, mode: InsertMode.insertOrIgnore),
  );

  Future<_Rules> _rulesOf(String recipientPubkey) async {
    final row = await (_db.select(
      _db.settings,
    )..where((s) => s.pubkey.equals(recipientPubkey))).getSingleOrNull();
    return _Rules.parse(row?.json);
  }
}

class _Rules {
  /// In display order, so a folder's index is its rank.
  final List<MailEntry> folders;
  final List<MailEntry> tags;

  _Rules(Iterable<MailEntry> folders, Iterable<MailEntry> tags)
    : folders = sortEntries(folders.where((f) => f.match != null)),
      tags = tags.where((t) => t.match != null).toList();

  factory _Rules.parse(String? settingsJson) {
    if (settingsJson == null || settingsJson.isEmpty) return _Rules([], []);
    try {
      final settings = PrivateSettings.fromJson(settingsJson);
      return _Rules(settings.folders ?? [], settings.tags ?? []);
    } catch (_) {
      return _Rules([], []);
    }
  }

  bool get isEmpty => folders.isEmpty && tags.isEmpty;

  String get key => [
    for (final f in folders) '${f.id}:${f.match!.toJson()}',
    '|',
    for (final t in tags) '${t.id}:${t.match!.toJson()}',
  ].join(',');

  List<MatchRow> matchesOf({
    required String emailId,
    required String recipientPubkey,
    required String from,
    required String subject,
    required bool hasAttachment,
  }) {
    bool holds(MailEntry entry) => entry.match!.matches(
      from: from,
      subject: subject,
      hasAttachment: hasAttachment,
    );
    return [
      for (final (rank, folder) in folders.indexed)
        if (holds(folder))
          MatchRow(
            emailId: emailId,
            recipientPubkey: recipientPubkey,
            entryId: folder.id,
            isFolder: true,
            rank: rank,
          ),
      for (final tag in tags)
        if (holds(tag))
          MatchRow(
            emailId: emailId,
            recipientPubkey: recipientPubkey,
            entryId: tag.id,
            isFolder: false,
            rank: 0,
          ),
    ];
  }
}
