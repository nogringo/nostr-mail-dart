import 'package:blossom_cache/blossom_cache.dart';
import 'package:idb_shim/idb_client_memory.dart' hide Database;
import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:ndk/shared/nips/nip01/key_pair.dart';
import 'package:nostr_mail/src/client.dart';
import 'package:nostr_mail/src/models/scheduled_email.dart';
import 'package:sembast/sembast_memory.dart';

class TestUser {
  String id;
  List<String>? defaultDmRelays;
  List<String>? defaultBlossomServers;
  Map<String, String>? nip05Overrides;
  SchedulerDvmConfig? schedulerDvm;

  late KeyPair keyPair;
  late Ndk ndk;
  late Database db;
  late BlossomCache blossomCache;
  late NostrMailClient client;

  TestUser(
    this.id, {
    this.defaultDmRelays,
    this.defaultBlossomServers,
    this.nip05Overrides,
    this.schedulerDvm,
  });

  Future<TestUser> create() async {
    keyPair = Bip340.generatePrivateKey();
    ndk = Ndk(
      NdkConfig(
        eventVerifier: Bip340EventVerifier(),
        cache: MemCacheManager(),
        bootstrapRelays: defaultDmRelays ?? [],
        fetchedRangesEnabled: true,
      ),
    );

    ndk.accounts.loginPrivateKey(
      pubkey: keyPair.publicKey,
      privkey: keyPair.privateKey!,
    );

    db = await databaseFactoryMemory.openDatabase(id);
    blossomCache = await IdbBlossomCache.open(
      factory: newIdbFactoryMemory(),
      dbName: 'blossom_cache_$id',
    );

    client = await NostrMailClient.create(
      ndk: ndk,
      db: db,
      blossomCache: blossomCache,
      defaultDmRelays: defaultDmRelays,
      defaultBlossomServers: defaultBlossomServers,
      nip05Overrides: nip05Overrides,
      schedulerDvm: schedulerDvm,
    );

    return this;
  }

  Future<void> destroy() async {
    await client.dispose();
    await ndk.destroy();
    await db.close();
  }
}
