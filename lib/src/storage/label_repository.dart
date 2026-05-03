import 'package:sembast/sembast.dart';

import 'models/email_record.dart';

/// Repository for NIP-32 labels with denormalized email updates.
///
/// Every label mutation is applied atomically to both the label store and
/// the denormalized email record so queries never need joins.
class LabelRepository {
  final Database _db;
  final _labelsStore = stringMapStoreFactory.store('labels');
  final _emailsStore = stringMapStoreFactory.store('emails');

  LabelRepository(this._db);

  String _makeKey(String emailId, String label) => '$emailId:$label';

  /// Save a label and update the denormalized email record atomically.
  Future<void> saveLabel({
    required String emailId,
    required String label,
    required String labelEventId,
    required int timestamp,
  }) async {
    final key = _makeKey(emailId, label);
    await _db.transaction((txn) async {
      await _labelsStore.record(key).put(txn, {
        'emailId': emailId,
        'label': label,
        'labelEventId': labelEventId,
        'timestamp': timestamp,
      });
      await _applyLabelToEmail(txn, emailId, label, add: true);
    });
  }

  /// Remove a label and revert the denormalized email record atomically.
  Future<void> removeLabel(String emailId, String label) async {
    final key = _makeKey(emailId, label);
    await _db.transaction((txn) async {
      await _labelsStore.record(key).delete(txn);
      await _applyLabelToEmail(txn, emailId, label, add: false);
    });
  }

  /// Get the label event ID for a specific email/label combination.
  Future<String?> getLabelEventId(String emailId, String label) async {
    final key = _makeKey(emailId, label);
    final record = await _labelsStore.record(key).get(_db);
    if (record == null) return null;
    return record['labelEventId'] as String?;
  }

  /// Get all labels for an email.
  Future<List<String>> getLabelsForEmail(String emailId) async {
    final finder = Finder(filter: Filter.equals('emailId', emailId));
    final records = await _labelsStore.find(_db, finder: finder);
    return records.map((r) => r.value['label'] as String).toList();
  }

  /// Check if an email has a specific label.
  Future<bool> hasLabel(String emailId, String label) async {
    final key = _makeKey(emailId, label);
    final record = await _labelsStore.record(key).get(_db);
    return record != null;
  }

  /// Get all email IDs that have a specific label.
  Future<List<String>> getEmailIdsWithLabel(String label) async {
    final finder = Finder(filter: Filter.equals('label', label));
    final records = await _labelsStore.find(_db, finder: finder);
    return records.map((r) => r.value['emailId'] as String).toList();
  }

  /// Get email IDs with a label older than [before].
  Future<List<String>> getEmailIdsWithLabelOlderThan(
    String label,
    DateTime before,
  ) async {
    final cutoff = before.millisecondsSinceEpoch ~/ 1000;
    final finder = Finder(
      filter: Filter.and([
        Filter.equals('label', label),
        Filter.or([
          Filter.isNull('timestamp'),
          Filter.lessThanOrEquals('timestamp', cutoff),
        ]),
      ]),
    );
    final records = await _labelsStore.find(_db, finder: finder);
    return records.map((r) => r.value['emailId'] as String).toList();
  }

  /// Delete all labels for an email (used when email is permanently deleted).
  Future<void> deleteLabelsForEmail(String emailId) async {
    final finder = Finder(filter: Filter.equals('emailId', emailId));
    final keys = await _labelsStore.findKeys(_db, finder: finder);
    for (final key in keys) {
      await _labelsStore.record(key).delete(_db);
    }
  }

  /// Get all label records (for finding labels by event ID).
  Future<List<Map<String, dynamic>>> getAllLabels() async {
    final records = await _labelsStore.find(_db);
    return records.map((r) => Map<String, dynamic>.from(r.value)).toList();
  }

  Future<void> clearAll() async {
    await _labelsStore.delete(_db);
  }

  // ── Denormalization helper ──────────────────────────────────────────────

  Future<void> _applyLabelToEmail(
    Transaction txn,
    String emailId,
    String label, {
    required bool add,
  }) async {
    final record = await _emailsStore.record(emailId).get(txn);
    if (record == null) return;
    final email = EmailRecord.fromJson(record as Map<String, dynamic>);

    String? newFolder;
    bool? newIsRead;
    bool? newIsStarred;
    final newLabels = List<String>.of(email.labels);

    if (label.startsWith('folder:')) {
      final folderName = label.substring(7);
      newFolder = add ? folderName : _defaultFolder(email);
    } else if (label == 'state:read') {
      newIsRead = add;
    } else if (label == 'flag:starred') {
      newIsStarred = add;
    } else {
      if (add) {
        if (!newLabels.contains(label)) newLabels.add(label);
      } else {
        newLabels.remove(label);
      }
    }

    final updated = email.copyWith(
      folder: newFolder,
      isRead: newIsRead,
      isStarred: newIsStarred,
      labels: newLabels,
    );
    await _emailsStore.record(emailId).put(txn, updated.toJson());
  }

  /// Heuristic to revert folder when a folder label is removed.
  String _defaultFolder(EmailRecord email) {
    // If we had more metadata we could distinguish inbox/sent.
    // For now, default back to inbox (the most common case when restoring).
    return 'inbox';
  }
}
