import 'package:blossom_cache/blossom_cache.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:idb_shim/idb_client_memory.dart' hide Database;
import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:ndk/shared/nips/nip01/key_pair.dart';
import 'package:nostr_mail/src/client.dart';
import 'package:nostr_mail/src/storage/database.dart';
import 'package:sembast/sembast_memory.dart' hide Filter;
import 'package:sync_engine_shim_for_ndk/sync_engine_shim_for_ndk.dart';

import 'publish_relay_lists.dart';

class TestUser {
  String id;
  List<String>? defaultDmRelays;

  /// [defaultDmRelays] when null.
  List<String>? defaultNip65Relays;
  List<String>? defaultBlossomServers;
  Map<String, String>? nip05Overrides;
  String? schedulerDvm;
  List<String>? schedulerDvmReadRelays;

  /// Whether [create] publishes the account's relay lists on the default
  /// relays, as the app does for every account it creates.
  bool publishesRelayLists;

  /// Another device of the same account when set.
  final KeyPair? _existingKeyPair;

  late KeyPair keyPair;
  late Ndk ndk;
  late NostrMailDatabase database;
  late Database db;
  late BlossomCache blossomCache;
  late SyncEngine syncEngine;
  late NostrMailClient client;

  TestUser(
    this.id, {
    this.defaultDmRelays,
    this.defaultNip65Relays,
    this.defaultBlossomServers,
    this.nip05Overrides,
    this.schedulerDvm,
    this.schedulerDvmReadRelays,
    this.publishesRelayLists = true,
    KeyPair? keyPair,
  }) : _existingKeyPair = keyPair;

  Future<TestUser> create() async {
    keyPair = _existingKeyPair ?? Bip340.generatePrivateKey();
    final relays = {...?defaultDmRelays, ...?defaultNip65Relays}.toList();
    ndk = Ndk(
      NdkConfig(
        eventVerifier: Bip340EventVerifier(),
        cache: MemCacheManager(),
        bootstrapRelays: relays,
      ),
    );

    ndk.accounts.loginPrivateKey(
      pubkey: keyPair.publicKey,
      privkey: keyPair.privateKey!,
    );
    final dmRelays = defaultDmRelays;
    if (publishesRelayLists && dmRelays != null) {
      await publishRelayLists(
        ndk,
        dmRelays: dmRelays,
        nip65Relays: defaultNip65Relays ?? dmRelays,
      );
    }

    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    database = NostrMailDatabase(NativeDatabase.memory());
    db = await databaseFactoryMemory.openDatabase(id);
    blossomCache = await IdbBlossomCache.open(
      factory: newIdbFactoryMemory(),
      dbName: 'blossom_cache_$id',
    );

    syncEngine = SyncEngine(
      ndk,
      store: SembastSyncStore(db),
      discoveryRelays: ndk.config.bootstrapRelays,
    );

    client = await NostrMailClient.create(
      ndk: ndk,
      database: database,
      db: db,
      blossomCache: blossomCache,
      syncEngine: syncEngine,
      indexerRelays: relays,
      defaultNip65Relays: defaultNip65Relays ?? defaultDmRelays,
      defaultBlossomServers: defaultBlossomServers,
      nip05Overrides: nip05Overrides,
      schedulerDvm: schedulerDvm,
      schedulerDvmReadRelays: schedulerDvmReadRelays,
    );

    return this;
  }

  Future<void> destroy() async {
    await client.dispose();
    await syncEngine.dispose();
    await ndk.destroy();
    await database.close();
    await db.close();
  }
}
