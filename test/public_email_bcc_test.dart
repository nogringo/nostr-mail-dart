import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart';
import 'package:test/test.dart';
import 'package:nostr_mail/src/constants.dart';

import 'mocks/mock_relay.dart';
import 'models/test_user.dart';

void main() {
  test(
    "Public emails with BCC hide BCC recipients from public event",
    () async {
      final relay = MockRelay(name: "relay", explicitPort: 4041);
      await relay.startServer();
      addTearDown(() async => await relay.stopServer());

      final sender = TestUser("sender", defaultDmRelays: [relay.url]);
      await sender.create();
      addTearDown(() async => await sender.destroy());

      final publicRecipientNpub =
          "npub1gvs8c59ndm3xyq2jz7hpww2z5xd4y9ppuvr42wwvramn38qrmkaqdqhdag";
      final publicRecipient = "$publicRecipientNpub@nostr";

      final bccUser = TestUser("bcc", defaultDmRelays: [relay.url]);
      await bccUser.create();
      addTearDown(() async => await bccUser.destroy());
      final bccRecipient =
          "${Nip19.encodePubKey(bccUser.keyPair.publicKey)}@nostr";

      await sender.client.send(
        to: [MailAddress(null, publicRecipient)],
        bcc: [MailAddress(null, bccRecipient)],
        subject: 'Public with BCC',
        body: 'Hello everyone (and secret Bob)',
        isPublic: true,
        signRumor: true,
      );

      final ndk = Ndk(
        NdkConfig(
          eventVerifier: Bip340EventVerifier(),
          cache: MemCacheManager(),
          bootstrapRelays: [relay.url],
        ),
      );
      addTearDown(() async => await ndk.destroy());

      // 1. Check the public event
      final publicQuery = ndk.requests.query(
        filter: Filter(kinds: [emailKind], authors: [sender.keyPair.publicKey]),
        explicitRelays: [relay.url],
      );
      final publicEmails = await publicQuery.future;

      expect(publicEmails.length, 1);
      final publicEvent = publicEmails.first;
      expect(
        publicEvent.getTags('p').length,
        1,
        reason: "BCC should be hidden from public event",
      );
      expect(
        publicEvent.getTags('p').first,
        isNot(equals(bccUser.keyPair.publicKey)),
        reason: "BCC pubkey leaked!",
      );

      // 2. Check for BCC notification (gift wrap) and sync it
      await bccUser.client.sync();
      final emails = await bccUser.client.getEmails();
      expect(
        emails.any((e) => e.subject == 'Public with BCC'),
        isTrue,
        reason: "BCC recipient should have received and processed the email",
      );
    },
  );
}
