import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart';
import 'package:test/test.dart';

import 'models/test_user.dart';

void main() {
  test("nostr cc bcc", () async {
    final fromUser = await TestUser("from user").create();
    final toUser = await TestUser("to user").create();
    final ccUser = await TestUser("cc user").create();
    final bcc1User = await TestUser("bcc user").create();
    final bcc2User = await TestUser("bcc user").create();

    await fromUser.client.send(
      to: [
        MailAddress(
          null,
          '${Nip19.encodePubKey(toUser.keyPair.publicKey)}@nostr',
        ),
      ],
      cc: [
        MailAddress(
          null,
          '${Nip19.encodePubKey(ccUser.keyPair.publicKey)}@nostr',
        ),
      ],
      bcc: [
        MailAddress(
          null,
          '${Nip19.encodePubKey(bcc1User.keyPair.publicKey)}@nostr',
        ),
        MailAddress(
          null,
          '${Nip19.encodePubKey(bcc2User.keyPair.publicKey)}@nostr',
        ),
      ],
      subject: "subject",
      body: "body",
    );

    await Future.delayed(const Duration(seconds: 5));

    await fromUser.client.fetchRecent();
    await toUser.client.fetchRecent();
    await ccUser.client.fetchRecent();
    await bcc1User.client.fetchRecent();
    await bcc2User.client.fetchRecent();

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
      '${Nip19.encodePubKey(bcc1User.keyPair.publicKey)}@nostr',
    );
    expect(
      mail.bcc![1].email,
      '${Nip19.encodePubKey(bcc2User.keyPair.publicKey)}@nostr',
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
    // BCC should be null or empty for TO recipient
    expect(inboxMail.bcc == null || inboxMail.bcc!.isEmpty, true);

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
    // BCC should be null or empty for CC recipient
    expect(ccInboxMail.bcc == null || ccInboxMail.bcc!.isEmpty, true);

    final bcc1InboxMails = await bcc1User.client.getInboxEmails();
    final bcc1InboxMail = bcc1InboxMails.first.mime;

    expect(
      bcc1InboxMail.to!.first.email,
      '${Nip19.encodePubKey(toUser.keyPair.publicKey)}@nostr',
    );
    expect(
      bcc1InboxMail.cc!.first.email,
      '${Nip19.encodePubKey(ccUser.keyPair.publicKey)}@nostr',
    );
    expect(bcc1InboxMail.bcc == null || bcc1InboxMail.bcc!.isEmpty, true);

    final bcc2InboxMails = await bcc2User.client.getInboxEmails();
    final bcc2InboxMail = bcc2InboxMails.first.mime;

    expect(
      bcc2InboxMail.to!.first.email,
      '${Nip19.encodePubKey(toUser.keyPair.publicKey)}@nostr',
    );
    expect(
      bcc2InboxMail.cc!.first.email,
      '${Nip19.encodePubKey(ccUser.keyPair.publicKey)}@nostr',
    );
    expect(bcc2InboxMail.bcc == null || bcc2InboxMail.bcc!.isEmpty, true);

    await fromUser.destroy();
    await toUser.destroy();
    await ccUser.destroy();
    await bcc1User.destroy();
    await bcc2User.destroy();
  });
}
