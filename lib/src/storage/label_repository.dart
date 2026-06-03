import 'package:sembast/sembast.dart';

import 'models/email_record.dart';

/// Repository for NIP-32 labels with denormalized email updates.
///
/// Every label mutation is applied atomically to both the label store and
/// the denormalized email record so queries never need joins.
///
/// Label records carry their owner's [recipientPubkey] (denormalized from
/// the associated email) so reads can be scoped per account without a
/// join.
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
    required String recipientPubkey,
  }) async {
    final key = _makeKey(emailId, label);
    await _db.transaction((txn) async {
      await _labelsStore.record(key).put(txn, {
        'emailId': emailId,
        'label': label,
        'labelEventId': labelEventId,
        'timestamp': timestamp,
        'recipientPubkey': recipientPubkey,
      });
      await _applyLabelToEmail(txn, emailId, label, recipientPubkey, add: true);
    });
  }

  /// Remove a label and revert the denormalized email record atomically.
  /// No-op if the label belongs to another account.
  Future<void> removeLabel(
    String emailId,
    String label, {
    required String recipientPubkey,
  }) async {
    final key = _makeKey(emailId, label);
    await _db.transaction((txn) async {
      final existing = await _labelsStore.record(key).get(txn);
      if (existing == null) return;
      if (existing['recipientPubkey'] != recipientPubkey) return;
      await _labelsStore.record(key).delete(txn);
      await _applyLabelToEmail(
        txn,
        emailId,
        label,
        recipientPubkey,
        add: false,
      );
    });
  }

  /// Get the label event ID for a specific email/label combination
  /// belonging to [recipientPubkey].
  Future<String?> getLabelEventId(
    String emailId,
    String label, {
    required String recipientPubkey,
  }) async {
    final key = _makeKey(emailId, label);
    final record = await _labelsStore.record(key).get(_db);
    if (record == null) return null;
    if (record['recipientPubkey'] != recipientPubkey) return null;
    return record['labelEventId'] as String?;
  }

  /// Get all labels for an email belonging to [recipientPubkey].
  Future<List<String>> getLabelsForEmail(
    String emailId, {
    required String recipientPubkey,
  }) async {
    final finder = Finder(
      filter: Filter.and([
        Filter.equals('emailId', emailId),
        Filter.equals('recipientPubkey', recipientPubkey),
      ]),
    );
    final records = await _labelsStore.find(_db, finder: finder);
    return records.map((r) => r.value['label'] as String).toList();
  }

  /// Check if [recipientPubkey]'s [emailId] has [label].
  Future<bool> hasLabel(
    String emailId,
    String label, {
    required String recipientPubkey,
  }) async {
    final key = _makeKey(emailId, label);
    final record = await _labelsStore.record(key).get(_db);
    if (record == null) return false;
    return record['recipientPubkey'] == recipientPubkey;
  }

  /// Get all email IDs with [label] belonging to [recipientPubkey].
  Future<List<String>> getEmailIdsWithLabel(
    String label, {
    required String recipientPubkey,
  }) async {
    final finder = Finder(
      filter: Filter.and([
        Filter.equals('label', label),
        Filter.equals('recipientPubkey', recipientPubkey),
      ]),
    );
    final records = await _labelsStore.find(_db, finder: finder);
    return records.map((r) => r.value['emailId'] as String).toList();
  }

  /// Get email IDs with a label older than [before], scoped by account.
  Future<List<String>> getEmailIdsWithLabelOlderThan(
    String label,
    DateTime before, {
    required String recipientPubkey,
  }) async {
    final cutoff = before.millisecondsSinceEpoch ~/ 1000;
    final finder = Finder(
      filter: Filter.and([
        Filter.equals('label', label),
        Filter.equals('recipientPubkey', recipientPubkey),
        Filter.or([
          Filter.isNull('timestamp'),
          Filter.lessThanOrEquals('timestamp', cutoff),
        ]),
      ]),
    );
    final records = await _labelsStore.find(_db, finder: finder);
    return records.map((r) => r.value['emailId'] as String).toList();
  }

  /// Get label event IDs attached to any email in [emailIds].
  Future<List<String>> getLabelEventIdsForEmails(
    Iterable<String> emailIds, {
    required String recipientPubkey,
  }) async {
    final uniqueIds = emailIds.toSet().toList();
    if (uniqueIds.isEmpty) return [];

    final finder = Finder(
      filter: Filter.and([
        Filter.inList('emailId', uniqueIds),
        Filter.equals('recipientPubkey', recipientPubkey),
      ]),
    );
    final records = await _labelsStore.find(_db, finder: finder);
    return records
        .map((r) => r.value['labelEventId'] as String?)
        .nonNulls
        .toSet()
        .toList();
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

    final finder = Finder(
      filter: Filter.and([
        Filter.inList('emailId', uniqueIds),
        Filter.equals('recipientPubkey', recipientPubkey),
      ]),
    );
    await _labelsStore.delete(_db, finder: finder);
  }

  /// Get all label records for [recipientPubkey] (used by sync to find
  /// labels by event id when processing label deletions).
  Future<List<Map<String, dynamic>>> getAllLabels({
    required String recipientPubkey,
  }) async {
    final finder = Finder(
      filter: Filter.equals('recipientPubkey', recipientPubkey),
    );
    final records = await _labelsStore.find(_db, finder: finder);
    return records.map((r) => Map<String, dynamic>.from(r.value)).toList();
  }

  /// Delete every label for [recipientPubkey], or pass `null` to wipe the
  /// entire store across all accounts.
  Future<void> clearAll({String? recipientPubkey}) async {
    if (recipientPubkey == null) {
      await _labelsStore.delete(_db);
      return;
    }
    await _labelsStore.delete(
      _db,
      finder: Finder(filter: Filter.equals('recipientPubkey', recipientPubkey)),
    );
  }

  // ── Denormalization helper ──────────────────────────────────────────────

  Future<void> _applyLabelToEmail(
    Transaction txn,
    String emailId,
    String label,
    String recipientPubkey, {
    required bool add,
  }) async {
    final record = await _emailsStore.record(emailId).get(txn);
    if (record == null) return;
    final email = EmailRecord.fromJson(record as Map<String, dynamic>);
    if (email.recipientPubkey != recipientPubkey) return;

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

  /// Restore folder labels to the email's natural mailbox.
  String _defaultFolder(EmailRecord email) {
    return email.senderPubkey == email.recipientPubkey ? 'sent' : 'inbox';
  }
}
