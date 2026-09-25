import 'package:ndk/ndk.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:test/test.dart';

import '../../helpers/test_user.dart';
import '../../helpers/wait_for_broadcasts.dart';
import '../../mocks/mock_relay.dart';

void main() {
  test('a label reaches the other device in a gift wrap, and leaves with '
      'it', () async {
    final relay = MockRelay(name: 'wrapped-labels');
    await relay.startServer();
    addTearDown(() async => await relay.stopServer());

    final suffix = DateTime.now().microsecondsSinceEpoch;
    final phone = await TestUser(
      'labels_phone_$suffix',
      defaultDmRelays: [relay.url],
    ).create();
    addTearDown(() async => await phone.destroy());
    final desktop = await TestUser(
      'labels_desktop_$suffix',
      defaultDmRelays: [relay.url],
      keyPair: phone.keyPair,
    ).create();
    addTearDown(() async => await desktop.destroy());

    final me = phone.keyPair.publicKey;
    // A label can land before the email it points at.
    const emailId = 'some-email';

    List<Nip01Event> wrapsToMe() => relay
        .matchingEvents(Filter(kinds: [giftWrapKind]))
        .where((e) => e.getFirstTag('p') == me)
        .toList();

    await phone.client.markAsRead(emailId);
    await waitForBroadcasts(phone.client.broadcastQueue);

    expect(relay.matchingEvents(Filter(kinds: [labelKind])), isEmpty);
    final wrap = wrapsToMe().single;
    expect(wrap.pubKey, isNot(me));

    await desktop.client.fetchRecent();
    expect(await desktop.client.isRead(emailId), isTrue);

    await phone.client.markAsUnread(emailId);
    await waitForBroadcasts(phone.client.broadcastQueue);

    final deletion = relay
        .matchingEvents(Filter(kinds: [deletionRequestKind]))
        .single;
    expect(deletion.getTags('e'), [wrap.id]);
    expect(deletion.getTags('k'), [giftWrapKind.toString()]);
    expect(wrapsToMe(), isEmpty);

    await desktop.client.fetchRecent();
    expect(await desktop.client.isRead(emailId), isFalse);
  });
}
