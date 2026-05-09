import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart';
import 'package:nostr_mail/src/constants.dart';
import 'package:test/test.dart';

import '../../helpers/test_user.dart';
import '../../mocks/mock_relay.dart';

void main() {
  group('Public emails', () {
    test('are publishable as kind 1301 events fetchable by anyone', () async {
      final relay = MockRelay(name: 'public-email');
      await relay.startServer();
      addTearDown(() async => await relay.stopServer());

      final sender = await TestUser(
        'sender',
        defaultDmRelays: [relay.url],
      ).create();
      addTearDown(() async => await sender.destroy());

      await sender.client.send(
        to: [
          MailAddress(
            null,
            'npub1gvs8c59ndm3xyq2jz7hpww2z5xd4y9ppuvr42wwvramn38qrmkaqdqhdag@nostr',
          ),
          MailAddress(
            null,
            'npub10xqd0n0mmm0wma2qq6ycq2y5dn7dxqj6awhfa60mesm9qccw2rfszasxh5@nostr',
          ),
        ],
        subject: 'subject',
        body: 'body',
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

      final emails = await ndk.requests
          .query(
            filter: Filter(
              kinds: [emailKind],
              authors: [sender.keyPair.publicKey],
            ),
            explicitRelays: [relay.url],
          )
          .future;

      expect(emails, hasLength(1));
      expect(emails.first.getTags('p').length, 2);
      expect(emails.first.pubKey, sender.keyPair.publicKey);
      expect(await Bip340EventVerifier().verify(emails.first), isTrue);
    });

    test(
      'hide BCC recipients from the public event but still notify them',
      () async {
        final relay = MockRelay(name: 'public-bcc', explicitPort: 4041);
        await relay.startServer();
        addTearDown(() async => await relay.stopServer());

        final sender = TestUser('sender', defaultDmRelays: [relay.url]);
        await sender.create();
        addTearDown(() async => await sender.destroy());

        const publicRecipientNpub =
            'npub1gvs8c59ndm3xyq2jz7hpww2z5xd4y9ppuvr42wwvramn38qrmkaqdqhdag';
        const publicRecipient = '$publicRecipientNpub@nostr';

        final bccUser = TestUser('bcc', defaultDmRelays: [relay.url]);
        await bccUser.create();
        addTearDown(() async => await bccUser.destroy());

        final bccRecipient =
            '${Nip19.encodePubKey(bccUser.keyPair.publicKey)}@nostr';

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

        final publicEmails = await ndk.requests
            .query(
              filter: Filter(
                kinds: [emailKind],
                authors: [sender.keyPair.publicKey],
              ),
              explicitRelays: [relay.url],
            )
            .future;

        expect(publicEmails, hasLength(1));
        final publicEvent = publicEmails.first;
        expect(
          publicEvent.getTags('p').length,
          1,
          reason: 'BCC must be hidden from public event',
        );
        expect(
          publicEvent.getTags('p').first,
          isNot(equals(bccUser.keyPair.publicKey)),
          reason: 'BCC pubkey leaked!',
        );

        // Check the BCC notification (gift wrap) reaches the BCC recipient.
        await bccUser.client.sync();
        final emails = await bccUser.client.getEmails();
        final bccEmail = emails.firstWhere(
          (e) => e.subject == 'Public with BCC',
        );
        expect(
          bccEmail.isPublic,
          isTrue,
          reason: 'BCC of a public email should have isPublic = true',
        );
      },
    );
  });
}
