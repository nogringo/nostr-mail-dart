// A recipient receives on its DM relay list (kind 10050), else on its NIP-65
// read relays. One with neither stops the send before anything is saved or
// enqueued.

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

  test('getReceivingRelays names the relays a send reaches', () async {
    final inbox = MockRelay(name: 'receiving-inbox');
    await inbox.startServer();
    addTearDown(() async => inbox.stopServer());

    final sender = await user('receiving_sender');
    final recipient = await user(
      'receiving_recipient',
      publishesRelayLists: false,
    );
    await publishList(recipient, relayListKind, [
      ['r', directory.url, 'write'],
      ['r', inbox.url, 'read'],
    ]);
    await publishList(recipient, dmRelayListKind, [
      ['relay', directory.url],
    ]);
    final pubkey = recipient.keyPair.publicKey;

    expect(await sender.client.getReceivingRelays(pubkey), [directory.url]);
    expect(await sender.client.getReceivingRelays(pubkey, isPublic: true), [
      inbox.url,
    ]);
    expect(
      await sender.client.getReceivingRelays(
        Bip340.generatePrivateKey().publicKey,
      ),
      isEmpty,
    );
  });
}
