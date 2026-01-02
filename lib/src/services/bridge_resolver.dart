import 'dart:convert';

import 'package:http/http.dart' as http;

import '../exceptions.dart';

class BridgeResolver {
  final http.Client _client;

  BridgeResolver({http.Client? client}) : _client = client ?? http.Client();

  /// Resolve bridge pubkey via NIP-05 lookup for _smtp@domain
  Future<String> resolveBridgePubkey(String domain) async {
    final url = Uri.https(domain, '/.well-known/nostr.json', {'name': '_smtp'});

    try {
      final response = await _client.get(url);

      if (response.statusCode != 200) {
        throw BridgeResolutionException(domain);
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final names = json['names'] as Map<String, dynamic>?;

      if (names == null || !names.containsKey('_smtp')) {
        throw BridgeResolutionException(domain);
      }

      return names['_smtp'] as String;
    } catch (e) {
      if (e is BridgeResolutionException) rethrow;
      throw BridgeResolutionException(domain);
    }
  }

  /// Resolve any NIP-05 identifier (user@domain) to pubkey
  Future<String?> resolveNip05(String identifier) async {
    final parts = identifier.split('@');
    if (parts.length != 2) return null;

    final name = parts[0];
    final domain = parts[1];
    final url = Uri.https(domain, '/.well-known/nostr.json', {'name': name});

    try {
      final response = await _client.get(url);

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final names = json['names'] as Map<String, dynamic>?;

      if (names == null || !names.containsKey(name)) return null;

      return names[name] as String;
    } catch (e) {
      return null;
    }
  }
}
