import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/shared/nips/nip19/nip19.dart';
import 'package:test/test.dart';

import '../../helpers/test_user.dart';
import '../../mocks/mock_blossom_server.dart';
import '../../mocks/mock_relay.dart';

void main() {
  test(
    'send and receive a large email (>32KB) via Blossom',
    () async {
      final relay = MockRelay(name: 'relay', explicitPort: 19003);
      await relay.startServer();
      addTearDown(() async => await relay.stopServer());

      final blossomServer = MockBlossomServer(port: 3457);
      await blossomServer.start();
      addTearDown(() async => await blossomServer.stop());

      final blossomUrl = 'http://localhost:${blossomServer.port}';

      final sender = await TestUser(
        'sender',
        defaultDmRelays: [relay.url],
        defaultBlossomServers: [blossomUrl],
      ).create();
      addTearDown(() async => await sender.destroy());

      final recipient = await TestUser(
        'recipient',
        defaultDmRelays: [relay.url],
        defaultBlossomServers: [blossomUrl],
      ).create();
      addTearDown(() async => await recipient.destroy());

      // Allow NDK to establish relay connections before sending.
      await Future.delayed(const Duration(seconds: 3));

      final largeBody = 'A' * (100 * 1024); // 100KB of text
      final testSubject =
          'Large Email Test - ${DateTime.now().toIso8601String()}';

      await sender.client.send(
        to: [
          MailAddress(
            null,
            '${Nip19.encodePubKey(recipient.keyPair.publicKey)}@nostr',
          ),
        ],
        subject: testSubject,
        body: largeBody,
      );

      // Allow the relay to broadcast and the recipient to receive.
      await Future.delayed(const Duration(seconds: 2));

      await recipient.client.fetchRecent();
      await Future.delayed(const Duration(seconds: 1));

      final received = await recipient.client.getInboxEmails();
      expect(received, isNotEmpty);

      final email = received.firstWhere(
        (e) => e.mime.decodeSubject()?.contains('Large Email Test') ?? false,
      );

      expect(email.mime.decodeSubject(), contains('Large Email Test'));
      expect(email.body, contains('AAAAAAA'));
      expect(email.mime.fromEmail, isNotEmpty);
      expect(email.mime.to?.first.email, isNotEmpty);
      expect(email.senderPubkey, sender.keyPair.publicKey);
      expect(email.recipientPubkey, recipient.keyPair.publicKey);
    },
    timeout: const Timeout(Duration(seconds: 300)),
  );
}
