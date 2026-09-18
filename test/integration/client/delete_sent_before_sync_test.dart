import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:test/test.dart';

import '../../helpers/test_user.dart';
import '../../helpers/wait_for_broadcasts.dart';
import '../../mocks/mock_relay.dart';

void main() {
  test('deleting a sent email before any sync deletes its own wrap', () async {
    final relay = MockRelay(name: 'delete-sent', explicitPort: 19035);
    await relay.startServer();
    addTearDown(() async => await relay.stopServer());

    final sender = await TestUser(
      'delete_sent_${DateTime.now().microsecondsSinceEpoch}',
      defaultDmRelays: [relay.url],
    ).create();
    addTearDown(() async => await sender.destroy());

    await sender.client.send(
      to: [NostrRecipient.fromPubkey(Bip340.generatePrivateKey().publicKey)],
      subject: 'Deleted right away',
      body: 'Gone before the sync ever brings it back.',
    );

    final sentEmail = (await sender.client.getSentEmails()).single;
    expect(await sender.client.getGiftWrap(sentEmail.id), isNotNull);

    await sender.client.delete([sentEmail.id]);
    await waitForBroadcasts(sender.client.broadcastQueue);

    final selfWraps = relay
        .matchingEvents(Filter(kinds: [GiftWrap.kGiftWrapEventkind]))
        .where((e) => e.getFirstTag('p') == sender.keyPair.publicKey);
    expect(selfWraps, isEmpty);
  });
}
