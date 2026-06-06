import 'package:ndk/entities.dart' as ndk_entities;
import 'package:ndk/ndk.dart';

import '../exceptions.dart';

typedef NdkNip05Resolver =
    Future<ndk_entities.Nip05ResolveResult> Function(String identifier);

class BridgeResolver {
  final NdkNip05Resolver _resolveNip05;
  final Map<String, String>? nip05Overrides;

  BridgeResolver({required Ndk ndk, this.nip05Overrides})
    : _resolveNip05 = ndk.nip05.resolve;

  BridgeResolver.withNip05Resolver({
    required NdkNip05Resolver resolveNip05,
    this.nip05Overrides,
  }) : _resolveNip05 = resolveNip05;

  /// Resolve bridge pubkey via NIP-05 lookup for _smtp@domain
  Future<String> resolveBridgePubkey(String domain) async {
    final nip05 = '_smtp@$domain';
    if (nip05Overrides != null && nip05Overrides!.containsKey(nip05)) {
      return nip05Overrides![nip05]!;
    }

    final result = await _resolveNip05(nip05);
    return switch (result) {
      ndk_entities.Nip05Found(:final data) => data.pubKey,
      ndk_entities.Nip05ResolveNetworkError() ||
      ndk_entities.Nip05NotFound() ||
      ndk_entities.Nip05ResolveInvalidResponse() =>
        throw BridgeResolutionException(domain),
    };
  }

  /// Resolve any NIP-05 identifier (user@domain) to pubkey.
  ///
  /// Returns null when the name is not registered or cannot be resolved by
  /// NDK, for example because the server cannot be reached or is blocked by
  /// browser transport policy such as CORS.
  Future<String?> resolveNip05(String identifier) async {
    if (nip05Overrides != null && nip05Overrides!.containsKey(identifier)) {
      return nip05Overrides![identifier]!;
    }

    final parts = identifier.split('@');
    if (parts.length != 2) return null;

    final result = await _resolveNip05(identifier);
    return switch (result) {
      ndk_entities.Nip05Found(:final data) => data.pubKey,
      ndk_entities.Nip05ResolveNetworkError() ||
      ndk_entities.Nip05NotFound() ||
      ndk_entities.Nip05ResolveInvalidResponse() => null,
    };
  }
}
