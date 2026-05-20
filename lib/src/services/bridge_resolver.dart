import 'dart:convert';

import 'package:http/http.dart' as http;

import '../exceptions.dart';

// TODO rename to NIP05Resolver

class BridgeResolver {
  final http.Client _client;
  final Map<String, String>? nip05Overrides;

  BridgeResolver({http.Client? client, this.nip05Overrides})
    : _client = client ?? http.Client();

  /// Resolve bridge pubkey via NIP-05 lookup for _smtp@domain
  Future<String> resolveBridgePubkey(String domain) async {
    final nip05 = '_smtp@$domain';
    if (nip05Overrides != null && nip05Overrides!.containsKey(nip05)) {
      return nip05Overrides![nip05]!;
    }

    final url = Uri.https(domain, '/.well-known/nostr.json', {'name': '_smtp'});

    final http.Response response;
    try {
      response = await _client.get(url);
    } catch (e) {
      throw NetworkRequiredException('bridge', 'failed to reach $domain: $e');
    }

    if (response.statusCode != 200) {
      throw BridgeResolutionException(domain);
    }

    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final names = json['names'] as Map<String, dynamic>?;

      if (names == null || !names.containsKey('_smtp')) {
        throw BridgeResolutionException(domain);
      }

      return names['_smtp'] as String;
    } on BridgeResolutionException {
      rethrow;
    } catch (_) {
      throw BridgeResolutionException(domain);
    }
  }

  /// Resolve any NIP-05 identifier (user@domain) to pubkey.
  ///
  /// Returns null when the server replied but the name is not registered.
  /// Throws [NetworkRequiredException] when the server could not be reached
  /// (DNS, socket, timeout) so callers can distinguish "no entry" from
  /// "offline" and surface a reconnect prompt instead of falling through
  /// to a bridge lookup that would fail for the same reason.
  ///
  // TODO: switch to `_ndk.nip05.resolve()` once NDK distinguishes transport
  // failures from "name not found". Today NDK's Nip05Usecase._performFetch
  // swallows every exception into null, so adopting it would cost us this
  // method's offline detection. The win we'd unlock is NDK's built-in
  // NIP-05 cache + in-flight dedup (and `Nip05.relays`), so this swap is
  // worth doing as soon as upstream surfaces the distinction (custom
  // Nip05Repository injection is not enough — the swallow lives one layer
  // above, in the use-case).
  Future<String?> resolveNip05(String identifier) async {
    if (nip05Overrides != null && nip05Overrides!.containsKey(identifier)) {
      return nip05Overrides![identifier]!;
    }

    final parts = identifier.split('@');
    if (parts.length != 2) return null;

    final name = parts[0];
    final domain = parts[1];
    final url = Uri.https(domain, '/.well-known/nostr.json', {'name': name});

    final http.Response response;
    try {
      response = await _client.get(url);
    } catch (e) {
      throw NetworkRequiredException('nip05', 'failed to reach $domain: $e');
    }

    if (response.statusCode != 200) return null;

    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final names = json['names'] as Map<String, dynamic>?;

      if (names == null || !names.containsKey(name)) return null;

      return names[name] as String;
    } catch (_) {
      return null;
    }
  }
}
