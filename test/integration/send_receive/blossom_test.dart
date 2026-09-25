import 'package:nostr_mail/nostr_mail.dart';
import 'package:test/test.dart';

import '../../helpers/test_user.dart';
import '../../mocks/mock_blossom_server.dart';
import '../../mocks/mock_relay.dart';

void main() {
  test('send and receive a large email (>32KB) via Blossom', () async {
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
      to: [NostrRecipient.fromPubkey(recipient.keyPair.publicKey)],
      subject: testSubject,
      body: largeBody,
    );

    final uploads = await sender.client.blossomUploadQueue.listAll();
    expect(uploads, hasLength(1));
    expect(uploads.single.pubkey, sender.keyPair.publicKey);

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
  }, timeout: const Timeout(Duration(seconds: 300)));

  test('a large email keeps Bcc out of the blob recipients can open', () async {
    final relay = MockRelay(name: 'relay');
    await relay.startServer();
    addTearDown(() async => await relay.stopServer());

    final blossomServer = MockBlossomServer();
    await blossomServer.start();
    addTearDown(() async => await blossomServer.stop());

    Future<TestUser> user(String name) async {
      final u = await TestUser(
        name,
        defaultDmRelays: [relay.url],
        defaultBlossomServers: ['http://localhost:${blossomServer.port}'],
      ).create();
      addTearDown(() async => await u.destroy());
      return u;
    }

    final sender = await user('bcc_leak_sender');
    final toUser = await user('bcc_leak_to');
    final bccUser = await user('bcc_leak_bcc');

    await Future.delayed(const Duration(seconds: 3));

    await sender.client.send(
      to: [NostrRecipient.fromPubkey(toUser.keyPair.publicKey)],
      bcc: [NostrRecipient.fromPubkey(bccUser.keyPair.publicKey)],
      subject: 'Large Bcc',
      body: 'A' * (100 * 1024),
    );

    final uploads = await sender.client.blossomUploadQueue.listAll();
    expect(uploads.map((u) => u.sha256).toSet(), hasLength(2));

    await Future.delayed(const Duration(seconds: 2));
    await toUser.client.fetchRecent();
    await bccUser.client.fetchRecent();
    await Future.delayed(const Duration(seconds: 1));

    final sent = (await sender.client.getSentEmails()).single;
    expect(sent.mime.bcc, isNotEmpty);

    for (final recipient in [toUser, bccUser]) {
      final email = (await recipient.client.getInboxEmails()).single;
      expect(email.body, contains('AAAAAAA'));
      expect(email.mime.bcc ?? const [], isEmpty);
    }
  }, timeout: const Timeout(Duration(seconds: 300)));
}
