import 'package:drift/drift.dart';

import '../constants.dart';
import 'database.dart';

/// Repository for NIP-32 labels.
///
/// Labels are the source of truth for an email's folder, read and starred
/// state: the `email_states` view derives them, so nothing is copied onto
/// the email row.
///
/// Label records carry their owner's [recipientPubkey] so reads can be
/// scoped per account.
class LabelRepository {
  final NostrMailDatabase _db;

  LabelRepository(this._db);

  Future<void> saveLabel({
    required String emailId,
    required String label,
    required String labelEventId,
    String? wrapId,
    required int timestamp,
    required String recipientPubkey,
  }) async {
    await _db
        .into(_db.labels)
        .insertOnConflictUpdate(
          LabelRow(
            labelEventId: labelEventId,
            emailId: emailId,
            label: label,
            wrapId: wrapId,
            timestamp: timestamp,
            recipientPubkey: recipientPubkey,
          ),
        );
  }

  /// Remove a label, every event carrying it included. No-op if the label
  /// belongs to another account.
  Future<void> removeLabel(
    String emailId,
    String label, {
    required String recipientPubkey,
  }) async {
    await (_db.delete(
      _db.labels,
    )..where((l) => _isLabel(l, emailId, label, recipientPubkey))).go();
  }

  /// Every event carrying [label] on [recipientPubkey]'s [emailId].
  Future<List<LabelRow>> getLabelEvents(
    String emailId,
    String label, {
    required String recipientPubkey,
  }) {
    return (_db.select(
      _db.labels,
    )..where((l) => _isLabel(l, emailId, label, recipientPubkey))).get();
  }

  /// The label event a deletion naming [id] removes: [id] is either the
  /// event's own id or the id of the gift wrap that carried it.
  Future<LabelRow?> getLabelEvent(
    String id, {
    required String recipientPubkey,
  }) {
    return (_db.select(_db.labels)
          ..where(
            (l) =>
                (l.labelEventId.equals(id) | l.wrapId.equals(id)) &
                l.recipientPubkey.equals(recipientPubkey),
          )
          ..limit(1))
        .getSingleOrNull();
  }

  Future<bool> hasLabelEvent(
    String labelEventId, {
    required String recipientPubkey,
  }) async {
    final row =
        await (_db.select(_db.labels)..where(
              (l) =>
                  l.labelEventId.equals(labelEventId) &
                  l.recipientPubkey.equals(recipientPubkey),
            ))
            .getSingleOrNull();
    return row != null;
  }

  Future<void> removeLabelEvent(
    String labelEventId, {
    required String recipientPubkey,
  }) async {
    await (_db.delete(_db.labels)..where(
          (l) =>
              l.labelEventId.equals(labelEventId) &
              l.recipientPubkey.equals(recipientPubkey),
        ))
        .go();
  }

  /// Get all labels for an email belonging to [recipientPubkey].
  Future<List<String>> getLabelsForEmail(
    String emailId, {
    required String recipientPubkey,
  }) async {
    final rows =
        await (_db.select(_db.labels)..where(
              (l) =>
                  l.emailId.equals(emailId) &
                  l.recipientPubkey.equals(recipientPubkey),
            ))
            .get();
    return rows.map((r) => r.label).toSet().toList();
  }

  /// Check if [recipientPubkey]'s [emailId] has [label].
  Future<bool> hasLabel(
    String emailId,
    String label, {
    required String recipientPubkey,
  }) async {
    final row =
        await (_db.select(_db.labels)
              ..where((l) => _isLabel(l, emailId, label, recipientPubkey))
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  /// Get all email IDs with [label] belonging to [recipientPubkey].
  Future<List<String>> getEmailIdsWithLabel(
    String label, {
    required String recipientPubkey,
  }) async {
    final rows =
        await (_db.select(_db.labels)..where(
              (l) =>
                  l.label.equals(label) &
                  l.recipientPubkey.equals(recipientPubkey),
            ))
            .get();
    return rows.map((r) => r.emailId).toSet().toList();
  }

  /// Get email IDs with a label older than [before], scoped by account.
  Future<List<String>> getEmailIdsWithLabelOlderThan(
    String label,
    DateTime before, {
    required String recipientPubkey,
  }) async {
    final cutoff = before.millisecondsSinceEpoch ~/ 1000;
    final rows =
        await (_db.select(_db.labels)..where(
              (l) =>
                  l.label.equals(label) &
                  l.recipientPubkey.equals(recipientPubkey) &
                  l.timestamp.isSmallerOrEqualValue(cutoff),
            ))
            .get();
    return rows.map((r) => r.emailId).toSet().toList();
  }

  /// Every label event attached to any email in [emailIds].
  Future<List<LabelRow>> getLabelEventsForEmails(
    Iterable<String> emailIds, {
    required String recipientPubkey,
  }) async {
    final uniqueIds = emailIds.toSet().toList();
    if (uniqueIds.isEmpty) return [];

    return (_db.select(_db.labels)..where(
          (l) =>
              l.emailId.isIn(uniqueIds) &
              l.recipientPubkey.equals(recipientPubkey),
        ))
        .get();
  }

  /// Delete all labels for an email belonging to [recipientPubkey].
  /// Used when an email is permanently deleted.
  Future<void> deleteLabelsForEmail(
    String emailId, {
    required String recipientPubkey,
  }) async {
    await deleteLabelsForEmails([emailId], recipientPubkey: recipientPubkey);
  }

  /// Delete all labels for emails in [emailIds] belonging to [recipientPubkey].
  Future<void> deleteLabelsForEmails(
    Iterable<String> emailIds, {
    required String recipientPubkey,
  }) async {
    final uniqueIds = emailIds.toSet().toList();
    if (uniqueIds.isEmpty) return;

    await (_db.delete(_db.labels)..where(
          (l) =>
              l.emailId.isIn(uniqueIds) &
              l.recipientPubkey.equals(recipientPubkey),
        ))
        .go();
  }

  /// Delete every label for [recipientPubkey], or pass `null` to wipe the
  /// entire store across all accounts.
  Future<void> clearAll({String? recipientPubkey}) async {
    final statement = _db.delete(_db.labels);
    if (recipientPubkey != null) {
      statement.where((l) => l.recipientPubkey.equals(recipientPubkey));
    }
    await statement.go();
  }

  static Expression<bool> _isLabel(
    Labels l,
    String emailId,
    String label,
    String recipientPubkey,
  ) =>
      l.emailId.equals(emailId) &
      l.label.equals(label) &
      l.recipientPubkey.equals(recipientPubkey);
}

extension LabelDeletion on LabelRow {
  /// What a deletion names: the wrap a relay holds, or the label itself when
  /// it was published in clear.
  String get deletionTarget => wrapId ?? labelEventId;

  int get deletionKind => wrapId == null ? labelKind : giftWrapKind;
}
