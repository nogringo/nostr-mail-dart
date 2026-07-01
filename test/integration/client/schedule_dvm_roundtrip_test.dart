import 'package:ndk/ndk.dart';
import 'package:ndk/entities.dart' show ReadWriteMarker;
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:nostr_scheduler_dvm/nostr_scheduler_dvm.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:test/test.dart';

import '../../helpers/test_user.dart';
import '../../mocks/mock_relay.dart';

void main() {
  test(
    'a real Scheduler DVM delivers the scheduled email at the schedule time',
    () async {
      final relay = MockRelay(name: 'relay', explicitPort: 19031);
      await relay.startServer();
      addTearDown(() async => await relay.stopServer());

      // A real Scheduler DVM running against the mock relay.
      final dvmKey = Bip340.generatePrivateKey();
      final dvmNdk = Ndk(
        NdkConfig(
          eventVerifier: Bip340EventVerifier(),
          cache: MemCacheManager(),
          bootstrapRelays: [relay.url],
          fetchedRangesEnabled: true,
        ),
      );
      dvmNdk.accounts.loginPrivateKey(
        pubkey: dvmKey.publicKey,
        privkey: dvmKey.privateKey!,
      );
      final dvmDb = await databaseFactoryMemory.openDatabase('dvm-roundtrip');
      final dvm = SchedulerDvm(
        SchedulerDvmConfig(
          ndk: dvmNdk,
          database: dvmDb,
          bootstrapRelays: [relay.url],
          announceNip89: false,
        ),
      );
      await dvm.start();
      addTearDown(() async {
        await dvm.dispose();
        await dvmNdk.destroy();
        await dvmDb.close();
      });

      final sender = await TestUser(
        'rt sender',
        defaultDmRelays: [relay.url],
        schedulerDvm: dvm.pubkey,
        schedulerDvmReadRelays: [relay.url],
      ).create();
      final recipient = await TestUser(
        'rt recipient',
        defaultDmRelays: [relay.url],
      ).create();
      addTearDown(() async {
        await sender.destroy();
        await recipient.destroy();
      });

      // The scheduler broadcasts the kind:5905 request to the user's NIP-65 relays.
      await sender.ndk.userRelayLists.broadcastAddNip65Relay(
        relayUrl: relay.url,
        marker: ReadWriteMarker.readWrite,
        broadcastRelays: [relay.url],
      );

      // Schedule a couple of seconds out so the DVM's timer fires during the test.
      final at = DateTime.now().add(const Duration(seconds: 2));
      await sender.client.scheduleEmail(
        to: [NostrRecipient.fromPubkey(recipient.keyPair.publicKey)],
        subject: 'rendez-vous lundi',
        body: 'a lundi 8h',
        at: at,
      );

      // Poll until the DVM has published and the recipient has synced it.
      Email? received;
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      while (received == null && DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(milliseconds: 400));
        await recipient.client.fetchRecent();
        final matches = (await recipient.client.getInboxEmails())
            .where((e) => e.subject == 'rendez-vous lundi')
            .toList();
        if (matches.isNotEmpty) received = matches.first;
      }

      expect(
        received,
        isNotNull,
        reason: 'the DVM should have delivered the scheduled email',
      );
      expect(received!.body.trim(), contains('a lundi 8h'));
      // The delivered email is dated at the schedule time.
      expect(
        received.createdAt.millisecondsSinceEpoch ~/ 1000,
        at.millisecondsSinceEpoch ~/ 1000,
      );
    },
  );
}
