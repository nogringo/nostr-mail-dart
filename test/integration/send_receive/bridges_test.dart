import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:ndk/shared/nips/nip19/nip19.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:test/test.dart';

import '../../helpers/test_user.dart';
import '../../mocks/mock_bridge.dart';
import '../../mocks/mock_relay.dart';

void main() {
  group('Bridges integration', () {
    test(
      'Nostr → SMTP forwards through the bridge to the legacy address',
      () async {
        final relay = MockRelay(name: 'relay', explicitPort: 19017);
        await relay.startServer();
        addTearDown(() async => await relay.stopServer());

        final bridge = MockBridge(
          'bridge.com',
          defaultDmRelays: [relay.url],
          defaultBlossomServers: [relay.url],
        );
        await bridge.start();
        addTearDown(() async => await bridge.stop());

        final user = await TestUser(
          'user',
          defaultDmRelays: [relay.url],
          defaultBlossomServers: [relay.url],
          nip05Overrides: {'_smtp@bridge.com': bridge.keyPair.publicKey},
        ).create();
        addTearDown(() async => await user.destroy());

        await user.client.send(
          from: MailAddress(
            null,
            '${Nip19.encodePubKey(user.keyPair.publicKey)}@bridge.com',
          ),
          to: [SmtpRecipient('alice@gmail.com')],
          subject: 'subject',
          body: 'body',
        );

        await Future.delayed(const Duration(seconds: 3));
        await bridge.client.fetchRecent();

        expect(bridge.getEmails('alice@gmail.com').length, 1);
      },
    );

    test(
      'Nostr → SMTP relays To and BCC legacy recipients via the rcpt-to envelope',
      () async {
        final relay = MockRelay(name: 'relay', explicitPort: 19023);
        await relay.startServer();
        addTearDown(() async => await relay.stopServer());

        final bridge = MockBridge(
          'bridge.com',
          defaultDmRelays: [relay.url],
          defaultBlossomServers: [relay.url],
        );
        await bridge.start();
        addTearDown(() async => await bridge.stop());

        final user = await TestUser(
          'user',
          defaultDmRelays: [relay.url],
          defaultBlossomServers: [relay.url],
          nip05Overrides: {'_smtp@bridge.com': bridge.keyPair.publicKey},
        ).create();
        addTearDown(() async => await user.destroy());

        final fromAddress =
            '${Nip19.encodePubKey(user.keyPair.publicKey)}@bridge.com';

        await user.client.send(
          from: MailAddress(null, fromAddress),
          to: [SmtpRecipient('alice@gmail.com')],
          bcc: [SmtpRecipient('bob@gmail.com')],
          subject: 'subject',
          body: 'body',
        );

        await Future.delayed(const Duration(seconds: 3));
        await bridge.client.fetchRecent();

        // Both legacy recipients share a single gift wrap to the bridge,
        // carrying the sender as mail-from and both addresses as rcpt-to.
        expect(bridge.receivedEnvelopes, hasLength(1));
        final envelope = bridge.receivedEnvelopes.single;
        expect(envelope.mailFrom, fromAddress);
        expect(
          envelope.rcptTo,
          containsAll(['alice@gmail.com', 'bob@gmail.com']),
        );

        // The BCC recipient is delivered purely from rcpt-to: its address is
        // stripped from the rendered MIME, so envelope routing is the only
        // way the bridge learns about it.
        expect(bridge.getEmails('alice@gmail.com'), hasLength(1));
        expect(bridge.getEmails('bob@gmail.com'), hasLength(1));
      },
    );

    test(
      'public email with a legacy BCC recipient still gift-wraps the bridge',
      () async {
        final relay = MockRelay(name: 'relay', explicitPort: 19024);
        await relay.startServer();
        addTearDown(() async => await relay.stopServer());

        final bridge = MockBridge(
          'bridge.com',
          defaultDmRelays: [relay.url],
          defaultBlossomServers: [relay.url],
        );
        await bridge.start();
        addTearDown(() async => await bridge.stop());

        final user = await TestUser(
          'user',
          defaultDmRelays: [relay.url],
          defaultBlossomServers: [relay.url],
          nip05Overrides: {'_smtp@bridge.com': bridge.keyPair.publicKey},
        ).create();
        addTearDown(() async => await user.destroy());

        final fromAddress =
            '${Nip19.encodePubKey(user.keyPair.publicKey)}@bridge.com';
        final publicRecipient = Bip340.generatePrivateKey();

        await user.client.send(
          from: MailAddress(null, fromAddress),
          to: [NostrRecipient.fromPubkey(publicRecipient.publicKey)],
          bcc: [SmtpRecipient('alice@gmail.com')],
          subject: 'public with legacy bcc',
          body: 'body',
          isPublic: true,
          signRumor: true,
        );

        await Future.delayed(const Duration(seconds: 3));
        await bridge.client.fetchRecent();

        // The bridge is reached by a normal gift wrap carrying the envelope,
        // not by the public event - so the legacy BCC recipient is delivered.
        expect(bridge.receivedEnvelopes, hasLength(1));
        expect(bridge.receivedEnvelopes.single.mailFrom, fromAddress);
        expect(
          bridge.receivedEnvelopes.single.rcptTo,
          contains('alice@gmail.com'),
        );
        expect(bridge.getEmails('alice@gmail.com'), hasLength(1));
      },
    );

    test('SMTP → Nostr delivers a legacy email through the bridge, held '
        'in requests until its sender is accepted', () async {
      final relay = MockRelay(name: 'relay', explicitPort: 19018);
      await relay.startServer();
      addTearDown(() async => await relay.stopServer());

      final bridge = MockBridge(
        'bridge.com',
        defaultDmRelays: [relay.url],
        defaultBlossomServers: [relay.url],
      );
      await bridge.start();
      addTearDown(() async => await bridge.stop());

      final user = await TestUser(
        'user',
        defaultDmRelays: [relay.url],
        defaultBlossomServers: [relay.url],
        nip05Overrides: {'_smtp@bridge.com': bridge.keyPair.publicKey},
      ).create();
      addTearDown(() async => await user.destroy());

      final builder = MessageBuilder()
        ..from = [MailAddress(null, 'Alice@Gmail.com')]
        ..to = [
          MailAddress(
            null,
            '${Nip19.encodePubKey(user.keyPair.publicKey)}@bridge.com',
          ),
        ]
        ..subject = 'Hello from SMTP'
        ..text = 'This is a test message from SMTP.';
      final mimeMessage = builder.buildMimeMessage();

      await bridge.receiveMailFromSmtp(
        MailAddress(null, 'alice@gmail.com'),
        mimeMessage,
      );

      await user.client.fetchRecent();
      final request = (await user.client.getSummaries(
        folder: 'requests',
      )).items.single;
      expect(request.subject, 'Hello from SMTP');
      expect(request.senderPubkey, bridge.keyPair.publicKey);
      expect(request.senderKey, '${bridge.keyPair.publicKey}:alice@gmail.com');
      expect(await user.client.getPendingSenderCount(), 1);

      await user.client.allowSender(request.senderKey);
      final inbox = await user.client.getInboxEmails();
      expect(inbox.single.mime.decodeSubject(), 'Hello from SMTP');
      expect(await user.client.getPendingSenderCount(), 0);

      // Another sender behind the same bridge is not accepted with Alice.
      final fromBob = MessageBuilder()
        ..from = [MailAddress(null, 'bob@gmail.com')]
        ..to = builder.to
        ..subject = 'Hello from Bob'
        ..text = 'Another sender.';
      await bridge.receiveMailFromSmtp(
        MailAddress(null, 'bob@gmail.com'),
        fromBob.buildMimeMessage(),
      );
      await user.client.fetchRecent();
      expect(
        (await user.client.getSummaries(
          folder: 'requests',
        )).items.single.subject,
        'Hello from Bob',
      );
    });
  });
}
