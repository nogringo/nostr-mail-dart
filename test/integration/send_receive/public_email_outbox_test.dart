// NIP-65: a public email goes to the author's write relays and to the read
// relays of everyone it tags, which is where a recipient looks for it. The
// two lists share nothing here, so only that routing gets it delivered.

import 'package:ndk/ndk.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:test/test.dart';

import '../../helpers/test_user.dart';
import '../../helpers/wait_for_broadcasts.dart';
import '../../mocks/mock_relay.dart';

void main() {
  test('a public email reaches a recipient through its read relays', () async {
    final directory = MockRelay(name: 'directory');
    final senderOutbox = MockRelay(name: 'sender-outbox');
    final recipientInbox = MockRelay(name: 'recipient-inbox');
    for (final relay in [directory, senderOutbox, recipientInbox]) {
      await relay.startServer();
      addTearDown(() async => relay.stopServer());
    }

    final sender = await TestUser(
      'outbox_sender_${DateTime.now().microsecondsSinceEpoch}',
      defaultDmRelays: [directory.url],
    ).create();
    addTearDown(() async => sender.destroy());
    final recipient = await TestUser(
      'outbox_recipient_${DateTime.now().microsecondsSinceEpoch}',
      defaultDmRelays: [directory.url],
    ).create();
    addTearDown(() async => recipient.destroy());

    Future<void> publishRelayList(TestUser user, List<List<String>> tags) =>
        user.ndk.broadcast
            .broadcast(
              nostrEvent: Nip01Event(
                pubKey: user.keyPair.publicKey,
                kind: relayListKind,
                tags: tags,
                content: '',
              ),
              specificRelays: [directory.url],
            )
            .broadcastDoneFuture;

    await publishRelayList(sender, [
      ['r', senderOutbox.url, 'write'],
      ['r', directory.url, 'read'],
    ]);
    await publishRelayList(recipient, [
      ['r', directory.url, 'write'],
      ['r', recipientInbox.url, 'read'],
    ]);

    await sender.client.send(
      to: [NostrRecipient.fromPubkey(recipient.keyPair.publicKey)],
      subject: 'Through the inbox',
      body: 'Found where the recipient reads.',
      isPublic: true,
      signRumor: true,
    );
    await waitForBroadcasts(sender.client.broadcastQueue);

    final publicEmails = Filter(kinds: [emailKind]);
    expect(senderOutbox.matchingEvents(publicEmails), hasLength(1));
    expect(recipientInbox.matchingEvents(publicEmails), hasLength(1));

    await recipient.client.fetchRecent();
    final received = await recipient.client.getEmails();
    expect(received.map((e) => e.subject), ['Through the inbox']);
    expect(received.single.isPublic, isTrue);
  });
}
