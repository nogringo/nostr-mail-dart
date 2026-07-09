import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:test/test.dart';

import '../../helpers/test_user.dart';
import '../../mocks/mock_relay.dart';

void main() {
  group('sendMime beforePublish', () {
    test(
      'receives the final gift wrap and the relays used by the queue',
      () async {
        final relay = MockRelay(name: 'before-publish', explicitPort: 19031);
        final relayAddedByCallback = MockRelay(
          name: 'before-publish-added',
          explicitPort: 19034,
        );
        await relay.startServer();
        await relayAddedByCallback.startServer();
        addTearDown(() async {
          await relay.stopServer();
          await relayAddedByCallback.stopServer();
        });

        final sender = await TestUser(
          'before_publish_sender',
          defaultDmRelays: [relay.url],
        ).create();
        final recipient = await TestUser(
          'before_publish_recipient',
          defaultDmRelays: [relay.url],
        ).create();
        addTearDown(() async {
          await sender.destroy();
          await recipient.destroy();
        });

        Nip01Event? callbackEvent;
        List<String>? callbackRelays;

        await sender.client.sendMime(
          _message(),
          to: [NostrRecipient.fromPubkey(recipient.keyPair.publicKey)],
          keepCopy: false,
          beforePublish: (event, relays) async {
            callbackEvent = event;
            callbackRelays = relays;
            relays.add(relayAddedByCallback.url);
          },
        );

        final queued = await sender.client.broadcastQueue.listAll();
        expect(queued, hasLength(1));
        expect(callbackEvent, isNotNull);
        expect(callbackEvent!.kind, giftWrapKind);
        expect(queued.single.event.id, callbackEvent!.id);
        expect(callbackRelays, [relay.url, relayAddedByCallback.url]);
        expect(queued.single.relays, callbackRelays);
      },
    );

    test('runs once for every public event and gift wrap', () async {
      final relay = MockRelay(
        name: 'before-publish-public',
        explicitPort: 19032,
      );
      await relay.startServer();
      addTearDown(relay.stopServer);

      final sender = await TestUser(
        'before_publish_public_sender',
        defaultDmRelays: [relay.url],
      ).create();
      final to = await TestUser(
        'before_publish_public_to',
        defaultDmRelays: [relay.url],
      ).create();
      final bcc = await TestUser(
        'before_publish_public_bcc',
        defaultDmRelays: [relay.url],
      ).create();
      addTearDown(() async {
        await sender.destroy();
        await to.destroy();
        await bcc.destroy();
      });

      final events = <Nip01Event>[];
      await sender.client.sendMime(
        _message(),
        to: [NostrRecipient.fromPubkey(to.keyPair.publicKey)],
        bcc: [NostrRecipient.fromPubkey(bcc.keyPair.publicKey)],
        isPublic: true,
        signRumor: true,
        beforePublish: (event, relays) async {
          events.add(event);
          expect(relays, [relay.url]);
        },
      );

      expect(events.where((event) => event.kind == emailKind), hasLength(1));
      expect(events.where((event) => event.kind == giftWrapKind), hasLength(2));
      expect(await sender.client.broadcastQueue.listAll(), hasLength(3));
    });

    test('propagates errors without enqueueing the affected event', () async {
      final relay = MockRelay(
        name: 'before-publish-error',
        explicitPort: 19033,
      );
      await relay.startServer();
      addTearDown(relay.stopServer);

      final sender = await TestUser(
        'before_publish_error_sender',
        defaultDmRelays: [relay.url],
      ).create();
      final recipient = await TestUser(
        'before_publish_error_recipient',
        defaultDmRelays: [relay.url],
      ).create();
      addTearDown(() async {
        await sender.destroy();
        await recipient.destroy();
      });

      final error = StateError('publication rejected');

      await expectLater(
        sender.client.sendMime(
          _message(),
          to: [NostrRecipient.fromPubkey(recipient.keyPair.publicKey)],
          keepCopy: false,
          beforePublish: (event, relays) async => throw error,
        ),
        throwsA(same(error)),
      );
      expect(await sender.client.broadcastQueue.listAll(), isEmpty);
    });
  });
}

MimeMessage _message() => MimeMessage.parseFromText(
  'From: sender@example.com\r\n'
  'To: recipient@example.com\r\n'
  'Subject: beforePublish\r\n'
  '\r\n'
  'Hello',
);
