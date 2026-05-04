import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/shared/nips/nip19/nip19.dart';
import 'package:test/test.dart';

import 'mocks/mock_blossom_server.dart';
import 'mocks/mock_relay.dart';
import 'models/test_user.dart';

void main() {
  test(
    'send and receive large email (> 32KB) via Blossom',
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

      recipient.client.watch().listen((e) => print(e));

      // Allow NDK to establish relay connections before sending
      await Future.delayed(const Duration(seconds: 3));

      // Create large body (> 60KB)
      final largeBody = 'A' * (100 * 1024); // 100KB of text
      final testSubject =
          'Large Email Test - ${DateTime.now().toIso8601String()}';

      final sw = Stopwatch()..start();
      await sender.client.send(
        to: [
          MailAddress(
            null,
            "${Nip19.encodePubKey(recipient.keyPair.publicKey)}@nostr",
          ),
        ],
        subject: testSubject,
        body: largeBody,
      );
      sw.stop();
      print("Send took ${sw.elapsedMilliseconds}ms");

      // Allow the relay to process the broadcast and the recipient to receive it
      await Future.delayed(const Duration(seconds: 2));

      await recipient.client.fetchRecent();

      await Future.delayed(const Duration(seconds: 1));

      final receivedEmails = await recipient.client.getInboxEmails();
      print(receivedEmails);
      expect(receivedEmails, isNotEmpty);

      final email = receivedEmails.firstWhere(
        (e) => e.mime.decodeSubject()?.contains('Large Email Test') ?? false,
      );

      expect(email.mime.decodeSubject(), contains('Large Email Test'));
      expect(email.body, contains("AAAAAAA"));
      expect(email.mime.fromEmail, isNotEmpty);
      expect(email.mime.to?.first.email, isNotEmpty);
      expect(email.senderPubkey, equals(sender.keyPair.publicKey));
      expect(email.recipientPubkey, equals(recipient.keyPair.publicKey));
    },
    timeout: Timeout(const Duration(seconds: 300)),
  );
}
