import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart';
import 'package:test/test.dart';

import '../../helpers/test_user.dart';
import '../../mocks/mock_relay.dart';

void main() {
  test(
    'CC and BCC recipients receive a copy and only BCC stays hidden',
    () async {
      final relay = MockRelay(name: 'relay', explicitPort: 19011);
      await relay.startServer();
      addTearDown(() async => await relay.stopServer());

      final fromUser = await TestUser(
        'from user',
        defaultDmRelays: [relay.url],
      ).create();
      final toUser = await TestUser(
        'to user',
        defaultDmRelays: [relay.url],
      ).create();
      final ccUser = await TestUser(
        'cc user',
        defaultDmRelays: [relay.url],
      ).create();
      final bcc1User = await TestUser(
        'bcc1 user',
        defaultDmRelays: [relay.url],
      ).create();
      final bcc2User = await TestUser(
        'bcc2 user',
        defaultDmRelays: [relay.url],
      ).create();

      addTearDown(() async {
        await fromUser.destroy();
        await toUser.destroy();
        await ccUser.destroy();
        await bcc1User.destroy();
        await bcc2User.destroy();
      });

      String npub(String pubkey) => Nip19.encodePubKey(pubkey);

      await fromUser.client.send(
        to: [MailAddress(null, '${npub(toUser.keyPair.publicKey)}@nostr')],
        cc: [MailAddress(null, '${npub(ccUser.keyPair.publicKey)}@nostr')],
        bcc: [
          MailAddress(null, '${npub(bcc1User.keyPair.publicKey)}@nostr'),
          MailAddress(null, '${npub(bcc2User.keyPair.publicKey)}@nostr'),
        ],
        subject: 'subject',
        body: 'body',
      );

      await Future.delayed(const Duration(seconds: 5));

      await fromUser.client.fetchRecent();
      await toUser.client.fetchRecent();
      await ccUser.client.fetchRecent();
      await bcc1User.client.fetchRecent();
      await bcc2User.client.fetchRecent();

      final sentMail = (await fromUser.client.getSentEmails()).first.mime;
      expect(
        sentMail.to!.first.email,
        '${npub(toUser.keyPair.publicKey)}@nostr',
      );
      expect(
        sentMail.cc!.first.email,
        '${npub(ccUser.keyPair.publicKey)}@nostr',
      );
      expect(
        sentMail.bcc!.first.email,
        '${npub(bcc1User.keyPair.publicKey)}@nostr',
      );
      expect(
        sentMail.bcc![1].email,
        '${npub(bcc2User.keyPair.publicKey)}@nostr',
      );

      void expectInboxHidesBcc(MimeMessage mime) {
        expect(mime.to!.first.email, '${npub(toUser.keyPair.publicKey)}@nostr');
        expect(mime.cc!.first.email, '${npub(ccUser.keyPair.publicKey)}@nostr');
        expect(mime.bcc == null || mime.bcc!.isEmpty, isTrue);
      }

      expectInboxHidesBcc((await toUser.client.getInboxEmails()).first.mime);
      expectInboxHidesBcc((await ccUser.client.getInboxEmails()).first.mime);
      expectInboxHidesBcc((await bcc1User.client.getInboxEmails()).first.mime);
      expectInboxHidesBcc((await bcc2User.client.getInboxEmails()).first.mime);
    },
  );
}
