import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:ndk/shared/nips/nip01/key_pair.dart';
import 'package:nostr_mail/src/constants.dart';

/// A fresh account whose relay lists name [relays] and are published there:
/// a recipient a send can reach without a test user running it.
Future<KeyPair> listedKeyPair(List<String> relays) async {
  final keyPair = Bip340.generatePrivateKey();
  final ndk = Ndk(
    NdkConfig(
      eventVerifier: Bip340EventVerifier(),
      cache: MemCacheManager(),
      bootstrapRelays: relays,
    ),
  );
  ndk.accounts.loginPrivateKey(
    pubkey: keyPair.publicKey,
    privkey: keyPair.privateKey!,
  );
  await publishRelayLists(ndk, dmRelays: relays, nip65Relays: relays);
  await ndk.destroy();
  return keyPair;
}

/// Publishes the logged account's DM relay list (kind 10050) and NIP-65 (kind
/// 10002) on those relays: without either, a send cannot reach it.
Future<void> publishRelayLists(
  Ndk ndk, {
  required List<String> dmRelays,
  required List<String> nip65Relays,
}) async {
  final pubkey = ndk.accounts.getPublicKey()!;
  for (final event in [
    Nip01Event(
      pubKey: pubkey,
      kind: dmRelayListKind,
      tags: [
        for (final relay in dmRelays) ['relay', relay],
      ],
      content: '',
    ),
    Nip01Event(
      pubKey: pubkey,
      kind: relayListKind,
      tags: [
        for (final relay in nip65Relays) ['r', relay],
      ],
      content: '',
    ),
  ]) {
    await ndk.broadcast
        .broadcast(
          nostrEvent: event,
          specificRelays: {...dmRelays, ...nip65Relays}.toList(),
        )
        .broadcastDoneFuture;
  }
}
