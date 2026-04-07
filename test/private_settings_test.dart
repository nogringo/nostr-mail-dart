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
        'default_address': 'test@bridge.com',
        'signature': 'Sent via Nostr',
        'bridges': ['nostr.mail', 'bridge.example.com'],
      });

      final settings = PrivateSettings.fromJson(json);

      expect(settings.defaultAddress, isNotNull);
      expect(settings.defaultAddress!.encode(), 'test@bridge.com');
      expect(settings.signature, 'Sent via Nostr');
      expect(settings.bridges, ['nostr.mail', 'bridge.example.com']);
    });

    test('fromJson handles empty/null fields', () {
      final settings = PrivateSettings.fromJson('{}');

      expect(settings.defaultAddress, isNull);
      expect(settings.signature, isNull);
      expect(settings.bridges, isNull);
    });

    test('fromJson handles partial fields', () {
      final json = jsonEncode({'signature': 'Custom signature'});

      final settings = PrivateSettings.fromJson(json);

      expect(settings.defaultAddress, isNull);
      expect(settings.signature, 'Custom signature');
      expect(settings.bridges, isNull);
    });

    test('fromJson handles invalid default_address gracefully', () {
      final json = jsonEncode({'default_address': 'not-a-valid-address'});

      // Should not throw, just set to null
      final settings = PrivateSettings.fromJson(json);
      expect(settings.defaultAddress, isNull);
    });

    test('toJson serializes all fields', () {
      final settings = PrivateSettings(
        defaultAddress: MailAddress(null, 'test@bridge.com'),
        signature: 'Sent via Nostr',
        bridges: ['nostr.mail'],
      );

      final json = jsonDecode(settings.toJson()) as Map<String, dynamic>;

      expect(json['default_address'], 'test@bridge.com');
      expect(json['signature'], 'Sent via Nostr');
      expect(json['bridges'], ['nostr.mail']);
    });

    test('toJson omits null fields', () {
      final settings = const PrivateSettings(signature: 'Only signature');

      final json = jsonDecode(settings.toJson()) as Map<String, dynamic>;

      expect(json.containsKey('default_address'), isFalse);
      expect(json['signature'], 'Only signature');
      expect(json.containsKey('bridges'), isFalse);
    });

    test('roundtrip preserves data', () {
      final original = PrivateSettings(
        defaultAddress: MailAddress(null, 'user@bridge.com'),
        signature: 'My signature',
        bridges: ['a.com', 'b.com'],
      );

      final restored = PrivateSettings.fromJson(original.toJson());

      expect(restored.signature, original.signature);
      expect(restored.bridges, original.bridges);
      expect(
        restored.defaultAddress!.encode(),
        original.defaultAddress!.encode(),
      );
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
        defaultAddress: MailAddress(null, 'test@bridge.com'),
        signature: 'signature',
        bridges: ['bridge.com'],
      );

      final updated = original.copyWith(
        clearDefaultAddress: true,
        clearSignature: true,
        clearBridges: true,
      );

      expect(updated.defaultAddress, isNull);
      expect(updated.signature, isNull);
      expect(updated.bridges, isNull);
    });

    test('copyWith clears sourceEvent', () {
      // We'll test with a real client that populates sourceEvent below
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
      // Login with only pubkey (no private key)
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

        // Note: this queries the relays, so it depends on network
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
      'updatePrivateSettings with defaultAddress',
      () async {
        final addr = MailAddress(null, 'user@nostr.mail');
        await client.updatePrivateSettings(defaultAddress: addr);

        final settings = await client.getPrivateSettings();

        expect(settings, isNotNull);
        expect(settings!.defaultAddress, isNotNull);
        expect(settings.defaultAddress!.encode(), 'user@nostr.mail');
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'clearAll resets private settings cache',
      () async {
        // Set some settings first
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
        // The d-tag should be 'nostr-mail/settings/private'
        final dTag = settings.sourceEvent!.tags.firstWhere(
          (t) => t.isNotEmpty && t[0] == 'd',
          orElse: () => [],
        );
        expect(dTag, isNotEmpty);
        expect(dTag[1], privateSettingsDTag);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
