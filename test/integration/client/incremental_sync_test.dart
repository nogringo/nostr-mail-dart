import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:sembast/sembast_memory.dart' hide Filter;
import 'package:sync_engine_shim_for_ndk/sync_engine_shim_for_ndk.dart';
import 'package:test/test.dart';

import '../../helpers/test_blossom_cache.dart';
import '../../helpers/test_database.dart';
import '../../helpers/test_user.dart';
import '../../mocks/mock_relay.dart';

void main() {
  test('a paginated walk projects as it goes, each email once', () async {
    // One event per request forces the engine to walk page by page instead of
    // swallowing the whole mailbox in a single query.
    final relay = MockRelay(name: 'paginated', maxEventsPerRequest: 1);
    await relay.startServer(delayResponse: const Duration(milliseconds: 40));
    addTearDown(() async => relay.stopServer());

    final alice = await TestUser(
      'page_alice',
      defaultDmRelays: [relay.url],
    ).create();
    addTearDown(alice.destroy);

    final keys = Bip340.generatePrivateKey();
    for (var i = 0; i < 5; i++) {
      await alice.client.send(
        to: [NostrRecipient.fromPubkey(keys.publicKey)],
        subject: 'mail $i',
        body: 'body $i',
      );
    }

    final ndk = Ndk(
      NdkConfig(
        eventVerifier: Bip340EventVerifier(),
        cache: MemCacheManager(),
        bootstrapRelays: [relay.url],
      ),
    );
    ndk.accounts.loginPrivateKey(
      pubkey: keys.publicKey,
      privkey: keys.privateKey!,
    );
    final db = await databaseFactoryMemory.openDatabase('page_bob');
    // Long staleness: only the explicit fetchRecent below walks, so what the
    // counts describe is one walk and not a background tick.
    final engine = SyncEngine(
      ndk,
      db: db,
      maxStaleness: const Duration(days: 1),
    );
    final bob = await NostrMailClient.create(
      ndk: ndk,
      database: testDatabase(),
      db: db,
      blossomCache: await openTestBlossomCache('page_bob'),
      syncEngine: engine,
      defaultDmRelays: [relay.url],
    );
    addTearDown(() async {
      await bob.dispose();
      await engine.dispose();
      await ndk.destroy();
      await db.close();
    });

    final received = <String>[];
    bob.onEmail.listen((email) => received.add(email.id));

    // Sampled while the walk runs: the point of projecting page by page is
    // that mail is readable before the last one lands.
    final samples = <int>[];
    var walking = true;
    Future<void> sample() async {
      while (walking) {
        samples.add((await bob.getEmails()).length);
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
    }

    final sampler = sample();
    await bob.fetchRecent();
    walking = false;
    await sampler;

    expect(await bob.getEmails(), hasLength(5));
    expect(received, hasLength(5), reason: 'no email replayed onto the bus');
    expect(received.toSet(), hasLength(5));
    // Every sample is taken before fetchRecent returns, so one non-empty read
    // is the whole point: the mailbox is readable before the walk is over.
    expect(
      samples.any((count) => count > 0),
      isTrue,
      reason: 'nothing was readable until the walk ended, saw $samples',
    );
  });
}
