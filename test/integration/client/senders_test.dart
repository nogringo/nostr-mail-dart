import 'dart:async';
import 'dart:convert';

import 'package:broadcast_queue_shim_for_ndk/broadcast_queue_shim_for_ndk.dart';
import 'package:ndk/ndk.dart' hide RelaySet;
import 'package:nostr_mail/nostr_mail.dart';
import 'package:test/test.dart';

import '../../helpers/test_user.dart';
import '../../helpers/wait_for_broadcasts.dart';
import '../../mocks/mock_relay.dart';

void main() {
  late MockRelay relay;
  late TestUser phone;
  late TestUser desktop;
  late String me;

  setUp(() async {
    relay = MockRelay(name: 'senders');
    await relay.startServer();
    addTearDown(() async => await relay.stopServer());

    final suffix = DateTime.now().microsecondsSinceEpoch;
    phone = await TestUser(
      'senders_phone_$suffix',
      defaultDmRelays: [relay.url],
    ).create();
    addTearDown(() async => await phone.destroy());
    desktop = await TestUser(
      'senders_desktop_$suffix',
      defaultDmRelays: [relay.url],
      keyPair: phone.keyPair,
    ).create();
    addTearDown(() async => await desktop.destroy());
    me = phone.keyPair.publicKey;
  });

  List<Nip01Event> listEvents() =>
      relay.matchingEvents(Filter(kinds: [listAddKind], authors: [me]));

  test('a verdict reaches the other device, and comes back', () async {
    final changes = <SenderVerdictChanged>[];
    phone.client.onSender.listen(changes.add);

    await phone.client.blockSender('bob');
    await waitForBroadcasts(phone.client.broadcastQueue);

    expect(await phone.client.getSenderVerdict('bob'), SenderVerdict.block);
    final published = listEvents().single;
    expect(published.tags, [
      ['d', sendersListDTag],
    ]);
    expect(published.content, isNot(contains('bob')));

    await desktop.client.fetchRecent();
    expect(await desktop.client.getSenderVerdict('bob'), SenderVerdict.block);

    await desktop.client.allowSender('bob');
    await waitForBroadcasts(desktop.client.broadcastQueue);
    await phone.client.fetchRecent();
    expect(await phone.client.getSenderVerdict('bob'), SenderVerdict.allow);

    expect(changes.map((e) => (e.senderKey, e.verdict)), [
      ('bob', SenderVerdict.block),
      ('bob', SenderVerdict.allow),
    ]);
  });

  test('the last of two verdicts in one second wins', () async {
    await phone.client.allowSender('bob');
    await phone.client.blockSender('bob');
    await waitForBroadcasts(phone.client.broadcastQueue);

    final [first, second] = listEvents()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    expect(second.createdAt, greaterThan(first.createdAt));

    await desktop.client.fetchRecent();
    expect(await desktop.client.getSenderVerdict('bob'), SenderVerdict.block);
  });

  test('an unchanged verdict publishes nothing', () async {
    await phone.client.allowSender('bob');
    await phone.client.allowSender('bob');
    await waitForBroadcasts(phone.client.broadcastQueue);

    expect(listEvents(), hasLength(1));
  });

  test('sorting requests publishes one event', () async {
    final spam = ['spam1', 'spam2', 'spam3'];
    final known = [for (var i = 1; i <= 7; i++) 'friend$i'];
    final changes = <SenderVerdictChanged>[];
    phone.client.onSender.listen(changes.add);

    await phone.client.setSenderVerdicts({
      for (final key in spam) key: SenderVerdict.block,
      for (final key in known) key: SenderVerdict.allow,
    });
    await waitForBroadcasts(phone.client.broadcastQueue);

    expect(listEvents(), hasLength(1));
    expect(changes, hasLength(10));

    await desktop.client.fetchRecent();
    for (final key in spam) {
      expect(await desktop.client.getSenderVerdict(key), SenderVerdict.block);
    }
    for (final key in known) {
      expect(await desktop.client.getSenderVerdict(key), SenderVerdict.allow);
    }
  });

  test('sorting leaves out the senders already sorted that way', () async {
    await phone.client.allowSender('bob');
    await waitForBroadcasts(phone.client.broadcastQueue);
    final first = listEvents().single;

    await phone.client.setSenderVerdicts({
      'bob': SenderVerdict.allow,
      'carol': SenderVerdict.block,
    });
    await waitForBroadcasts(phone.client.broadcastQueue);

    final second = listEvents().where((e) => e.id != first.id).single;
    final plaintext = await phone.ndk.accounts
        .getLoggedAccount()!
        .signer
        .decryptNip44(ciphertext: second.content, senderPubKey: me);
    expect(jsonDecode(plaintext!), [
      ['sender', 'carol', 'block'],
    ]);
  });

  test('a deleted verdict is withdrawn', () async {
    await phone.client.blockSender('bob');
    await waitForBroadcasts(phone.client.broadcastQueue);
    await desktop.client.fetchRecent();
    expect(await desktop.client.getSenderVerdict('bob'), SenderVerdict.block);

    final deletion = await phone.ndk.accounts.sign(
      Nip01Event(
        pubKey: me,
        kind: deletionRequestKind,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        tags: [
          ['e', listEvents().single.id],
          ['k', listAddKind.toString()],
        ],
        content: '',
      ),
    );
    await phone.client.broadcastQueue.broadcast(
      deletion,
      relaySet: RelaySet.explicit([relay.url]),
      pubkey: me,
    );
    await waitForBroadcasts(phone.client.broadcastQueue);

    await desktop.client.fetchRecent();
    expect(await desktop.client.getSenderVerdict('bob'), isNull);
  });

  test('received mail moves with the verdict on its sender', () async {
    final stranger = await TestUser(
      'senders_stranger_${DateTime.now().microsecondsSinceEpoch}',
      defaultDmRelays: [relay.url],
    ).create();
    addTearDown(() async => await stranger.destroy());
    final senderKey = stranger.keyPair.publicKey;

    await stranger.client.send(
      to: [NostrRecipient.fromPubkey(me)],
      subject: 'Hello',
      body: 'Do we know each other?',
    );
    await waitForBroadcasts(stranger.client.broadcastQueue);
    await phone.client.fetchRecent();

    Future<String> folder() async =>
        (await phone.client.getSummaries()).items.single.folder;

    final row = (await phone.client.getSummaries(
      folder: 'requests',
    )).items.single;
    expect(row.senderKey, senderKey);
    final pending = StreamIterator(phone.client.watchPendingSenderCount());
    addTearDown(pending.cancel);
    expect(await pending.moveNext(), isTrue);
    expect(pending.current, 1);
    await expectLater(
      phone.client.moveToFolder(row.id, 'requests'),
      throwsA(isA<NostrMailException>()),
    );

    await phone.client.allowSender(senderKey);
    expect(await pending.moveNext(), isTrue);
    expect(pending.current, 0);
    expect(await folder(), 'inbox');
    expect(await phone.client.getUnreadCount(folder: 'inbox'), 1);

    await phone.client.blockSender(senderKey);
    expect(await folder(), 'spam');
    expect(await phone.client.getPendingSenderCount(), 0);
  });
}
