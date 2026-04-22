import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/shared/nips/nip19/nip19.dart';
import 'package:test/test.dart';

import 'mocks/mock_bridge.dart';
import 'mocks/mock_relay.dart';
import 'models/test_user.dart';

void main() {
  group('Bridges integration test', () {
    test('Nostr to smtp', () async {
      final relay = MockRelay(name: 'relay');
      await relay.startServer();
      addTearDown(() async {
        await relay.stopServer();
      });

      final bridge = MockBridge(
        'bridge.com',
        defaultDmRelays: [relay.url],
        defaultBlossomServers: [relay.url],
      );
      await bridge.start();
      addTearDown(() async {
        await bridge.stop();
      });

      final user = await TestUser(
        'user',
        defaultDmRelays: [relay.url],
        defaultBlossomServers: [relay.url],
        nip05Overrides: {'_smtp@bridge.com': bridge.keyPair.publicKey},
      ).create();
      addTearDown(() async {
        await user.destroy();
      });

      await user.client.send(
        from: MailAddress(
          null,
          '${Nip19.encodePubKey(user.keyPair.publicKey)}@bridge.com',
        ),
        to: [MailAddress(null, 'alice@gmail.com')],
        subject: 'subject',
        body: 'body',
      );

      await bridge.client.fetchRecent();

      expect(bridge.getEmails('alice@gmail.com').length, 1);
    });

    test('Smtp to nostr', () async {
      final relay = MockRelay(name: 'relay');
      await relay.startServer();
      addTearDown(() async {
        await relay.stopServer();
      });

      final bridge = MockBridge(
        'bridge.com',
        defaultDmRelays: [relay.url],
        defaultBlossomServers: [relay.url],
      );
      await bridge.start();
      addTearDown(() async {
        await bridge.stop();
      });

      final user = await TestUser(
        'user',
        defaultDmRelays: [relay.url],
        defaultBlossomServers: [relay.url],
        nip05Overrides: {'_smtp@bridge.com': bridge.keyPair.publicKey},
      ).create();
      addTearDown(() async {
        await user.destroy();
      });

      final builder = MessageBuilder()
        ..from = [MailAddress(null, 'alice@gmail.com')]
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
      final inbox = await user.client.getInboxEmails();

      expect(inbox.length, 1);
      expect(inbox.first.mime.decodeSubject(), 'Hello from SMTP');
      expect(inbox.first.senderPubkey, bridge.keyPair.publicKey);
    });
  });
}
