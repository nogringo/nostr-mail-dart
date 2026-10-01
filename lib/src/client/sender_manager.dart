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

  Future<void> setVerdict(String senderKey, SenderVerdict verdict) async {
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
    if (await _senders.verdictOf(senderKey, recipientPubkey: pubkey) ==
        verdict) {
      return;
    }

    final entries = [(key: senderKey, verdict: verdict.name)];
    final plaintext = sendersListContent(entries);
    final content = await account.signer.encryptNip44(
      plaintext: plaintext,
      recipientPubKey: pubkey,
    );
    if (content == null) {
      throw NostrMailException('Failed to encrypt the senders list');
    }

    // In the same second as the last event on this sender, the lowest id would
    // win instead of this one.
    final latest =
        await _senders.latestCreatedAt(senderKey, recipientPubkey: pubkey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final signed = await account.signer.sign(
      Nip01Event(
        pubKey: pubkey,
        kind: listAddKind,
        createdAt: now > latest ? now : latest + 1,
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
