import 'package:broadcast_queue_shim_for_ndk/broadcast_queue_shim_for_ndk.dart';
import 'package:ndk/ndk.dart';

import '../constants.dart';
import '../exceptions.dart';

/// Resolves DM and write relays for a given pubkey via NDK.
///
/// The `get*` methods look the lists up now; the `*RelaySet` ones describe the
/// same targets as a [UrlSet] the broadcast queue resolves on its own, so an
/// event can be enqueued without waiting on a lookup. A NIP-65 is looked up on
/// the indexer relays, every other list on the write relays it names.
///
/// An account receives its emails on its DM relays (kind 10050), or on its
/// NIP-65 read relays when it publishes no DM relay list. Neither ever falls
/// back to default relays: nobody reads an email left there. Only the write
/// relays fall back to [defaultNip65Relays].
class RelayResolver {
  final List<String> _defaultNip65Relays;
  final UrlListFn _lookUp;

  RelayResolver(
    Ndk ndk, {
    List<String> indexerRelays = defaultIndexerRelays,
    List<String>? defaultNip65Relays,
  }) : _defaultNip65Relays = defaultNip65Relays ?? recommendedNip65Relays,
       // NIP-59 sends a wrap under an ephemeral key: authenticating to find out
       // where to send it would attach the real sender to it.
       _lookUp = ndkUrlListFn(
         ndk,
         discoveryRelays: indexerRelays,
         auth: const AuthPolicy.never(),
       );

  /// Where [pubkey] receives gift wraps: its DM relays (kind 10050), or its
  /// NIP-65 read relays when it publishes none. Empty when it publishes
  /// neither.
  Future<List<String>> getDmRelays(String pubkey) =>
      _resolve(dmRelaySet([pubkey]));

  /// [getDmRelays], or null when no relay answered the lookup.
  Future<List<String>?> findDmRelays(String pubkey) async =>
      switch (await resolveUrlSet(dmRelaySet([pubkey]), _lookUp)) {
        UrlsResolved(:final urls) => urls,
        UrlsUnavailable() => null,
      };

  /// The NIP-65 write relays of [pubkey], or the defaults when it publishes
  /// none.
  Future<List<String>> getWriteRelays(String pubkey) =>
      _resolve(writeRelaySet(pubkey));

  /// The NIP-65 read relays of [pubkey]: where others publish the events that
  /// mention it. Empty when it publishes none.
  Future<List<String>> getReadRelays(String pubkey) =>
      _resolve(readRelaySet(pubkey));

  /// Throws [NetworkRequiredException] when no relay answered a lookup: a list
  /// that could not be looked up is not a list that does not exist.
  Future<List<String>> _resolve(UrlSet set) async =>
      switch (await resolveUrlSet(set, _lookUp)) {
        UrlsResolved(:final urls) => urls,
        UrlsUnavailable(:final reason) => throw NetworkRequiredException(
          'relay-lists',
          reason,
        ),
      };

  /// Where drafts are saved: the NIP-37 private relays, or the write relays
  /// when the account has none.
  UrlSet draftWriteRelaySet(String pubkey) =>
      UrlSet.fallback([UrlSet.private(pubkey), writeRelaySet(pubkey)]);

  /// Where drafts are read: both, since drafts saved before the account
  /// listed private relays, or by a client ignoring them, are on the write
  /// relays.
  UrlSet draftReadRelaySet(String pubkey) =>
      UrlSet.union([UrlSet.private(pubkey), writeRelaySet(pubkey)]);

  /// [getDmRelays] as a [UrlSet], for each of [pubkeys].
  UrlSet dmRelaySet(List<String> pubkeys) => UrlSet.union([
    for (final p in pubkeys) UrlSet.fallback([UrlSet.dm(p), UrlSet.inbox(p)]),
  ]);

  /// [getWriteRelays] as a [UrlSet]: the NIP-65 write relays of [pubkey], or
  /// the defaults when it publishes no kind 10002.
  UrlSet writeRelaySet(String pubkey) => UrlSet.fallback([
    UrlSet.outbox(pubkey),
    UrlSet.explicit(_defaultNip65Relays),
  ]);

  /// [getReadRelays] as a [UrlSet].
  UrlSet readRelaySet(String pubkey) => UrlSet.inbox(pubkey);
}
