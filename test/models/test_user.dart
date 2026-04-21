import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:ndk/shared/nips/nip01/key_pair.dart';
import 'package:nostr_mail/src/client.dart';
import 'package:sembast/sembast_memory.dart';

class TestUser {
  String id;
  List<String>? defaultDmRelays;
  List<String>? defaultBlossomServers;
  Map<String, String>? nip05Overrides;

  late KeyPair keyPair;
  late Ndk ndk;
  late Database db;
  late NostrMailClient client;

  TestUser(
    this.id, {
    this.defaultDmRelays,
    this.defaultBlossomServers,
    this.nip05Overrides,
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

    db = await databaseFactoryMemory.openDatabase(id);

    client = NostrMailClient(
      ndk: ndk,
      db: db,
      defaultDmRelays: defaultDmRelays,
      defaultBlossomServers: defaultBlossomServers,
      nip05Overrides: nip05Overrides,
    );

    return this;
  }

  Future<void> destroy() async {
    await ndk.destroy();
    await db.close();
  }
}
