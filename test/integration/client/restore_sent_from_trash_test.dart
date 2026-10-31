import 'package:nostr_mail/nostr_mail.dart';
import 'package:test/test.dart';

import '../../helpers/publish_relay_lists.dart';
import '../../helpers/test_user.dart';
import '../../helpers/wait_for_broadcasts.dart';
import '../../mocks/mock_relay.dart';

void main() {
  test('restoring a trashed sent email returns it to sent', () async {
    final relay = MockRelay(
      name: 'restore-sent-from-trash',
      explicitPort: 19021,
    );
    await relay.startServer();
    addTearDown(() async => await relay.stopServer());

    final suffix = DateTime.now().microsecondsSinceEpoch;
    final sender = await TestUser(
      'restore_sender_$suffix',
      defaultDmRelays: [relay.url],
    ).create();

    addTearDown(() async => await sender.destroy());

    await sender.client.send(
      to: [
        NostrRecipient.fromPubkey((await listedKeyPair([relay.url])).publicKey),
      ],
      subject: 'Restore sent message',
      body: 'This message should return to Sent after restore.',
    );
    await waitForBroadcasts(sender.client.broadcastQueue);

    final sentEmail = (await sender.client.getSentEmails()).single;

    await sender.client.moveToTrash(sentEmail.id);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await waitForBroadcasts(sender.client.broadcastQueue);

    expect(
      (await sender.client.getTrashedEmails()).map((email) => email.id),
      contains(sentEmail.id),
    );
    expect(await sender.client.getSentEmails(), isEmpty);

    await sender.client.restoreFromTrash(sentEmail.id);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await waitForBroadcasts(sender.client.broadcastQueue);

    expect(
      (await sender.client.getSentEmails()).map((email) => email.id),
      contains(sentEmail.id),
    );
    expect(
      (await sender.client.getInboxEmails()).map((email) => email.id),
      isNot(contains(sentEmail.id)),
    );
  });
}
