import 'package:broadcast_queue_shim_for_ndk/broadcast_queue_shim_for_ndk.dart';
import 'package:ndk/ndk.dart' hide RelaySet;

import '../constants.dart';
import '../exceptions.dart';
import '../models/mail_event.dart';
import '../models/sender_verdict.dart';
import '../storage/sender_repository.dart';
import '../utils/senders_list.dart';
import 'event_bus.dart';
import 'relay_resolver.dart';

/// Writes sender verdicts to the senders list, local-first: each is an Add,
/// applied at once and broadcast to the account's write relays through the
/// offline queue.
class SenderManager {
  final Ndk _ndk;
  final SenderRepository _senders;
  final RelayResolver _relays;
  final EventBus _bus;
  final OfflineBroadcast _broadcastQueue;

  SenderManager(
    this._ndk,
    this._senders,
    this._relays,
    this._bus,
    this._broadcastQueue,
  );

  Future<SenderVerdict?> verdictOf(String senderKey) {
    final pubkey = _ndk.accounts.getPublicKey();
    if (pubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }
    return _senders.verdictOf(senderKey, recipientPubkey: pubkey);
  }

  /// Records [verdicts] in one Add, or in several when one would exceed the
  /// 64 KiB restrictive relays accept, past about 480 senders.
  Future<void> setVerdicts(Map<String, SenderVerdict> verdicts) async {
    final account = _ndk.accounts.getLoggedAccount();
    if (account == null) {
      throw NostrMailException('No account configured in ndk');
    }
    if (!account.signer.canSign()) {
      throw NostrMailException(
        'Cannot write the senders list: no signing capability',
      );
    }
    final pubkey = account.pubkey;
    // A remote signer would ask its user twice for nothing.
    final current = await _senders.verdictsOf(
      verdicts.keys,
      recipientPubkey: pubkey,
    );
    final entries = [
      for (final MapEntry(:key, value: verdict) in verdicts.entries)
        if (current[key] != verdict) (key: key, verdict: verdict.name),
    ];
    if (entries.isEmpty) return;

    // In the same second as the last event on one of these senders, the
    // lowest id would win instead of this one.
    final latest =
        await _senders.latestCreatedAt(
          entries.map((entry) => entry.key),
          recipientPubkey: pubkey,
        ) ??
        0;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final createdAt = now > latest ? now : latest + 1;

    for (final batch in sendersListBatches(entries)) {
      await _publish(account, batch, createdAt);
    }
  }

  Future<void> _publish(
    Account account,
    List<SenderEntry> entries,
    int createdAt,
  ) async {
    final pubkey = account.pubkey;
    final plaintext = sendersListContent(entries);
    final content = await account.signer.encryptNip44(
      plaintext: plaintext,
      recipientPubKey: pubkey,
    );
    if (content == null) {
      throw NostrMailException('Failed to encrypt the senders list');
    }

    final signed = await account.signer.sign(
      Nip01Event(
        pubKey: pubkey,
        kind: listAddKind,
        createdAt: createdAt,
        tags: [
          ['d', sendersListDTag],
        ],
        content: content,
      ),
    );

    // Recorded open, so the sync does not ask the signer to decrypt it again
    // when it comes back from the relays.
    await _senders.saveDecryption(
      eventId: signed.id,
      recipientPubkey: pubkey,
      plaintext: plaintext,
    );
    final changes = await _senders.saveEntries(
      eventId: signed.id,
      recipientPubkey: pubkey,
      isAdd: true,
      createdAt: signed.createdAt,
      entries: entries,
    );
    changes.forEach(
      (key, verdict) =>
          _bus.emit(SenderVerdictChanged(senderKey: key, verdict: verdict)),
    );

    await _broadcastQueue.broadcast(
      signed,
      relaySet: _relays.writeRelaySet(pubkey),
      pubkey: pubkey,
    );
  }
}
