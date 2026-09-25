import 'package:broadcast_queue_shim_for_ndk/broadcast_queue_shim_for_ndk.dart';
import 'package:ndk/ndk.dart' hide RelaySet;

import '../constants.dart';
import '../exceptions.dart';
import '../models/mail_event.dart';
import '../storage/gift_wrap_repository.dart';
import '../storage/label_repository.dart';
import '../storage/tombstone_repository.dart';
import 'event_bus.dart';
import 'relay_resolver.dart';

/// Manages NIP-32 labels with local-first semantics.
///
/// Labels are applied to local storage immediately and broadcast via the
/// offline broadcast queue, which persists the event and retries until every
/// targeted relay has acknowledged delivery.
class LabelManager {
  final Ndk _ndk;
  final LabelRepository _labels;
  final GiftWrapRepository _giftWraps;
  final TombstoneRepository _tombstones;
  final RelayResolver _relays;
  final EventBus _bus;
  final OfflineBroadcast _broadcastQueue;

  LabelManager(
    this._ndk,
    this._labels,
    this._giftWraps,
    this._tombstones,
    this._relays,
    this._bus,
    this._broadcastQueue,
  );

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
      final all = await _labels.getLabelsForEmail(
        emailId,
        recipientPubkey: pubkey,
      );
      for (final existing in all) {
        if (existing.startsWith('folder:') && existing != label) {
          await removeLabel(emailId, existing);
        }
      }
    }

    if (await _labels.hasLabel(emailId, label, recipientPubkey: pubkey)) return;

    final labelEvent = Nip01Event(
      pubKey: pubkey,
      kind: labelKind,
      // Explicit: left at 0, ndk hashes the id under a second clock read.
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      tags: [
        ['L', labelNamespace],
        ['l', label, labelNamespace],
        ['e', emailId, '', 'labelled'],
      ],
      content: '',
    );

    final signed = await _ndk.accounts.sign(labelEvent);

    // Signed, then wrapped without a seal to the account itself, so relays
    // see neither what is labelled nor when (nostr-mail-labels).
    final wrap = await GiftWrap.wrapEvent(
      recipientPublicKey: pubkey,
      sealEvent: signed,
      eventSignerFactory: _ndk.giftWrap.eventSignerFactory,
      randomizeCreatedAtBefore: signed.createdAt,
    );

    // Recorded open, so the sync does not ask the signer to decrypt it again
    // when it comes back from the relays.
    await _giftWraps.saveOpened(wrap, recipientPubkey: pubkey, rumor: signed);
    await _labels.saveLabel(
      emailId: emailId,
      label: label,
      labelEventId: signed.id,
      wrapId: wrap.id,
      timestamp: signed.createdAt,
      recipientPubkey: pubkey,
    );

    // Notify listeners immediately
    _bus.emit(
      LabelAdded(emailId: emailId, label: label, labelEventId: signed.id),
    );

    // Enqueue for durable broadcast. The outbox persists the event before
    // any network attempt and retries until every DM relay has acked, so a
    // label survives offline use and process death. It resolves the DM
    // relays itself, so labelling never waits on a relay list.
    await _broadcastQueue.broadcast(
      wrap,
      relaySet: _relays.dmRelaySet([pubkey]),
      pubkey: pubkey,
    );
  }

  /// Remove a label from an email (local-first).
  Future<void> removeLabel(String emailId, String label) async {
    _assertPubkey();
    final pubkey = _pubkey!;

    final events = await _labels.getLabelEvents(
      emailId,
      label,
      recipientPubkey: pubkey,
    );
    if (events.isEmpty) return;

    final targets = events.map((e) => e.deletionTarget).toList();
    final kinds = events.map((e) => e.deletionKind).toSet();
    final deletionEvent = Nip01Event(
      pubKey: pubkey,
      kind: deletionRequestKind,
      tags: [
        ...targets.map((id) => ['e', id]),
        ...kinds.map((kind) => ['k', kind.toString()]),
      ],
      content: '',
    );

    final signed = await _ndk.accounts.sign(deletionEvent);

    // Tombstone the label events so they are not re-applied if re-served
    // by a relay (or by NDK's in-memory cache) on a future sync.
    await _tombstones.addMany(targets, recipientPubkey: pubkey);

    await _labels.removeLabel(emailId, label, recipientPubkey: pubkey);

    _bus.emit(LabelRemoved(emailId: emailId, label: label));

    await _broadcastQueue.broadcast(
      signed,
      relaySet: RelaySet.union([
        if (kinds.contains(giftWrapKind)) _relays.dmRelaySet([pubkey]),
        if (kinds.contains(labelKind)) _relays.writeRelaySet(pubkey),
      ]),
      pubkey: pubkey,
    );
  }

  // ── Convenience helpers ─────────────────────────────────────────────────

  Future<List<String>> getLabels(String emailId) {
    _assertPubkey();
    return _labels.getLabelsForEmail(emailId, recipientPubkey: _pubkey!);
  }

  Future<bool> hasLabel(String emailId, String label) {
    _assertPubkey();
    return _labels.hasLabel(emailId, label, recipientPubkey: _pubkey!);
  }

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

  Future<List<String>> getTrashedEmailIds() {
    _assertPubkey();
    return _labels.getEmailIdsWithLabel(
      'folder:trash',
      recipientPubkey: _pubkey!,
    );
  }

  Future<List<String>> getArchivedEmailIds() {
    _assertPubkey();
    return _labels.getEmailIdsWithLabel(
      'folder:archive',
      recipientPubkey: _pubkey!,
    );
  }

  Future<List<String>> getStarredEmailIds() {
    _assertPubkey();
    return _labels.getEmailIdsWithLabel(
      'flag:starred',
      recipientPubkey: _pubkey!,
    );
  }

  Future<List<String>> getReadEmailIds() {
    _assertPubkey();
    return _labels.getEmailIdsWithLabel(
      'state:read',
      recipientPubkey: _pubkey!,
    );
  }

  Future<void> deleteLabelsForEmail(String emailId) {
    _assertPubkey();
    return _labels.deleteLabelsForEmail(emailId, recipientPubkey: _pubkey!);
  }
}
