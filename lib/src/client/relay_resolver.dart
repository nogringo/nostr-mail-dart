import 'package:ndk/ndk.dart';
import 'package:ndk/domain_layer/entities/filter.dart' as ndk;

import '../constants.dart';

/// Resolves DM and write relays for a given pubkey via NDK.
///
/// Falls back to [defaultDmRelays] when the user has no relay lists configured.
class RelayResolver {
  final Ndk _ndk;
  final List<String> _defaultDmRelays;

  RelayResolver(this._ndk, {List<String>? defaultDmRelays})
    : _defaultDmRelays = defaultDmRelays ?? recommendedDmRelays;

  /// Get user's DM relays from NIP-17 kind 10050 event.
  Future<List<String>> getDmRelays(String pubkey) async {
    final response = _ndk.requests.query(
      filter: ndk.Filter(kinds: [dmRelayListKind], authors: [pubkey], limit: 1),
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
}
