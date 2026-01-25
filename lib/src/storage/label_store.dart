import 'package:sembast/sembast.dart';

class LabelStore {
  final Database _db;
  final _labelsStore = stringMapStoreFactory.store('labels');

  LabelStore(this._db);

  /// Save a label for an email
  /// [emailId] is the gift wrap event ID
  /// [label] is the label string (e.g., 'folder:trash', 'state:read')
  /// [labelEventId] is the kind 1985 event ID (needed for deletion)
  Future<void> saveLabel({
    required String emailId,
    required String label,
    required String labelEventId,
  }) async {
    final key = _makeKey(emailId, label);
    await _labelsStore.record(key).put(_db, {
      'emailId': emailId,
      'label': label,
      'labelEventId': labelEventId,
    });
  }

  /// Remove a label from an email
  Future<void> removeLabel(String emailId, String label) async {
    final key = _makeKey(emailId, label);
    await _labelsStore.record(key).delete(_db);
  }

  /// Get the label event ID for a specific email/label combination
  /// Returns null if the label doesn't exist
  Future<String?> getLabelEventId(String emailId, String label) async {
    final key = _makeKey(emailId, label);
    final record = await _labelsStore.record(key).get(_db);
    if (record == null) return null;
    return record['labelEventId'] as String?;
  }

  /// Get all labels for an email
  Future<List<String>> getLabelsForEmail(String emailId) async {
    final finder = Finder(filter: Filter.equals('emailId', emailId));
    final records = await _labelsStore.find(_db, finder: finder);
    return records.map((r) => r.value['label'] as String).toList();
  }

  /// Get all email IDs that have a specific label
  Future<List<String>> getEmailIdsWithLabel(String label) async {
    final finder = Finder(filter: Filter.equals('label', label));
    final records = await _labelsStore.find(_db, finder: finder);
    return records.map((r) => r.value['emailId'] as String).toList();
  }

  /// Check if an email has a specific label
  Future<bool> hasLabel(String emailId, String label) async {
    final key = _makeKey(emailId, label);
    final record = await _labelsStore.record(key).get(_db);
    return record != null;
  }

  /// Delete all labels for an email (used when email is permanently deleted)
  Future<void> deleteLabelsForEmail(String emailId) async {
    final finder = Finder(filter: Filter.equals('emailId', emailId));
    final keys = await _labelsStore.findKeys(_db, finder: finder);
    for (final key in keys) {
      await _labelsStore.record(key).delete(_db);
    }
  }

  /// Get all label records (for finding labels by event ID)
  Future<List<Map<String, dynamic>>> getAllLabels() async {
    final records = await _labelsStore.find(_db);
    return records.map((r) => Map<String, dynamic>.from(r.value)).toList();
  }

  String _makeKey(String emailId, String label) => '$emailId:$label';
}
