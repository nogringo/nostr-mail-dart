import 'package:enough_mail_plus/enough_mail.dart';
import 'package:test/test.dart';

import '../../helpers/test_user.dart';
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
        MailAddress(
          null,
          'npub1krtvaf2gw0ukuvgxvf7kxjz8s3zd6agfk87cnpcdha0s8xuscj2qly5eac@nostr',
        ),
      ],
      subject: 'Restore sent message',
      body: 'This message should return to Sent after restore.',
    );
    await sender.client.flushBroadcasts();

    final sentEmail = (await sender.client.getSentEmails()).single;

    await sender.client.moveToTrash(sentEmail.id);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sender.client.flushBroadcasts();

    expect(
      (await sender.client.getTrashedEmails()).map((email) => email.id),
      contains(sentEmail.id),
    );
    expect(await sender.client.getSentEmails(), isEmpty);

    await sender.client.restoreFromTrash(sentEmail.id);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sender.client.flushBroadcasts();

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
