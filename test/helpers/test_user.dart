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

class TestUser {
  String id;
  List<String>? defaultDmRelays;
  List<String>? defaultBlossomServers;
  Map<String, String>? nip05Overrides;
  String? schedulerDvm;
  List<String>? schedulerDvmReadRelays;

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
    this.defaultBlossomServers,
    this.nip05Overrides,
    this.schedulerDvm,
    this.schedulerDvmReadRelays,
  });

  Future<TestUser> create() async {
    keyPair = Bip340.generatePrivateKey();
    ndk = Ndk(
      NdkConfig(
        eventVerifier: Bip340EventVerifier(),
        cache: MemCacheManager(),
        bootstrapRelays: defaultDmRelays ?? [],
      ),
    );

    ndk.accounts.loginPrivateKey(
      pubkey: keyPair.publicKey,
      privkey: keyPair.privateKey!,
    );

    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    database = NostrMailDatabase(NativeDatabase.memory());
    db = await databaseFactoryMemory.openDatabase(id);
    blossomCache = await IdbBlossomCache.open(
      factory: newIdbFactoryMemory(),
      dbName: 'blossom_cache_$id',
    );

    syncEngine = SyncEngine(ndk, db: db);

    client = await NostrMailClient.create(
      ndk: ndk,
      database: database,
      db: db,
      blossomCache: blossomCache,
      syncEngine: syncEngine,
      defaultDmRelays: defaultDmRelays,
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
