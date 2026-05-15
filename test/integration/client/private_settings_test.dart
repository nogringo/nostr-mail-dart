import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:test/test.dart';

import '../../mocks/mock_relay.dart';

void main() {
  group('PrivateSettings end-to-end', () {
    test(
      'persists across NostrMailClient instances backed by the relay',
      () async {
        final relay = MockRelay(name: 'relay', explicitPort: 19016);
        await relay.startServer();
        addTearDown(() async => await relay.stopServer());

        final ndk = Ndk(
          NdkConfig(
            eventVerifier: Bip340EventVerifier(),
            cache: MemCacheManager(),
            bootstrapRelays: [relay.url],
          ),
        );
        addTearDown(() async => await ndk.destroy());

        final keyPair = Bip340.generatePrivateKey();
        final signer = Bip340EventSigner(
          privateKey: keyPair.privateKey,
          publicKey: keyPair.publicKey,
        );
        ndk.accounts.loginExternalSigner(signer: signer);

        final db = await databaseFactoryMemory.openDatabase(
          'test_private_settings_${DateTime.now().microsecondsSinceEpoch}',
        );

        final clientA = await NostrMailClient.create(
          ndk: ndk,
          db: db,
          defaultDmRelays: [relay.url],
        );

        expect(clientA.cachedPrivateSettings, isNull);

        await clientA.updatePrivateSettings(signature: 'test');

        expect(clientA.cachedPrivateSettings!.signature, 'test');

        // Fresh DB, same relay/account: settings should be re-fetched.
        final db2 = await databaseFactoryMemory.openDatabase(
          'test_private_settings_${DateTime.now().microsecondsSinceEpoch}_b',
        );
        final clientB = await NostrMailClient.create(
          ndk: ndk,
          db: db2,
          defaultDmRelays: [relay.url],
        );

        final settings = await clientB.getPrivateSettings();

        expect(
          settings!.sourceEvent!.id,
          clientA.cachedPrivateSettings!.sourceEvent!.id,
        );
        expect(settings.signature, clientA.cachedPrivateSettings!.signature);
      },
    );
  });

  group('NostrMailClient.privateSettings', () {
    late Ndk ndk;
    late NostrMailClient client;
    late MockRelay relay;

    setUp(() async {
      relay = MockRelay(name: 'relay', explicitPort: 19012);
      await relay.startServer();

      final db = await databaseFactoryMemory.openDatabase(
        'test_private_settings_${DateTime.now().microsecondsSinceEpoch}',
      );
      ndk = Ndk(
        NdkConfig(
          bootstrapRelays: [relay.url],
          eventVerifier: Bip340EventVerifier(),
          cache: MemCacheManager(),
        ),
      );

      final keyPair = Bip340.generatePrivateKey();
      ndk.accounts.loginPrivateKey(
        pubkey: keyPair.publicKey,
        privkey: keyPair.privateKey!,
      );

      client = await NostrMailClient.create(
        ndk: ndk,
        db: db,
        defaultDmRelays: [relay.url],
      );
    });

    tearDown(() async {
      await ndk.destroy();
      await relay.stopServer();
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
      'updatePrivateSettings then getPrivateSettings returns the same value',
      () async {
        await client.updatePrivateSettings(signature: 'Synced signature');

        final settings = await client.getPrivateSettings();

        expect(settings, isNotNull);
        expect(settings!.signature, 'Synced signature');
        expect(client.cachedPrivateSettings!.signature, 'Synced signature');
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'updatePrivateSettings updates an existing signature',
      () async {
        await client.updatePrivateSettings(signature: 'First signature');
        var settings = await client.getPrivateSettings();
        expect(settings!.signature, 'First signature');

        // Need a strictly greater createdAt (1 s resolution).
        await Future.delayed(const Duration(seconds: 1));

        await client.updatePrivateSettings(signature: 'Updated signature');
        settings = await client.getPrivateSettings();
        expect(settings!.signature, 'Updated signature');
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'updatePrivateSettings persists bridges',
      () async {
        final bridges = ['nostr.mail', 'bridge.example.com'];
        await client.updatePrivateSettings(bridges: bridges);

        final settings = await client.getPrivateSettings();

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

        expect(settings!.defaultAddress!.personalName, 'Alice');
        expect(settings.identities!.length, 2);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'clearAll resets the private settings cache',
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
      'updatePrivateSettings with clearSignature drops the signature',
      () async {
        await client.updatePrivateSettings(signature: 'To be cleared');
        await client.getPrivateSettings();
        expect(client.cachedPrivateSettings!.signature, 'To be cleared');

        await Future.delayed(const Duration(seconds: 1));

        await client.updatePrivateSettings(clearSignature: true);

        final settings = await client.getPrivateSettings();
        expect(settings!.signature, isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'sourceEvent is populated on getPrivateSettings',
      () async {
        await client.updatePrivateSettings(signature: 'test');
        final settings = await client.getPrivateSettings();

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
      'updatePrivateSettings persists identities',
      () async {
        final identities = [
          MailAddress('Alice Real', 'alice@nostr.mail'),
          MailAddress(null, 'bob@bridge.com'),
        ];
        await client.updatePrivateSettings(identities: identities);

        final settings = await client.getPrivateSettings();

        expect(settings!.identities, hasLength(2));
        expect(settings.identities![0].personalName, 'Alice Real');
        expect(settings.identities![1].personalName, isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'updatePrivateSettings with clearIdentities drops identities',
      () async {
        await client.updatePrivateSettings(
          identities: [MailAddress('Test', 'test@test.com')],
        );
        await client.getPrivateSettings();
        expect(client.cachedPrivateSettings!.identities, isNotNull);

        await Future.delayed(const Duration(seconds: 1));

        await client.updatePrivateSettings(clearIdentities: true);

        final settings = await client.getPrivateSettings();
        expect(settings!.identities, isNull);
        expect(settings.defaultAddress, isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
