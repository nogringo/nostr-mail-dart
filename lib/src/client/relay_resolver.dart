import 'package:broadcast_queue_shim_for_ndk/broadcast_queue_shim_for_ndk.dart';
import 'package:ndk/ndk.dart' hide RelaySet;
import 'package:ndk/domain_layer/entities/filter.dart' as ndk;

import '../constants.dart';

/// Resolves DM and write relays for a given pubkey via NDK.
///
/// The `get*` methods query the relays now; the `*RelaySet` ones describe the
/// same targets as a [RelaySet] the broadcast queue resolves on its own, so an
/// event can be enqueued without waiting on a lookup.
///
/// Falls back to [defaultDmRelays] when the user has no relay lists configured.
class RelayResolver {
  final Ndk _ndk;
  final List<String> _defaultDmRelays;

  RelayResolver(this._ndk, {List<String>? defaultDmRelays})
    : _defaultDmRelays = defaultDmRelays ?? recommendedDmRelays;

  /// The relays a lookup falls back to when the account publishes no list.
  /// They are also where the broadcast queue looks relay lists up, next to
  /// the public indexers.
  List<String> get defaultRelays => _defaultDmRelays;

  /// Get user's DM relays from NIP-17 kind 10050 event.
  ///
  /// [auth] says which identity the lookup may be attributed to. A lookup for
  /// someone else should pass [RelayAuth.never]: NIP-59 sends the wrap under an
  /// ephemeral key, and authenticating to find out where to send it would
  /// attach the real sender to it.
  Future<List<String>> getDmRelays(String pubkey, {RelayAuth? auth}) async {
    final response = _ndk.requests.query(
      filter: ndk.Filter(kinds: [dmRelayListKind], authors: [pubkey], limit: 1),
      auth: auth,
    );
    final events = await response.future;
    if (events.isEmpty) return _defaultDmRelays;

    final event = events.reduce((a, b) => a.createdAt > b.createdAt ? a : b);
    final relays = event.tags
        .where((t) => t.isNotEmpty && t[0] == 'relay')
        .map((t) => t[1])
        .toList();

    return relays.isNotEmpty ? relays : _defaultDmRelays;
  }

  /// Get user's write relays from NIP-65 kind 10002 event.
  Future<List<String>> getWriteRelays(String pubkey) async {
    final response = _ndk.requests.query(
      filter: ndk.Filter(kinds: [relayListKind], authors: [pubkey], limit: 1),
    );
    final events = await response.future;
    if (events.isEmpty) return _defaultDmRelays;

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

    return relays.isNotEmpty ? relays : _defaultDmRelays;
  }

  /// [getDmRelays] as a [RelaySet]: the NIP-17 DM relays of [pubkeys], or the
  /// defaults when none of them publishes a kind 10050.
  RelaySet dmRelaySet(List<String> pubkeys) => RelaySet.fallback([
    RelaySet.dm(pubkeys),
    // TODO: fall back to RelaySet.inbox(pubkeys) here, and in getDmRelays
    // too, so sends and deletions keep targeting the same relays.
    RelaySet.explicit(_defaultDmRelays),
  ]);

  /// [getWriteRelays] as a [RelaySet]: the NIP-65 write relays of [pubkey], or
  /// the defaults when it publishes no kind 10002.
  RelaySet writeRelaySet(String pubkey) => RelaySet.fallback([
    RelaySet.outbox(pubkey),
    RelaySet.explicit(_defaultDmRelays),
  ]);
}
