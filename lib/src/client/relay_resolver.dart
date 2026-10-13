import 'dart:convert';

import 'package:broadcast_queue_shim_for_ndk/broadcast_queue_shim_for_ndk.dart';
import 'package:ndk/ndk.dart';
import 'package:ndk/domain_layer/entities/filter.dart' as ndk;

import '../constants.dart';

/// Resolves DM and write relays for a given pubkey via NDK.
///
/// The `get*` methods query the relays now; the `*RelaySet` ones describe the
/// same targets as a [UrlSet] the broadcast queue resolves on its own, so an
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
  /// someone else should pass [AuthPolicy.never]: NIP-59 sends the wrap under an
  /// ephemeral key, and authenticating to find out where to send it would
  /// attach the real sender to it.
  Future<List<String>> getDmRelays(String pubkey, {AuthPolicy? auth}) async {
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
  Future<List<String>> getWriteRelays(String pubkey) =>
      _nip65Relays(pubkey, excluding: 'read');

  /// Get user's read relays from NIP-65 kind 10002 event: where others
  /// publish the events that mention them.
  Future<List<String>> getReadRelays(String pubkey) =>
      _nip65Relays(pubkey, excluding: 'write');

  /// An `r` tag without a marker is both read and write.
  Future<List<String>> _nip65Relays(
    String pubkey, {
    required String excluding,
  }) async {
    final response = _ndk.requests.query(
      filter: ndk.Filter(kinds: [relayListKind], authors: [pubkey], limit: 1),
    );
    final events = await response.future;
    if (events.isEmpty) return _defaultDmRelays;

    final event = events.reduce((a, b) => a.createdAt > b.createdAt ? a : b);
    final relays = event.tags
        .where(
          (t) =>
              t.length >= 2 &&
              t[0] == 'r' &&
              (t.length == 2 || t[2] != excluding),
        )
        .map((t) => t[1])
        .toList();

    return relays.isNotEmpty ? relays : _defaultDmRelays;
  }

  /// NIP-37 private relays of [pubkey], from its kind 10013. Empty when it
  /// publishes none, or when no signer here can open it.
  Future<List<String>> getPrivateRelays(String pubkey) async {
    final response = _ndk.requests.query(
      filter: ndk.Filter(
        kinds: [privateRelayListKind],
        authors: [pubkey],
        limit: 1,
      ),
    );
    final events = await response.future;
    if (events.isEmpty) return const [];

    final event = events.reduce((a, b) => a.createdAt > b.createdAt ? a : b);
    final signer = _ndk.accounts.accounts[pubkey]?.signer;
    if (event.content.isEmpty || signer == null) return const [];

    final String? plaintext;
    try {
      plaintext = await _ndk.decryptedEventPayloads.loadOrDecrypt(
        event: event,
        viewerPubKey: pubkey,
        scheme: DecryptedPayloadScheme.nip44,
        decrypt: () => signer.decryptNip44(
          ciphertext: event.content,
          senderPubKey: pubkey,
        ),
      );
    } catch (_) {
      return const [];
    }
    if (plaintext == null) return const [];

    final Object? tags;
    try {
      tags = jsonDecode(plaintext);
    } on FormatException {
      return const [];
    }
    if (tags is! List) return const [];
    return [
      for (final tag in tags)
        if (tag is List &&
            tag.length >= 2 &&
            tag[0] == 'relay' &&
            tag[1] is String)
          tag[1] as String,
    ];
  }

  /// Where drafts are read: [getPrivateRelays], or [getWriteRelays] when the
  /// account has none.
  Future<List<String>> getDraftRelays(String pubkey) async {
    final private = await getPrivateRelays(pubkey);
    return private.isNotEmpty ? private : getWriteRelays(pubkey);
  }

  /// [getDraftRelays] as a [UrlSet].
  UrlSet draftRelaySet(String pubkey) =>
      UrlSet.fallback([UrlSet.private(pubkey), writeRelaySet(pubkey)]);

  /// [getDmRelays] as a [UrlSet]: the NIP-17 DM relays of [pubkeys], or the
  /// defaults when none of them publishes a kind 10050.
  UrlSet dmRelaySet(List<String> pubkeys) => UrlSet.fallback([
    UrlSet.union([for (final p in pubkeys) UrlSet.dm(p)]),
    // TODO: fall back to UrlSet.inbox here, and in getDmRelays too, so sends
    // and deletions keep targeting the same relays.
    UrlSet.explicit(_defaultDmRelays),
  ]);

  /// [getWriteRelays] as a [UrlSet]: the NIP-65 write relays of [pubkey], or
  /// the defaults when it publishes no kind 10002.
  UrlSet writeRelaySet(String pubkey) => UrlSet.fallback([
    UrlSet.outbox(pubkey),
    UrlSet.explicit(_defaultDmRelays),
  ]);

  /// [getReadRelays] as a [UrlSet].
  UrlSet readRelaySet(String pubkey) => UrlSet.fallback([
    UrlSet.inbox(pubkey),
    UrlSet.explicit(_defaultDmRelays),
  ]);
}
