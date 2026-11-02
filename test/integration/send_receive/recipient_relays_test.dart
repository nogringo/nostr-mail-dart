// A recipient receives on its DM relay list (kind 10050), else on its NIP-65
// read relays. One with neither stops the send before anything is saved or
// enqueued. One no relay answered for is queued and looked up by the queue.

import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:test/test.dart';

import '../../helpers/test_user.dart';
import '../../helpers/wait_for_broadcasts.dart';
import '../../mocks/mock_relay.dart';

void main() {
  late MockRelay directory;

  setUp(() async {
    directory = MockRelay(name: 'directory');
    await directory.startServer();
    addTearDown(() async => directory.stopServer());
  });

  Future<TestUser> user(String name, {bool publishesRelayLists = true}) async {
    final u = await TestUser(
      '${name}_${DateTime.now().microsecondsSinceEpoch}',
      defaultDmRelays: [directory.url],
      publishesRelayLists: publishesRelayLists,
    ).create();
    addTearDown(() async => u.destroy());
    return u;
  }

  Future<void> publishList(TestUser user, int kind, List<List<String>> tags) =>
      user.ndk.broadcast
          .broadcast(
            nostrEvent: Nip01Event(
              pubKey: user.keyPair.publicKey,
              kind: kind,
              tags: tags,
              content: '',
            ),
            specificRelays: [directory.url],
          )
          .broadcastDoneFuture;

  List<Nip01Event> wrapsFor(MockRelay relay, String pubkey) => relay
      .matchingEvents(Filter(kinds: [giftWrapKind]))
      .where((e) => e.getFirstTag('p') == pubkey)
      .toList();

  test(
    'a recipient without DM relays receives on its NIP-65 read relays',
    () async {
      final inbox = MockRelay(name: 'recipient-inbox');
      await inbox.startServer();
      addTearDown(() async => inbox.stopServer());

      final sender = await user('nip65_sender');
      final recipient = await user(
        'nip65_recipient',
        publishesRelayLists: false,
      );
      final recipientPubkey = recipient.keyPair.publicKey;
      await publishList(recipient, relayListKind, [
        ['r', directory.url, 'write'],
        ['r', inbox.url, 'read'],
      ]);

      await sender.client.send(
        to: [NostrRecipient.fromPubkey(recipientPubkey)],
        subject: 'Through the inbox',
        body: 'No DM relay list needed.',
      );
      await waitForBroadcasts(sender.client.broadcastQueue);

      expect(wrapsFor(inbox, recipientPubkey), hasLength(1));
      expect(wrapsFor(directory, recipientPubkey), isEmpty);

      await recipient.client.fetchRecent();
      final received = await recipient.client.getEmails();
      expect(received.map((e) => e.subject), ['Through the inbox']);
    },
  );

  test(
    'a recipient with no relay list stops the send before anything is saved',
    () async {
      final sender = await user('unreachable_sender');
      final reachable = await user('unreachable_reachable');
      final unreachable = NostrRecipient.fromPubkey(
        Bip340.generatePrivateKey().publicKey,
      );

      await expectLater(
        sender.client.send(
          to: [
            NostrRecipient.fromPubkey(reachable.keyPair.publicKey),
            unreachable,
          ],
          subject: 'Nowhere',
          body: 'Hello',
        ),
        throwsA(
          isA<UnreachableRecipientsException>()
              .having((e) => e.recipients, 'recipients', [unreachable])
              .having((e) => e.sender, 'sender', isFalse),
        ),
      );
      await waitForBroadcasts(sender.client.broadcastQueue);

      expect(await sender.client.getSentEmails(), isEmpty);
      expect(directory.matchingEvents(Filter(kinds: [giftWrapKind])), isEmpty);
    },
  );

  test('a recipient no relay answered for is reached once one does', () async {
    final sender = await user('later_sender');
    final recipient = await user('later_recipient');
    final recipientPubkey = recipient.keyPair.publicKey;

    directory.closeRequestsMessage = 'error: offline';
    await sender.client.send(
      to: [NostrRecipient.fromPubkey(recipientPubkey)],
      subject: 'Sent offline',
      body: 'Hello',
    );
    final sent = (await sender.client.getSentEmails()).single;
    expect(sent.subject, 'Sent offline');
    expect(wrapsFor(directory, recipientPubkey), isEmpty);

    directory.closeRequestsMessage = null;
    await waitForBroadcasts(
      sender.client.broadcastQueue,
      timeout: const Duration(seconds: 60),
    );

    expect(wrapsFor(directory, recipientPubkey), hasLength(1));
    final delivery = await sender.client.watchDelivery(sent.id).first;
    final only = delivery!.recipients.single;
    expect(only.status, DeliveryStatus.delivered);
    expect(only.relays.single.url, directory.url);
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('a recipient found with no relay after the send is reported, and looked '
      'up again on retry', () async {
    final sender = await user('later_unlisted_sender');
    final recipient = await user(
      'later_unlisted_recipient',
      publishesRelayLists: false,
    );
    final recipientPubkey = recipient.keyPair.publicKey;
    final reported = sender.client.watchUnreachableDeliveries().first;

    directory.closeRequestsMessage = 'error: offline';
    await sender.client.send(
      to: [NostrRecipient.fromPubkey(recipientPubkey)],
      subject: 'Nowhere yet',
      body: 'Hello',
    );
    directory.closeRequestsMessage = null;

    final report = await reported.timeout(const Duration(seconds: 60));
    final sent = (await sender.client.getSentEmails()).single;
    expect(report.emailId, sent.id);
    expect(report.recipientPubkey, recipientPubkey);

    final delivery = await sender.client.watchDelivery(sent.id).first;
    final only = delivery!.recipients.single;
    expect(only.unreachable, isTrue);
    expect(only.status, DeliveryStatus.failed);

    await publishList(recipient, dmRelayListKind, [
      ['relay', directory.url],
    ]);
    await sender.client.retryDelivery(sent.id);
    await waitForBroadcasts(sender.client.broadcastQueue);

    expect(wrapsFor(directory, recipientPubkey), hasLength(1));
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('getReadRelays leaves the DM relay list out', () async {
    final inbox = MockRelay(name: 'read-inbox');
    await inbox.startServer();
    addTearDown(() async => inbox.stopServer());

    final sender = await user('read_sender');
    final listed = await user('read_listed', publishesRelayLists: false);
    await publishList(listed, relayListKind, [
      ['r', directory.url, 'write'],
      ['r', inbox.url, 'read'],
    ]);
    await publishList(listed, dmRelayListKind, [
      ['relay', directory.url],
    ]);
    final dmOnly = await user('read_dm_only', publishesRelayLists: false);
    await publishList(dmOnly, dmRelayListKind, [
      ['relay', directory.url],
    ]);

    final client = sender.client;
    expect(await client.getReadRelays(listed.keyPair.publicKey), [inbox.url]);
    expect(await client.getReadRelays(dmOnly.keyPair.publicKey), isEmpty);
    expect(
      await client.getReadRelays(Bip340.generatePrivateKey().publicKey),
      isEmpty,
    );
  });
}
