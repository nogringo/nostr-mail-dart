import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:nostr_mail/src/services/bridge_resolver.dart';
import 'package:nostr_mail/src/utils/recipient_resolver.dart';
import 'package:test/test.dart';

class _MockHttpClient extends Mock implements http.Client {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  group('BridgeResolver', () {
    late _MockHttpClient mockClient;
    late BridgeResolver resolver;

    setUp(() {
      mockClient = _MockHttpClient();
      resolver = BridgeResolver(client: mockClient);
    });

    test('resolveBridgePubkey returns pubkey for valid response', () async {
      final responseBody = jsonEncode({
        'names': {'_smtp': 'bridge-pubkey-123'},
      });

      when(
        () => mockClient.get(any()),
      ).thenAnswer((_) async => http.Response(responseBody, 200));

      final pubkey = await resolver.resolveBridgePubkey('example.com');

      expect(pubkey, 'bridge-pubkey-123');
      verify(
        () => mockClient.get(
          Uri.https('example.com', '/.well-known/nostr.json', {
            'name': '_smtp',
          }),
        ),
      ).called(1);
    });

    test('resolveBridgePubkey throws for non-200 response', () async {
      when(
        () => mockClient.get(any()),
      ).thenAnswer((_) async => http.Response('Not found', 404));

      expect(
        () => resolver.resolveBridgePubkey('example.com'),
        throwsA(isA<BridgeResolutionException>()),
      );
    });

    test('resolveBridgePubkey throws when _smtp not in response', () async {
      final responseBody = jsonEncode({
        'names': {'other': 'some-pubkey'},
      });

      when(
        () => mockClient.get(any()),
      ).thenAnswer((_) async => http.Response(responseBody, 200));

      expect(
        () => resolver.resolveBridgePubkey('example.com'),
        throwsA(isA<BridgeResolutionException>()),
      );
    });

    test('resolveNip05 returns pubkey for valid identifier', () async {
      final responseBody = jsonEncode({
        'names': {'alice': 'alice-pubkey-456'},
      });

      when(
        () => mockClient.get(any()),
      ).thenAnswer((_) async => http.Response(responseBody, 200));

      final pubkey = await resolver.resolveNip05('alice@example.com');

      expect(pubkey, 'alice-pubkey-456');
      verify(
        () => mockClient.get(
          Uri.https('example.com', '/.well-known/nostr.json', {
            'name': 'alice',
          }),
        ),
      ).called(1);
    });

    test('resolveNip05 returns null for invalid identifier format', () async {
      final result = await resolver.resolveNip05('invalid-no-at-sign');

      expect(result, isNull);
      verifyNever(() => mockClient.get(any()));
    });

    test('resolveNip05 returns null for non-200 response', () async {
      when(
        () => mockClient.get(any()),
      ).thenAnswer((_) async => http.Response('Error', 500));

      final result = await resolver.resolveNip05('user@example.com');

      expect(result, isNull);
    });

    test('resolveNip05 returns null when name not found', () async {
      final responseBody = jsonEncode({
        'names': {'other': 'other-pubkey'},
      });

      when(
        () => mockClient.get(any()),
      ).thenAnswer((_) async => http.Response(responseBody, 200));

      final result = await resolver.resolveNip05('missing@example.com');

      expect(result, isNull);
    });

    test('resolveNip05 returns null on network error', () async {
      when(() => mockClient.get(any())).thenThrow(Exception('Network error'));

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

        final overrideResolver = BridgeResolver(
          nip05Overrides: {
            '_smtp@gmail.com': gmailBridgePubkey,
            'bob@primal.net': primalUserPubkey,
            '_smtp@example.com': exampleBridgePubkey,
          },
        );

        expect(
          await overrideResolver.resolveNip05('_smtp@gmail.com'),
          gmailBridgePubkey,
        );
        expect(
          await overrideResolver.resolveNip05('bob@primal.net'),
          primalUserPubkey,
        );
        expect(
          await overrideResolver.resolveNip05('_smtp@example.com'),
          exampleBridgePubkey,
        );
      },
    );
  });

  group('resolveRecipient', () {
    final keyPair = Bip340.generatePrivateKey();
    final npub = Nip19.encodePubKey(keyPair.publicKey);

    group('raw address', () {
      test('npub@domain', () async {
        final result = await resolveRecipient(to: '$npub@example.com');
        expect(result, keyPair.publicKey);
      });

      test('npub@nostr', () async {
        final result = await resolveRecipient(to: '$npub@nostr');
        expect(result, keyPair.publicKey);
      });

      test('npub', () async {
        final result = await resolveRecipient(to: npub);
        expect(result, keyPair.publicKey);
      });

      test('pubkey', () async {
        final result = await resolveRecipient(to: keyPair.publicKey);
        expect(result, keyPair.publicKey);
      });

      test('nip05', () async {
        final result = await resolveRecipient(to: 'russell@uid.ovh');
        expect(
          result,
          'b22b06b051fd5232966a9344a634d956c3dc33a7f5ecdcad9ed11ddc4120a7f2',
        );
      });
    });

    group('address with name', () {
      test('npub@domain', () async {
        final result = await resolveRecipient(to: 'Bob <$npub@example.com>');
        expect(result, keyPair.publicKey);
      });

      test('npub@nostr', () async {
        final result = await resolveRecipient(to: 'Bob <$npub@nostr>');
        expect(result, keyPair.publicKey);
      });

      test('nip05', () async {
        final result = await resolveRecipient(to: 'Bob <russell@uid.ovh>');
        expect(
          result,
          'b22b06b051fd5232966a9344a634d956c3dc33a7f5ecdcad9ed11ddc4120a7f2',
        );
      });
    });
  });
}
