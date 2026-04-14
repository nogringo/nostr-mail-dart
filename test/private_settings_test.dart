import 'dart:convert';

import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:test/test.dart';

void main() {
  group("Integration", () {
    test("main", () async {
      final ndk = Ndk(
        NdkConfig(
          eventVerifier: Bip340EventVerifier(),
          cache: MemCacheManager(),
        ),
      );

      final keyPair = Bip340.generatePrivateKey();
      final signer = Bip340EventSigner(
        privateKey: keyPair.privateKey,
        publicKey: keyPair.publicKey,
      );
      ndk.accounts.loginExternalSigner(signer: signer);

      final db = await databaseFactoryMemory.openDatabase(
        'test_private_settings_${DateTime.now().millisecondsSinceEpoch}',
      );

      final client = NostrMailClient(ndk: ndk, db: db);

      expect(client.cachedPrivateSettings, isNull);

      await client.updatePrivateSettings(signature: "test");

      expect(client.cachedPrivateSettings!.signature, equals("test"));

      final db2 = await databaseFactoryMemory.openDatabase(
        'test_private_settings_${DateTime.now().millisecondsSinceEpoch}',
      );
      final client2 = NostrMailClient(ndk: ndk, db: db2);

      final settings = await client2.getPrivateSettings();

      expect(
        settings!.sourceEvent!.id,
        equals(client.cachedPrivateSettings!.sourceEvent!.id),
      );
      expect(
        settings.signature,
        equals(client.cachedPrivateSettings!.signature),
      );

      await ndk.destroy();
    });
  });

  group('PrivateSettings model', () {
    test('fromJson parses all fields', () {
      final json = jsonEncode({
        'signature': 'Sent via Nostr',
        'bridges': ['nostr.mail', 'bridge.example.com'],
        'identities': [
          'Alice Real <npub1abc@test.mail>',
          'npub1def@bridge.com',
        ],
      });

      final settings = PrivateSettings.fromJson(json);

      expect(settings.defaultAddress, isNotNull);
      expect(settings.defaultAddress!.personalName, 'Alice Real');
      expect(settings.defaultAddress!.email, 'npub1abc@test.mail');
      expect(settings.signature, 'Sent via Nostr');
      expect(settings.bridges, ['nostr.mail', 'bridge.example.com']);
      expect(settings.identities, isNotNull);
      expect(settings.identities!.length, 2);
      expect(settings.identities![0].personalName, 'Alice Real');
    });

    test('fromJson handles empty/null fields', () {
      final settings = PrivateSettings.fromJson('{}');

      expect(settings.defaultAddress, isNull);
      expect(settings.signature, isNull);
      expect(settings.bridges, isNull);
      expect(settings.identities, isNull);
    });

    test('fromJson handles partial fields', () {
      final json = jsonEncode({'signature': 'Custom signature'});

      final settings = PrivateSettings.fromJson(json);

      expect(settings.defaultAddress, isNull);
      expect(settings.signature, 'Custom signature');
      expect(settings.bridges, isNull);
      expect(settings.identities, isNull);
    });

    test('toJson serializes all fields', () {
      final settings = PrivateSettings(
        signature: 'Sent via Nostr',
        bridges: ['nostr.mail'],
        identities: [
          MailAddress('Alice', 'alice@nostr.mail'),
          MailAddress(null, 'bob@bridge.com'),
        ],
      );

      final json = jsonDecode(settings.toJson()) as Map<String, dynamic>;

      expect(json['signature'], 'Sent via Nostr');
      expect(json['bridges'], ['nostr.mail']);
      expect(json.containsKey('default_address'), isFalse);
      expect(json['identities'], isNotNull);
      expect((json['identities'] as List).length, 2);
    });

    test('toJson omits null fields', () {
      final settings = const PrivateSettings(signature: 'Only signature');

      final json = jsonDecode(settings.toJson()) as Map<String, dynamic>;

      expect(json['signature'], 'Only signature');
      expect(json.containsKey('bridges'), isFalse);
      expect(json.containsKey('identities'), isFalse);
    });

    test('roundtrip preserves data', () {
      final original = PrivateSettings(
        signature: 'My signature',
        bridges: ['a.com', 'b.com'],
        identities: [
          MailAddress('Alice', 'alice@nostr.mail'),
          MailAddress(null, 'bob@bridge.com'),
        ],
      );

      final restored = PrivateSettings.fromJson(original.toJson());

      expect(restored.signature, original.signature);
      expect(restored.bridges, original.bridges);
      expect(
        restored.defaultAddress!.encode(),
        original.defaultAddress!.encode(),
      );
      expect(restored.identities, isNotNull);
      expect(restored.identities!.length, 2);
      expect(restored.identities![0].personalName, 'Alice');
      expect(restored.identities![1].personalName, isNull);
    });

    test('copyWith updates fields', () {
      final original = PrivateSettings(
        signature: 'Old signature',
        bridges: ['old.com'],
      );

      final updated = original.copyWith(signature: 'New signature');

      expect(updated.signature, 'New signature');
      expect(updated.bridges, ['old.com']); // unchanged
      expect(updated.sourceEvent, isNull); // cleared by copyWith
    });

    test('copyWith clears fields', () {
      final original = PrivateSettings(
        signature: 'signature',
        bridges: ['bridge.com'],
        identities: [MailAddress('Alice', 'alice@test.com')],
      );

      final updated = original.copyWith(
        clearSignature: true,
        clearBridges: true,
        clearIdentities: true,
      );

      expect(updated.defaultAddress, isNull);
      expect(updated.signature, isNull);
      expect(updated.bridges, isNull);
      expect(updated.identities, isNull);
    });

    test('copyWith updates identities', () {
      final original = PrivateSettings(
        identities: [MailAddress('Old', 'old@test.com')],
      );

      final updated = original.copyWith(
        identities: [MailAddress('New', 'new@test.com')],
      );

      expect(updated.identities, isNotNull);
      expect(updated.identities!.length, 1);
      expect(updated.identities![0].personalName, 'New');
    });

    test('copyWith clears sourceEvent', () {
      final settings = PrivateSettings(signature: 'test', sourceEvent: null);
      final updated = settings.copyWith(signature: 'updated');
      expect(updated.sourceEvent, isNull);
    });

    test('toString is descriptive', () {
      final settings = PrivateSettings(
        signature: 'test-sig',
        bridges: ['a.com'],
      );

      expect(settings.toString(), contains('test-sig'));
      expect(settings.toString(), contains('a.com'));
    });
  });

  group('PrivateSettings integration', () {
    late Ndk ndk;
    late NostrMailClient client;

    setUp(() async {
      final db = await databaseFactoryMemory.openDatabase(
        'test_private_settings_${DateTime.now().millisecondsSinceEpoch}',
      );
      ndk = Ndk(
        NdkConfig(
          bootstrapRelays: ['wss://nostr-01.uid.ovh'],
          eventVerifier: Bip340EventVerifier(),
          cache: MemCacheManager(),
        ),
      );

      final keyPair = Bip340.generatePrivateKey();
      ndk.accounts.loginPrivateKey(
        pubkey: keyPair.publicKey,
        privkey: keyPair.privateKey!,
      );

      client = NostrMailClient(ndk: ndk, db: db);
    });

    tearDown(() async {
      await ndk.destroy();
    });

    test('cachedPrivateSettings is null before first fetch', () {
      expect(client.cachedPrivateSettings, isNull);
    });

    test('setPrivateSettings throws without signing capability', () async {
      final readOnlyKeys = Bip340.generatePrivateKey();
      ndk.accounts.loginPublicKey(pubkey: readOnlyKeys.publicKey);

      expect(
        () => client.setPrivateSettings(const PrivateSettings()),
        throwsA(isA<NostrMailException>()),
      );
    });

    test('getPrivateSettings throws without signing capability', () async {
      final readOnlyKeys = Bip340.generatePrivateKey();
      ndk.accounts.loginPublicKey(pubkey: readOnlyKeys.publicKey);

      expect(
        () => client.getPrivateSettings(),
        throwsA(isA<NostrMailException>()),
      );
    });

    test(
      'updatePrivateSettings with signature then get returns same value',
      () async {
        await client.updatePrivateSettings(signature: 'Synced signature');

        final settings = await client.getPrivateSettings();

        expect(settings, isNotNull);
        expect(settings!.signature, 'Synced signature');
        expect(client.cachedPrivateSettings, isNotNull);
        expect(client.cachedPrivateSettings!.signature, 'Synced signature');
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'updatePrivateSettings updates existing signature',
      () async {
        await client.updatePrivateSettings(signature: 'First signature');
        var settings = await client.getPrivateSettings();
        expect(settings!.signature, 'First signature');

        await client.updatePrivateSettings(signature: 'Updated signature');
        settings = await client.getPrivateSettings();
        expect(settings!.signature, 'Updated signature');
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'updatePrivateSettings with bridges',
      () async {
        final bridges = ['nostr.mail', 'bridge.example.com'];
        await client.updatePrivateSettings(bridges: bridges);

        final settings = await client.getPrivateSettings();

        expect(settings, isNotNull);
        expect(settings!.bridges, bridges);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'updatePrivateSettings with identities sets defaultAddress',
      () async {
        final identities = [
          MailAddress('Alice', 'alice@nostr.mail'),
          MailAddress(null, 'bob@bridge.com'),
        ];
        await client.updatePrivateSettings(identities: identities);

        final settings = await client.getPrivateSettings();

        expect(settings, isNotNull);
        expect(settings!.defaultAddress, isNotNull);
        expect(settings.defaultAddress!.personalName, 'Alice');
        expect(settings.identities!.length, 2);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'clearAll resets private settings cache',
      () async {
        await client.updatePrivateSettings(signature: 'Test signature');
        await client.getPrivateSettings();
        expect(client.cachedPrivateSettings, isNotNull);

        await client.clearAll();

        expect(client.cachedPrivateSettings, isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'updatePrivateSettings with clearSignature',
      () async {
        await client.updatePrivateSettings(signature: 'To be cleared');
        await client.getPrivateSettings();
        expect(client.cachedPrivateSettings!.signature, 'To be cleared');

        await client.updatePrivateSettings(clearSignature: true);

        final settings = await client.getPrivateSettings();
        expect(settings, isNotNull);
        expect(settings!.signature, isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'sourceEvent is populated on getPrivateSettings',
      () async {
        await client.updatePrivateSettings(signature: 'test');
        final settings = await client.getPrivateSettings();

        expect(settings, isNotNull);
        expect(settings!.sourceEvent, isNotNull);
        expect(settings.sourceEvent!.kind, appSettingsKind);
        final dTag = settings.sourceEvent!.tags.firstWhere(
          (t) => t.isNotEmpty && t[0] == 'd',
          orElse: () => [],
        );
        expect(dTag, isNotEmpty);
        expect(dTag[1], privateSettingsDTag);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'updatePrivateSettings with identities',
      () async {
        final identities = [
          MailAddress('Alice Real', 'alice@nostr.mail'),
          MailAddress(null, 'bob@bridge.com'),
        ];
        await client.updatePrivateSettings(identities: identities);

        final settings = await client.getPrivateSettings();

        expect(settings, isNotNull);
        expect(settings!.identities, isNotNull);
        expect(settings.identities!.length, 2);
        expect(settings.identities![0].personalName, 'Alice Real');
        expect(settings.identities![1].personalName, isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'updatePrivateSettings with clearIdentities',
      () async {
        await client.updatePrivateSettings(
          identities: [MailAddress('Test', 'test@test.com')],
        );
        await client.getPrivateSettings();
        expect(client.cachedPrivateSettings!.identities, isNotNull);

        await client.updatePrivateSettings(clearIdentities: true);

        final settings = await client.getPrivateSettings();
        expect(settings, isNotNull);
        expect(settings!.identities, isNull);
        expect(settings.defaultAddress, isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
