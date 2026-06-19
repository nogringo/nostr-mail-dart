import 'dart:convert';

import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/entities.dart';
import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:ndk/shared/nips/nip44/nip44.dart';
import 'package:nostr_scheduler_dvm/nostr_scheduler_dvm.dart' as dvm;
import 'package:nostr_mail/src/constants.dart';
import 'package:nostr_mail/src/exceptions.dart';
import 'package:nostr_mail/src/models/scheduled_email.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:test/test.dart';

import '../../helpers/test_user.dart';
import '../../mocks/mock_relay.dart';

void main() {
  group('scheduled send', () {
    test('requires scheduler config for delayed emails', () async {
      final user = await TestUser('scheduled_no_config').create();
      addTearDown(() async => await user.destroy());

      await expectLater(
        user.client.send(
          to: [
            MailAddress(
              null,
              '${Nip19.encodePubKey(user.keyPair.publicKey)}@nostr',
            ),
          ],
          subject: 'Later',
          body: 'Body',
          scheduledAt: DateTime.now().add(const Duration(hours: 1)),
        ),
        throwsA(isA<NostrMailException>()),
      );
    });

    test('rejects non-future scheduledAt', () async {
      final dvm = Bip340.generatePrivateKey();
      final user = await TestUser(
        'scheduled_past',
        schedulerDvm: SchedulerDvmConfig(pubkey: dvm.publicKey),
      ).create();
      addTearDown(() async => await user.destroy());

      await expectLater(
        user.client.send(
          to: [
            MailAddress(
              null,
              '${Nip19.encodePubKey(user.keyPair.publicKey)}@nostr',
            ),
          ],
          subject: 'Too late',
          body: 'Body',
          scheduledAt: DateTime.now().subtract(const Duration(seconds: 1)),
        ),
        throwsA(isA<NostrMailException>()),
      );
    });

    test('creates scheduler jobs without immediate email broadcast', () async {
      final relay = MockRelay(name: 'scheduler-relay', explicitPort: 19130);
      await relay.startServer();
      addTearDown(() async => await relay.stopServer());

      final dvm = Bip340.generatePrivateKey();
      final recipient = await TestUser(
        'scheduled_recipient',
        defaultDmRelays: [relay.url],
      ).create();
      addTearDown(() async => await recipient.destroy());

      final sender = await TestUser(
        'scheduled_sender',
        defaultDmRelays: [relay.url],
        schedulerDvm: SchedulerDvmConfig(
          pubkey: dvm.publicKey,
          readRelays: [relay.url],
        ),
      ).create();
      addTearDown(() async => await sender.destroy());

      await sender.ndk.config.cache.saveUserRelayList(
        UserRelayList(
          pubKey: sender.keyPair.publicKey,
          relays: {relay.url: ReadWriteMarker.readWrite},
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          refreshedTimestamp: 0,
        ),
      );

      final scheduledAt = DateTime.utc(2030, 1, 7, 8);

      await sender.client.send(
        to: [
          MailAddress(
            null,
            '${Nip19.encodePubKey(recipient.keyPair.publicKey)}@nostr',
          ),
        ],
        subject: 'Monday morning',
        body: 'See you then',
        keepCopy: true,
        scheduledAt: scheduledAt,
      );

      final sentNow = await sender.client.getSentEmails();
      expect(sentNow, isEmpty);

      final scheduled = await sender.client.listScheduledEmails();
      expect(scheduled, hasLength(1));
      expect(scheduled.single.subject, 'Monday morning');
      expect(
        scheduled.single.scheduledAt.millisecondsSinceEpoch ~/ 1000,
        scheduledAt.millisecondsSinceEpoch ~/ 1000,
      );
      expect(scheduled.single.mailEvent, isNotNull);
      expect(scheduled.single.mailEvent!.kind, emailKind);
      expect(
        scheduled.single.mailEvent!.createdAt,
        scheduledAt.millisecondsSinceEpoch ~/ 1000,
      );

      final queued = await sender.client.broadcastQueue.listAll();
      expect(queued.map((record) => record.event.kind).toSet(), {5905, 31234});

      final manifest = queued
          .map((record) => record.event)
          .singleWhere((event) => event.kind == 31234);
      final manifestContent = await Nip44.decryptMessage(
        manifest.content,
        sender.keyPair.privateKey!,
        manifest.pubKey,
      );
      final manifestMailEvent = Nip01EventModel.fromJson(
        jsonDecode(manifestContent) as Map<String, dynamic>,
      );
      expect(manifestMailEvent.kind, emailKind);
      expect(
        manifestMailEvent.createdAt,
        scheduledAt.millisecondsSinceEpoch ~/ 1000,
      );
      expect(
        MimeMessage.parseFromText(manifestMailEvent.content).decodeSubject(),
        'Monday morning',
      );

      final requestEvents = queued
          .map((record) => record.event)
          .where((event) => event.kind == 5905)
          .toList();
      expect(requestEvents, hasLength(2));

      final targetEvents = <Nip01Event>[];
      for (final request in requestEvents) {
        final payload = await Nip44.decryptMessage(
          request.content,
          dvm.privateKey!,
          request.pubKey,
        );
        final json = jsonDecode(payload) as Map<String, dynamic>;
        final eventJson = json['signed_event'] as Map<String, dynamic>;
        targetEvents.add(Nip01EventModel.fromJson(eventJson));
      }

      expect(targetEvents.every((event) => event.kind == giftWrapKind), isTrue);
      expect(
        targetEvents.every(
          (event) =>
              event.createdAt == scheduledAt.millisecondsSinceEpoch ~/ 1000,
        ),
        isTrue,
      );

      final selfGiftWrap = targetEvents.singleWhere(
        (event) => event.getFirstTag('p') == sender.keyPair.publicKey,
      );
      final selfRumor = await sender.ndk.giftWrap.fromGiftWrap(
        giftWrap: selfGiftWrap,
      );
      expect(selfRumor.createdAt, scheduledAt.millisecondsSinceEpoch ~/ 1000);

      final selfMime = MimeMessage.parseFromText(selfRumor.content);
      expect(
        selfMime.decodeDate()!.millisecondsSinceEpoch ~/ 1000,
        scheduledAt.toLocal().millisecondsSinceEpoch ~/ 1000,
      );
    });

    test('publishes due email through a test Scheduler DVM', () async {
      final relay = MockRelay(name: 'scheduler-dvm-relay', explicitPort: 19131);
      await relay.startServer();
      addTearDown(() async => await relay.stopServer());

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
      addTearDown(() async => await dvmNdk.destroy());

      final dvmDb = await databaseFactoryMemory.openDatabase(
        'scheduler_dvm_19131',
      );
      final testDvm = dvm.SchedulerDvm(
        dvm.SchedulerDvmConfig(
          ndk: dvmNdk,
          database: dvmDb,
          bootstrapRelays: [relay.url],
          announceNip89: false,
        ),
      );
      addTearDown(() async => await testDvm.dispose());

      final recipient = await TestUser(
        'scheduled_dvm_recipient',
        defaultDmRelays: [relay.url],
      ).create();
      addTearDown(() async => await recipient.destroy());

      final sender = await TestUser(
        'scheduled_dvm_sender',
        defaultDmRelays: [relay.url],
        schedulerDvm: SchedulerDvmConfig(
          pubkey: dvmKey.publicKey,
          readRelays: [relay.url],
        ),
      ).create();
      addTearDown(() async => await sender.destroy());

      await sender.ndk.config.cache.saveUserRelayList(
        UserRelayList(
          pubKey: sender.keyPair.publicKey,
          relays: {relay.url: ReadWriteMarker.readWrite},
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          refreshedTimestamp: 0,
        ),
      );

      final scheduledAt = DateTime.now().add(const Duration(seconds: 2));
      await sender.client.send(
        to: [
          MailAddress(
            null,
            '${Nip19.encodePubKey(recipient.keyPair.publicKey)}@nostr',
          ),
        ],
        subject: 'Delivered by test DVM',
        body: 'This should arrive after the DVM publishes it.',
        keepCopy: false,
        scheduledAt: scheduledAt,
      );
      await sender.client.flushBroadcasts(timeout: const Duration(seconds: 5));
      // TODO(relaystr/ndk#648): start the DVM before scheduling once MockRelay
      // subscriptions handle tag-filtered events consistently. For now the
      // DVM starts after the request is flushed so its resync can load the job.
      await testDvm.start();

      await _waitFor(() async {
        await recipient.client.fetchRecent();
        final inbox = await recipient.client.getInboxEmails();
        return inbox.any(
          (email) => email.mime.decodeSubject() == 'Delivered by test DVM',
        );
      });

      final inbox = await recipient.client.getInboxEmails();
      final delivered = inbox.singleWhere(
        (email) => email.mime.decodeSubject() == 'Delivered by test DVM',
      );
      expect(
        delivered.createdAt.millisecondsSinceEpoch ~/ 1000,
        scheduledAt.millisecondsSinceEpoch ~/ 1000,
      );
      expect(
        delivered.mime.decodeDate()!.millisecondsSinceEpoch ~/ 1000,
        scheduledAt.millisecondsSinceEpoch ~/ 1000,
      );
    });
  });
}

Future<void> _waitFor(
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail('Timed out waiting for condition');
}
