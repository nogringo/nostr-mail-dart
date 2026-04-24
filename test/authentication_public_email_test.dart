import 'package:enough_mail_plus/pop.dart';
import 'package:ndk/ndk.dart';
import 'package:test/test.dart';

import 'mocks/mock_relay.dart';
import 'models/test_user.dart';

void main() {
  test("Public emails can be fetched by anyone", () async {
    final relay = MockRelay(name: "name");
    await relay.startServer();
    addTearDown(() async => await relay.stopServer());

    final sender = TestUser("sender", defaultDmRelays: [relay.url]);
    await sender.create();
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

    final query = ndk.requests.query(
      filter: Filter(kinds: [1301], authors: [sender.keyPair.publicKey]),
      explicitRelays: [relay.url],
    );

    final emails = await query.future;

    expect(emails.length, 1);
    expect(emails.first.getTags('p').length, equals(2));
    expect(emails.first.pubKey, equals(sender.keyPair.publicKey));
    expect(await Bip340EventVerifier().verify(emails.first), isTrue);
  });
}
