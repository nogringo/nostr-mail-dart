import 'package:blossom_cache/blossom_cache.dart';
import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:test/test.dart';

import '../../helpers/test_blossom_cache.dart';
import '../../helpers/test_database.dart';
import '../../mocks/mock_relay.dart';
import '../../helpers/test_sync_engine.dart';

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
          database: testDatabase(),
          db: db,
          syncEngine: testSyncEngine(ndk, db),
          blossomCache: await openTestBlossomCache('private_settings_a'),
          defaultDmRelays: [relay.url],
        );
        addTearDown(() async => await clientA.dispose());

        expect(clientA.cachedPrivateSettings(), isNull);

        await clientA.setPrivateSettings(
          const PrivateSettings(signature: 'test'),
        );

        expect(clientA.cachedPrivateSettings()!.signature, 'test');

        // Fresh DB, same relay/account: settings should be re-fetched.
        final db2 = await databaseFactoryMemory.openDatabase(
          'test_private_settings_${DateTime.now().microsecondsSinceEpoch}_b',
        );
        final clientB = await NostrMailClient.create(
          ndk: ndk,
          database: testDatabase(),
          db: db2,
          syncEngine: testSyncEngine(ndk, db2),
          blossomCache: await openTestBlossomCache('private_settings_b'),
          defaultDmRelays: [relay.url],
        );
        addTearDown(() async => await clientB.dispose());

        final settings = await clientB.fetchPrivateSettings();

        expect(
          settings!.sourceEvent!.id,
          clientA.cachedPrivateSettings()!.sourceEvent!.id,
        );
        expect(settings.signature, clientA.cachedPrivateSettings()!.signature);
      },
    );
  });

  group('NostrMailClient.privateSettings', () {
    late Ndk ndk;
    late NostrMailClient client;
    late MockRelay relay;
    late NostrMailDatabase database;
    late Database db;
    late BlossomCache blossomCache;

    setUp(() async {
      relay = MockRelay(name: 'relay', explicitPort: 19012);
      await relay.startServer();

      database = testDatabase();
      db = await databaseFactoryMemory.openDatabase(
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

      blossomCache = await openTestBlossomCache('private_settings_c');
      client = await NostrMailClient.create(
        ndk: ndk,
        database: database,
        db: db,
        syncEngine: testSyncEngine(ndk, db),
        blossomCache: blossomCache,
        defaultDmRelays: [relay.url],
      );
    });

    tearDown(() async {
      await client.dispose();
      await ndk.destroy();
      await relay.stopServer();
    });

    test('cachedPrivateSettings is null before first local read', () {
      expect(client.cachedPrivateSettings(), isNull);
    });

    test(
      'NostrMailClient.create primes cachedPrivateSettings from local DB',
      () async {
        await client.updatePrivateSettings(signature: 'primed signature');
        expect(client.cachedPrivateSettings()!.signature, 'primed signature');

        // Reopen a fresh client backed by the SAME database. The signature is
        // persisted in the SettingsRepository, so the new client must expose
        // it through the sync getter immediately after create() returns,
        // without anyone calling getLocalPrivateSettings() first. This mirrors
        // the post-login flow where the app reads the cached signature right after initClient().
        final reopened = await NostrMailClient.create(
          ndk: ndk,
          database: database,
          db: db,
          syncEngine: testSyncEngine(ndk, db),
          blossomCache: blossomCache,
          defaultDmRelays: [relay.url],
        );

        expect(reopened.cachedPrivateSettings(), isNotNull);
        expect(reopened.cachedPrivateSettings()!.signature, 'primed signature');
      },
    );

    test('setPrivateSettings throws without signing capability', () async {
      final readOnlyKeys = Bip340.generatePrivateKey();
      ndk.accounts.loginPublicKey(pubkey: readOnlyKeys.publicKey);

      expect(
        () => client.setPrivateSettings(const PrivateSettings()),
        throwsA(isA<NostrMailException>()),
      );
    });

    test('fetchPrivateSettings throws without signing capability', () async {
      final readOnlyKeys = Bip340.generatePrivateKey();
      ndk.accounts.loginPublicKey(pubkey: readOnlyKeys.publicKey);

      expect(
        () => client.fetchPrivateSettings(),
        throwsA(isA<NostrMailException>()),
      );
    });

    test('updatePrivateSettings throws without signing capability', () async {
      final readOnlyKeys = Bip340.generatePrivateKey();
      ndk.accounts.loginPublicKey(pubkey: readOnlyKeys.publicKey);

      expect(
        () => client.updatePrivateSettings(signature: 'Local signature'),
        throwsA(isA<NostrMailException>()),
      );
    });

    test(
      'updatePrivateSettings updates the local cache and enqueues sync',
      () async {
        await client.updatePrivateSettings(signature: 'Synced signature');

        final settings = await client.getLocalPrivateSettings();

        expect(settings, isNotNull);
        expect(settings!.signature, 'Synced signature');
        expect(client.cachedPrivateSettings()!.signature, 'Synced signature');
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test('updatePrivateSettings updates an existing signature', () async {
      await client.updatePrivateSettings(signature: 'First signature');
      var settings = await client.getLocalPrivateSettings();
      expect(settings!.signature, 'First signature');

      await client.updatePrivateSettings(signature: 'Updated signature');
      settings = await client.getLocalPrivateSettings();
      expect(settings!.signature, 'Updated signature');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('updatePrivateSettings persists bridges', () async {
      final bridges = ['nostr.mail', 'bridge.example.com'];
      await client.updatePrivateSettings(bridges: bridges);

      final settings = await client.getLocalPrivateSettings();

      expect(settings!.bridges, bridges);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('updatePrivateSettings with identities sets defaultAddress', () async {
      final identities = [
        MailAddress('Alice', 'alice@nostr.mail'),
        MailAddress(null, 'bob@bridge.com'),
      ];
      await client.updatePrivateSettings(identities: identities);

      final settings = await client.getLocalPrivateSettings();

      expect(settings!.defaultAddress!.personalName, 'Alice');
      expect(settings.identities!.length, 2);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('clearAll resets the private settings cache', () async {
      await client.updatePrivateSettings(signature: 'Test signature');
      await client.getLocalPrivateSettings();
      expect(client.cachedPrivateSettings(), isNotNull);

      await client.clearAll();

      expect(client.cachedPrivateSettings(), isNull);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test(
      'updatePrivateSettings with clearSignature drops the signature',
      () async {
        await client.updatePrivateSettings(signature: 'To be cleared');
        expect(client.cachedPrivateSettings()!.signature, 'To be cleared');

        await client.updatePrivateSettings(clearSignature: true);

        final settings = await client.getLocalPrivateSettings();
        expect(settings!.signature, isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test('sourceEvent is populated on fetchPrivateSettings', () async {
      await client.setPrivateSettings(const PrivateSettings(signature: 'test'));
      final settings = await client.fetchPrivateSettings();

      expect(settings!.sourceEvent, isNotNull);
      expect(settings.sourceEvent!.kind, appSettingsKind);
      final dTag = settings.sourceEvent!.tags.firstWhere(
        (t) => t.isNotEmpty && t[0] == 'd',
        orElse: () => [],
      );
      expect(dTag, isNotEmpty);
      expect(dTag[1], privateSettingsDTag);
    }, timeout: const Timeout(Duration(seconds: 30)));

    group('getPrivateSettings', () {
      Future<NostrMailClient> freshClient({List<String>? dmRelays}) async {
        final freshDb = await databaseFactoryMemory.openDatabase(
          'test_private_settings_${DateTime.now().microsecondsSinceEpoch}_d',
        );
        final fresh = await NostrMailClient.create(
          ndk: ndk,
          database: testDatabase(),
          db: freshDb,
          syncEngine: testSyncEngine(ndk, freshDb),
          blossomCache: blossomCache,
          defaultDmRelays: dmRelays ?? [relay.url],
        );
        addTearDown(fresh.dispose);
        return fresh;
      }

      test('emits the local value then the relay copy', () async {
        await client.setPrivateSettings(
          const PrivateSettings(signature: 'test'),
        );

        final values = await client.getPrivateSettings().stream.toList();

        expect(values.map((v) => v.origin), [
          DataOrigin.cache,
          DataOrigin.relays,
        ]);
        expect(values.map((v) => v.value!.signature), ['test', 'test']);
        expect(
          values.last.value!.sourceEvent!.id,
          client.cachedPrivateSettings()!.sourceEvent!.id,
        );
      }, timeout: const Timeout(Duration(seconds: 30)));

      test('emits null from cache then the relay copy', () async {
        await client.setPrivateSettings(
          const PrivateSettings(signature: 'remote'),
        );
        final fresh = await freshClient();

        final response = fresh.getPrivateSettings();
        final values = await response.stream.toList();

        expect(values.first.value, isNull);
        expect(values.first.origin, DataOrigin.cache);
        expect(values.last.value!.signature, 'remote');
        expect(values.last.origin, DataOrigin.relays);

        final last = await response.future;
        expect(last.origin, DataOrigin.relays);
        expect(fresh.cachedPrivateSettings()!.signature, 'remote');
      }, timeout: const Timeout(Duration(seconds: 30)));

      test('confirms absence when the relay holds nothing', () async {
        final values = await client.getPrivateSettings().stream.toList();

        expect(values.map((v) => (v.value, v.origin)), [
          (null, DataOrigin.cache),
          (null, DataOrigin.relays),
        ]);
      }, timeout: const Timeout(Duration(seconds: 30)));

      test('fails when no relay answers', () async {
        final fresh = await freshClient(dmRelays: ['ws://localhost:19099']);

        final response = fresh.getPrivateSettings(
          timeout: const Duration(seconds: 2),
        );

        await expectLater(response.future, throwsA(isA<NostrMailException>()));
      }, timeout: const Timeout(Duration(seconds: 30)));

      test('reads and writes another account known to ndk', () async {
        final loggedPubkey = ndk.accounts.getPublicKey()!;
        final other = Bip340.generatePrivateKey();
        ndk.accounts.addAccount(
          pubkey: other.publicKey,
          type: AccountType.privateKey,
          signer: Bip340EventSigner(
            privateKey: other.privateKey,
            publicKey: other.publicKey,
          ),
        );
        await client.setPrivateSettings(
          const PrivateSettings(signature: 'other'),
          pubkey: other.publicKey,
        );
        await client.updatePrivateSettings(
          bridges: ['bridge.example.com'],
          pubkey: other.publicKey,
        );

        expect(client.cachedPrivateSettings(), isNull);
        expect(
          client.cachedPrivateSettings(pubkey: other.publicKey)!.signature,
          'other',
        );

        final last = await client
            .getPrivateSettings(pubkey: other.publicKey)
            .future;
        expect(last.origin, DataOrigin.relays);
        expect(last.value!.signature, 'other');
        expect(last.value!.bridges, ['bridge.example.com']);

        final fetched = await client.fetchPrivateSettings(
          pubkey: other.publicKey,
        );
        expect(fetched!.sourceEvent!.pubKey, other.publicKey);
        expect(ndk.accounts.getPublicKey(), loggedPubkey);
      }, timeout: const Timeout(Duration(seconds: 30)));

      test('throws for a pubkey unknown to ndk', () {
        expect(
          () => client.getPrivateSettings(
            pubkey: Bip340.generatePrivateKey().publicKey,
          ),
          throwsA(isA<NostrMailException>()),
        );
      });

      test('throws without signing capability', () {
        final readOnlyKeys = Bip340.generatePrivateKey();
        ndk.accounts.loginPublicKey(pubkey: readOnlyKeys.publicKey);

        expect(
          () => client.getPrivateSettings(),
          throwsA(isA<NostrMailException>()),
        );
      });
    });

    test('updatePrivateSettings persists identities', () async {
      final identities = [
        MailAddress('Alice Real', 'alice@nostr.mail'),
        MailAddress(null, 'bob@bridge.com'),
      ];
      await client.updatePrivateSettings(identities: identities);

      final settings = await client.getLocalPrivateSettings();

      expect(settings!.identities, hasLength(2));
      expect(settings.identities![0].personalName, 'Alice Real');
      expect(settings.identities![1].personalName, isNull);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test(
      'updatePrivateSettings with clearIdentities drops identities',
      () async {
        await client.updatePrivateSettings(
          identities: [MailAddress('Test', 'test@test.com')],
        );
        expect(client.cachedPrivateSettings()!.identities, isNotNull);

        await client.updatePrivateSettings(clearIdentities: true);

        final settings = await client.getLocalPrivateSettings();
        expect(settings!.identities, isNull);
        expect(settings.defaultAddress, isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
