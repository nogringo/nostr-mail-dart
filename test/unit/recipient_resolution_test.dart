import 'package:ndk/entities.dart' as ndk_entities;
import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:nostr_mail/src/services/bridge_resolver.dart';
import 'package:nostr_mail/src/utils/recipient_resolver.dart';
import 'package:test/test.dart';

Ndk _newNdk() => Ndk(
  NdkConfig(
    eventVerifier: Bip340EventVerifier(),
    cache: MemCacheManager(),
    bootstrapRelays: [],
  ),
);

ndk_entities.Nip05Found _nip05Found(String pubkey, String nip05) {
  return ndk_entities.Nip05Found(
    ndk_entities.Nip05(pubKey: pubkey, nip05: nip05),
  );
}

void main() {
  group('BridgeResolver', () {
    late List<String> resolvedIdentifiers;

    BridgeResolver resolverReturning(ndk_entities.Nip05ResolveResult result) {
      return BridgeResolver.withNip05Resolver(
        resolveNip05: (identifier) async {
          resolvedIdentifiers.add(identifier);
          return result;
        },
      );
    }

    setUp(() {
      resolvedIdentifiers = [];
    });

    test('resolveBridgePubkey returns pubkey for valid response', () async {
      final resolver = resolverReturning(
        _nip05Found('bridge-pubkey-123', '_smtp@example.com'),
      );

      final pubkey = await resolver.resolveBridgePubkey('example.com');

      expect(pubkey, 'bridge-pubkey-123');
      expect(resolvedIdentifiers, ['_smtp@example.com']);
    });

    test('resolveBridgePubkey throws when bridge is not found', () async {
      final resolver = resolverReturning(const ndk_entities.Nip05NotFound());

      expect(
        () => resolver.resolveBridgePubkey('example.com'),
        throwsA(isA<BridgeResolutionException>()),
      );
    });

    test(
      'resolveBridgePubkey throws BridgeResolutionException on fetch error',
      () async {
        final resolver = resolverReturning(
          ndk_entities.Nip05ResolveNetworkError(Exception('socket closed')),
        );

        await expectLater(
          () => resolver.resolveBridgePubkey('example.com'),
          throwsA(isA<BridgeResolutionException>()),
        );
      },
    );

    test('resolveBridgePubkey throws for invalid NIP-05 response', () async {
      final resolver = resolverReturning(
        ndk_entities.Nip05ResolveInvalidResponse(Exception('bad json')),
      );

      expect(
        () => resolver.resolveBridgePubkey('example.com'),
        throwsA(isA<BridgeResolutionException>()),
      );
    });

    test('resolveNip05 returns pubkey for valid identifier', () async {
      final resolver = resolverReturning(
        _nip05Found('alice-pubkey-456', 'alice@example.com'),
      );

      final pubkey = await resolver.resolveNip05('alice@example.com');

      expect(pubkey, 'alice-pubkey-456');
      expect(resolvedIdentifiers, ['alice@example.com']);
    });

    test('resolveNip05 returns null for invalid identifier format', () async {
      final resolver = resolverReturning(
        _nip05Found('unused-pubkey', 'unused@example.com'),
      );

      final result = await resolver.resolveNip05('invalid-no-at-sign');

      expect(result, isNull);
      expect(resolvedIdentifiers, isEmpty);
    });

    test('resolveNip05 returns null when identifier is not found', () async {
      final resolver = resolverReturning(const ndk_entities.Nip05NotFound());

      final result = await resolver.resolveNip05('user@example.com');

      expect(result, isNull);
    });

    test('resolveNip05 returns null for invalid NIP-05 response', () async {
      final resolver = resolverReturning(
        ndk_entities.Nip05ResolveInvalidResponse(Exception('bad json')),
      );

      final result = await resolver.resolveNip05('missing@example.com');

      expect(result, isNull);
    });

    test('resolveNip05 returns null on fetch error', () async {
      final resolver = resolverReturning(
        ndk_entities.Nip05ResolveNetworkError(Exception('CORS blocked')),
      );

      final result = await resolver.resolveNip05('user@example.com');

      expect(result, isNull);
    });

    test(
      'nip05Overrides short-circuit network calls for bridges and users',
      () async {
        final gmailBridgePubkey =
            '1111111111111111111111111111111111111111111111111111111111111111';
        final primalUserPubkey =
            '2222222222222222222222222222222222222222222222222222222222222222';
        final exampleBridgePubkey =
            '3333333333333333333333333333333333333333333333333333333333333333';

        final resolver = BridgeResolver.withNip05Resolver(
          resolveNip05: (identifier) async {
            resolvedIdentifiers.add(identifier);
            throw StateError('override should not call NDK resolver');
          },
          nip05Overrides: {
            '_smtp@gmail.com': gmailBridgePubkey,
            'bob@primal.net': primalUserPubkey,
            '_smtp@example.com': exampleBridgePubkey,
          },
        );

        expect(
          await resolver.resolveNip05('_smtp@gmail.com'),
          gmailBridgePubkey,
        );
        expect(await resolver.resolveNip05('bob@primal.net'), primalUserPubkey);
        expect(
          await resolver.resolveNip05('_smtp@example.com'),
          exampleBridgePubkey,
        );
        expect(resolvedIdentifiers, isEmpty);
      },
    );
  });

  group('resolveRecipient', () {
    final keyPair = Bip340.generatePrivateKey();
    final npub = Nip19.encodePubKey(keyPair.publicKey);
    final nip05Pubkey =
        'b22b06b051fd5232966a9344a634d956c3dc33a7f5ecdcad9ed11ddc4120a7f2';
    late Ndk ndk;

    setUp(() {
      ndk = _newNdk();
      addTearDown(ndk.destroy);
    });

    group('raw address', () {
      test('npub@domain', () async {
        final result = await resolveRecipient(
          to: '$npub@example.com',
          ndk: ndk,
        );
        expect(result, keyPair.publicKey);
      });

      test('npub@nostr', () async {
        final result = await resolveRecipient(to: '$npub@nostr', ndk: ndk);
        expect(result, keyPair.publicKey);
      });

      test('npub', () async {
        final result = await resolveRecipient(to: npub, ndk: ndk);
        expect(result, keyPair.publicKey);
      });

      test('pubkey', () async {
        final result = await resolveRecipient(to: keyPair.publicKey, ndk: ndk);
        expect(result, keyPair.publicKey);
      });

      test('nip05', () async {
        final result = await resolveRecipient(
          to: 'russell@uid.ovh',
          ndk: ndk,
          nip05Overrides: {'russell@uid.ovh': nip05Pubkey},
        );
        expect(result, nip05Pubkey);
      });
    });

    group('address with name', () {
      test('npub@domain', () async {
        final result = await resolveRecipient(
          to: 'Bob <$npub@example.com>',
          ndk: ndk,
        );
        expect(result, keyPair.publicKey);
      });

      test('npub@nostr', () async {
        final result = await resolveRecipient(
          to: 'Bob <$npub@nostr>',
          ndk: ndk,
        );
        expect(result, keyPair.publicKey);
      });

      test('nip05', () async {
        final result = await resolveRecipient(
          to: 'Bob <russell@uid.ovh>',
          ndk: ndk,
          nip05Overrides: {'russell@uid.ovh': nip05Pubkey},
        );
        expect(result, nip05Pubkey);
      });
    });
  });
}
