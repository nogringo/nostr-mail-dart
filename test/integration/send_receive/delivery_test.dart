import 'package:nostr_mail/nostr_mail.dart';
import 'package:test/test.dart';

import '../../helpers/test_user.dart';
import '../../mocks/mock_blossom_server.dart';
import '../../mocks/mock_relay.dart';

void main() {
  Future<TestUser> user(
    String name,
    MockRelay relay, {
    MockRelay? nip65Relay,
    MockBlossomServer? blossom,
  }) async {
    final u = await TestUser(
      name,
      defaultDmRelays: [relay.url],
      defaultNip65Relays: nip65Relay == null ? null : [nip65Relay.url],
      defaultBlossomServers: [
        if (blossom != null) 'http://localhost:${blossom.port}',
      ],
    ).create();
    addTearDown(u.destroy);
    return u;
  }

  Future<MockRelay> startRelay(MockRelay relay) async {
    await relay.startServer();
    addTearDown(relay.stopServer);
    return relay;
  }

  Future<EmailDelivery> settled(TestUser sender) async {
    final sent = (await sender.client.getSentEmails()).single;
    final delivery = await sender.client
        .watchDelivery(sent.id)
        .firstWhere(
          (d) =>
              d != null &&
              [
                ...d.recipients,
                ?d.selfCopy,
              ].every((r) => r.status != DeliveryStatus.pending),
        )
        .timeout(const Duration(seconds: 60));
    return delivery!;
  }

  test('a recipient is delivered once one of its relays accepts', () async {
    final relay = await startRelay(MockRelay(name: 'delivery-ok'));
    final sender = await user('delivery_ok_sender', relay);
    final recipient = await user('delivery_ok_recipient', relay);

    await sender.client.send(
      to: [NostrRecipient.fromPubkey(recipient.keyPair.publicKey)],
      subject: 'Delivered',
      body: 'Hello',
    );

    final delivery = await settled(sender);
    final only = delivery.recipients.single;
    expect(only.pubkey, recipient.keyPair.publicKey);
    expect(only.status, DeliveryStatus.delivered);
    expect(only.blob, isNull);
    expect(only.relays.single.url, relay.url);
    expect(delivery.selfCopy?.status, DeliveryStatus.delivered);
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('a recipient is not delivered when its relays refuse', () async {
    final relay = await startRelay(
      MockRelay(
        name: 'delivery-blocked',
        rejectFirstEventPublishes: 1000,
        rejectEventMessage: 'blocked: not on the list',
      ),
    );
    // The relay refuses every event, relay lists included.
    final directory = await startRelay(MockRelay(name: 'delivery-directory'));
    final sender = await user(
      'delivery_blocked_sender',
      relay,
      nip65Relay: directory,
    );
    final recipient = await user(
      'delivery_blocked_recipient',
      relay,
      nip65Relay: directory,
    );

    await sender.client.send(
      to: [NostrRecipient.fromPubkey(recipient.keyPair.publicKey)],
      subject: 'Blocked',
      body: 'Hello',
    );

    final only = (await settled(sender)).recipients.single;
    expect(only.status, DeliveryStatus.failed);
    expect(only.relays.single.error, 'blocked: not on the list');
  }, timeout: const Timeout(Duration(seconds: 120)));

  test(
    'a large email is not delivered while no server holds its blob',
    () async {
      final relay = await startRelay(MockRelay(name: 'delivery-blob'));
      final blossom = MockBlossomServer(port: 3471, rejectUploadsWith: 413);
      await blossom.start();
      addTearDown(blossom.stop);

      final sender = await user(
        'delivery_blob_sender',
        relay,
        blossom: blossom,
      );
      final recipient = await user(
        'delivery_blob_recipient',
        relay,
        blossom: blossom,
      );

      await sender.client.send(
        to: [NostrRecipient.fromPubkey(recipient.keyPair.publicKey)],
        subject: 'Too large',
        body: 'A' * (100 * 1024),
      );

      final only = (await settled(sender)).recipients.single;
      expect(only.relays.single.status, DeliveryStatus.delivered);
      expect(only.blob?.status, DeliveryStatus.failed);
      expect(only.status, DeliveryStatus.failed);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  test('an email this device did not send has no delivery', () async {
    final relay = await startRelay(MockRelay(name: 'delivery-none'));
    final sender = await user('delivery_none_sender', relay);

    expect(await sender.client.watchDelivery('unknown').first, isNull);
  });
}
