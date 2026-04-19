import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart';
import 'package:test/test.dart';

import 'models/test_user.dart';

void main() {
  test("description", () async {
    final fromUser = await TestUser("from user").create();
    final toUser = await TestUser("to user").create();
    final ccUser = await TestUser("cc user").create();
    final bccUser = await TestUser("bcc user").create();

    await fromUser.client.send(
      to: [
        MailAddress(null, '${Nip19.encodePubKey(toUser.keyPair.publicKey)}@nostr'),
      ],
      cc: [
        MailAddress(null, '${Nip19.encodePubKey(ccUser.keyPair.publicKey)}@nostr'),
      ],
      bcc: [
        MailAddress(null, '${Nip19.encodePubKey(bccUser.keyPair.publicKey)}@nostr'),
      ],
      subject: "subject",
      body: "body",
    );

    await Future.delayed(const Duration(seconds: 5));

    await fromUser.client.fetchRecent();
    await toUser.client.fetchRecent();
    await ccUser.client.fetchRecent();
    await bccUser.client.fetchRecent();

    final sentMails = await fromUser.client.getSentEmails();
    final mail = sentMails.first.mime;

    expect(
      mail.to!.first.email,
      '${Nip19.encodePubKey(toUser.keyPair.publicKey)}@nostr',
    );
    expect(
      mail.cc!.first.email,
      '${Nip19.encodePubKey(ccUser.keyPair.publicKey)}@nostr',
    );
    expect(
      mail.bcc!.first.email,
      '${Nip19.encodePubKey(bccUser.keyPair.publicKey)}@nostr',
    );

    final inboxMails = await toUser.client.getInboxEmails();
    final inboxMail = inboxMails.first.mime;

    expect(
      inboxMail.to!.first.email,
      '${Nip19.encodePubKey(toUser.keyPair.publicKey)}@nostr',
    );
    expect(
      inboxMail.cc!.first.email,
      '${Nip19.encodePubKey(ccUser.keyPair.publicKey)}@nostr',
    );
    expect(inboxMail.bcc, isNull);

    final ccInboxMails = await ccUser.client.getInboxEmails();
    final ccInboxMail = ccInboxMails.first.mime;

    expect(
      ccInboxMail.to!.first.email,
      '${Nip19.encodePubKey(toUser.keyPair.publicKey)}@nostr',
    );
    expect(
      ccInboxMail.cc!.first.email,
      '${Nip19.encodePubKey(ccUser.keyPair.publicKey)}@nostr',
    );
    expect(ccInboxMail.bcc, isNull);

    final bccInboxMails = await bccUser.client.getInboxEmails();
    final bccInboxMail = bccInboxMails.first.mime;

    expect(
      bccInboxMail.to!.first.email,
      '${Nip19.encodePubKey(toUser.keyPair.publicKey)}@nostr',
    );
    expect(
      bccInboxMail.cc!.first.email,
      '${Nip19.encodePubKey(ccUser.keyPair.publicKey)}@nostr',
    );
    expect(
      bccInboxMail.bcc!.first.email,
      '${Nip19.encodePubKey(bccUser.keyPair.publicKey)}@nostr',
    );

    await fromUser.destroy();
    await toUser.destroy();
    await ccUser.destroy();
    await bccUser.destroy();
  });
}
