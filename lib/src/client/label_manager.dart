import 'package:ndk/ndk.dart';
import 'package:ndk/domain_layer/entities/filter.dart' as ndk;

import '../constants.dart';
import '../exceptions.dart';
import '../models/mail_event.dart';
import '../storage/label_repository.dart';
import 'event_bus.dart';

/// Manages NIP-32 labels with local-first semantics.
///
/// Labels are applied to local storage immediately and broadcast to relays
/// in the background.
class LabelManager {
  final Ndk _ndk;
  final LabelRepository _labels;
  final EventBus _bus;
  final List<String> _defaultWriteRelays;

  LabelManager(
    this._ndk,
    this._labels,

    this._bus, {
    List<String>? defaultWriteRelays,
  }) : _defaultWriteRelays = defaultWriteRelays ?? recommendedDmRelays;

  String? get _pubkey => _ndk.accounts.getPublicKey();

  void _assertPubkey() {
    if (_pubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }
  }

  /// Add a label to an email (local-first).
  Future<void> addLabel(String emailId, String label) async {
    _assertPubkey();
    final pubkey = _pubkey!;

    // Mutual exclusion for folder labels
    if (label.startsWith('folder:')) {
      final all = await _labels.getLabelsForEmail(emailId);
      for (final existing in all) {
        if (existing.startsWith('folder:') && existing != label) {
          await removeLabel(emailId, existing);
        }
      }
    }

    if (await _labels.hasLabel(emailId, label)) return;

    final labelEvent = Nip01Event(
      pubKey: pubkey,
      kind: labelKind,
      tags: [
        ['L', labelNamespace],
        ['l', label, labelNamespace],
        ['e', emailId, '', 'labelled'],
      ],
      content: '',
    );

    final signed = await _ndk.accounts.sign(labelEvent);

    // Save locally FIRST
    await _labels.saveLabel(
      emailId: emailId,
      label: label,
      labelEventId: signed.id,
      timestamp: signed.createdAt,
    );

    // Notify listeners immediately
    _bus.emit(
      LabelAdded(emailId: emailId, label: label, labelEventId: signed.id),
    );

    // Broadcast in background (don't await)
    _getWriteRelays(pubkey).then((relays) {
      _ndk.broadcast.broadcast(nostrEvent: signed, specificRelays: relays);
    });
  }

  /// Remove a label from an email (local-first).
  Future<void> removeLabel(String emailId, String label) async {
    _assertPubkey();
    final pubkey = _pubkey!;

    final labelEventId = await _labels.getLabelEventId(emailId, label);
    if (labelEventId == null) return;

    // Remove locally FIRST
    await _labels.removeLabel(emailId, label);

    // Notify listeners immediately
    _bus.emit(LabelRemoved(emailId: emailId, label: label));

    // Broadcast deletion in background
    final deletionEvent = Nip01Event(
      pubKey: pubkey,
      kind: deletionRequestKind,
      tags: [
        ['e', labelEventId],
        ['k', labelKind.toString()],
      ],
      content: '',
    );

    _ndk.accounts.sign(deletionEvent).then((signed) {
      _getWriteRelays(pubkey).then((relays) {
        _ndk.broadcast.broadcast(nostrEvent: signed, specificRelays: relays);
      });
    });
  }

  // ── Convenience helpers ─────────────────────────────────────────────────

  Future<List<String>> getLabels(String emailId) =>
      _labels.getLabelsForEmail(emailId);

  Future<bool> hasLabel(String emailId, String label) =>
      _labels.hasLabel(emailId, label);

  Future<void> moveToTrash(String emailId) => addLabel(emailId, 'folder:trash');
  Future<void> restoreFromTrash(String emailId) =>
      removeLabel(emailId, 'folder:trash');
  Future<void> moveToArchive(String emailId) =>
      addLabel(emailId, 'folder:archive');
  Future<void> restoreFromArchive(String emailId) =>
      removeLabel(emailId, 'folder:archive');
  Future<void> markAsRead(String emailId) => addLabel(emailId, 'state:read');
  Future<void> markAsUnread(String emailId) =>
      removeLabel(emailId, 'state:read');
  Future<void> star(String emailId) => addLabel(emailId, 'flag:starred');
  Future<void> unstar(String emailId) => removeLabel(emailId, 'flag:starred');

  Future<bool> isTrashed(String emailId) => hasLabel(emailId, 'folder:trash');
  Future<bool> isArchived(String emailId) =>
      hasLabel(emailId, 'folder:archive');
  Future<bool> isRead(String emailId) => hasLabel(emailId, 'state:read');
  Future<bool> isStarred(String emailId) => hasLabel(emailId, 'flag:starred');

  Future<List<String>> getTrashedEmailIds() =>
      _labels.getEmailIdsWithLabel('folder:trash');
  Future<List<String>> getArchivedEmailIds() =>
      _labels.getEmailIdsWithLabel('folder:archive');
  Future<List<String>> getStarredEmailIds() =>
      _labels.getEmailIdsWithLabel('flag:starred');
  Future<List<String>> getReadEmailIds() =>
      _labels.getEmailIdsWithLabel('state:read');

  Future<void> deleteLabelsForEmail(String emailId) =>
      _labels.deleteLabelsForEmail(emailId);

  // ── Relay helper ────────────────────────────────────────────────────────

  Future<List<String>> _getWriteRelays(String pubkey) async {
    final response = _ndk.requests.query(
      filter: ndk.Filter(kinds: [relayListKind], authors: [pubkey], limit: 1),
    );
    final events = await response.future;
    if (events.isEmpty) return _defaultWriteRelays;

    final event = events.reduce((a, b) => a.createdAt > b.createdAt ? a : b);
    final relays = event.tags
        .where(
          (t) =>
              t.isNotEmpty &&
              t[0] == 'r' &&
              (t.length == 2 || (t.length == 3 && t[2] != 'read')),
        )
        .map((t) => t[1])
        .toList();
    return relays.isNotEmpty ? relays : _defaultWriteRelays;
  }
}
