import 'package:nostr_mail/nostr_mail.dart';
import 'package:test/test.dart';

import '../../helpers/test_user.dart';
import '../../mocks/mock_relay.dart';

void main() {
  group('NostrMailClient.openEmail', () {
    test('opens a private email from a gift wrap event reference', () async {
      final relay = MockRelay(name: 'open-email-giftwrap');
      await relay.startServer();
      addTearDown(relay.stopServer);

      final suffix = DateTime.now().microsecondsSinceEpoch;
      final sender = await TestUser(
        'open_email_giftwrap_sender_$suffix',
        defaultDmRelays: [relay.url],
      ).create();
      final recipient = await TestUser(
        'open_email_giftwrap_recipient_$suffix',
        defaultDmRelays: [relay.url],
      ).create();
      addTearDown(() async {
        await sender.destroy();
        await recipient.destroy();
      });

      await sender.client.send(
        to: [NostrRecipient.fromPubkey(recipient.keyPair.publicKey)],
        subject: 'Private notification email',
        body: 'Opened from a gift wrap reference.',
        keepCopy: false,
      );
      final queued = await sender.client.broadcastQueue.listAll();
      final giftWrap = queued.single.event;
      await sender.client.flushBroadcasts();

      final email = await recipient.client.openEmail(
        eventId: giftWrap.id,
        relays: [relay.url],
      );

      expect(email, isNotNull);
      expect(email!.subject, 'Private notification email');
      expect(email.textBody, contains('gift wrap reference'));
      expect(await recipient.client.getEmail(email.id), isNotNull);
    });

    test('uses account relays in addition to provided relay hints', () async {
      final accountRelay = MockRelay(name: 'open-email-account-relay');
      final hintedRelay = MockRelay(name: 'open-email-hinted-relay');
      await accountRelay.startServer();
      await hintedRelay.startServer();
      addTearDown(() async {
        await accountRelay.stopServer();
        await hintedRelay.stopServer();
      });

      final suffix = DateTime.now().microsecondsSinceEpoch;
      final sender = await TestUser(
        'open_email_account_relay_sender_$suffix',
        defaultDmRelays: [accountRelay.url],
      ).create();
      final recipient = await TestUser(
        'open_email_account_relay_recipient_$suffix',
        defaultDmRelays: [accountRelay.url],
      ).create();
      addTearDown(() async {
        await sender.destroy();
        await recipient.destroy();
      });

      await sender.client.send(
        to: [NostrRecipient.fromPubkey(recipient.keyPair.publicKey)],
        subject: 'Account relay fallback',
        body: 'Opened even though the relay hint missed the event.',
        keepCopy: false,
      );
      final queued = await sender.client.broadcastQueue.listAll();
      final giftWrap = queued.single.event;
      await sender.client.flushBroadcasts();

      final email = await recipient.client.openEmail(
        eventId: giftWrap.id,
        relays: [hintedRelay.url],
      );

      expect(email, isNotNull);
      expect(email!.subject, 'Account relay fallback');
    });

    test('opens a public email from a kind 1301 event reference', () async {
      final relay = MockRelay(name: 'open-email-public');
      await relay.startServer();
      addTearDown(relay.stopServer);

      final suffix = DateTime.now().microsecondsSinceEpoch;
      final sender = await TestUser(
        'open_email_public_sender_$suffix',
        defaultDmRelays: [relay.url],
      ).create();
      final recipient = await TestUser(
        'open_email_public_recipient_$suffix',
        defaultDmRelays: [relay.url],
      ).create();
      addTearDown(() async {
        await sender.destroy();
        await recipient.destroy();
      });

      await sender.client.send(
        to: [NostrRecipient.fromPubkey(recipient.keyPair.publicKey)],
        subject: 'Public notification email',
        body: 'Opened from a public email reference.',
        keepCopy: false,
        signRumor: true,
        isPublic: true,
      );
      final queued = await sender.client.broadcastQueue.listAll();
      final publicEvent = queued.single.event;
      await sender.client.flushBroadcasts();

      final email = await recipient.client.openEmail(
        eventId: publicEvent.id,
        relays: [relay.url],
      );

      expect(email, isNotNull);
      expect(email!.isPublic, isTrue);
      expect(email.subject, 'Public notification email');
      expect(email.textBody, contains('public email reference'));
      expect(await recipient.client.getEmail(publicEvent.id), isNotNull);
    });
  });
}
