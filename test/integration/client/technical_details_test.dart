import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:test/test.dart';

import '../../mocks/mock_relay.dart';

void main() {
  test('exposes gift wrap, seal, and rumor for a sent email', () async {
    final relay = MockRelay(name: 'relay', explicitPort: 19014);
    await relay.startServer();
    addTearDown(() async => await relay.stopServer());

    final db = await databaseFactoryMemory.openDatabase('db');

    final keyPair = Bip340.generatePrivateKey();
    final recipientKeyPair = Bip340.generatePrivateKey();

    final ndk = Ndk(
      NdkConfig(
        eventVerifier: Bip340EventVerifier(),
        cache: MemCacheManager(),
        bootstrapRelays: [relay.url],
        logLevel: LogLevel.off,
      ),
    );
    addTearDown(() async => await ndk.destroy());

    ndk.accounts.loginPrivateKey(
      pubkey: keyPair.publicKey,
      privkey: keyPair.privateKey!,
    );

    final client = NostrMailClient(
      ndk: ndk,
      db: db,
      defaultDmRelays: [relay.url],
    );

    await client.send(
      to: [
        MailAddress(
          null,
          '${Nip19.encodePubKey(recipientKeyPair.publicKey)}@nostr',
        ),
      ],
      subject: 'Test Email',
      body: 'This is a test email sent via Nostr Mail.',
    );

    await client.fetchRecent();

    final firstMail = (await client.getSentEmails()).first;

    final giftWrap = await client.getGiftWrap(firstMail.id);
    final seal = await client.getSeal(firstMail.id);
    final rumor = await client.getRumor(firstMail.id);

    expect(giftWrap, isNotNull);
    expect(seal, isNotNull);
    expect(rumor, isNotNull);
  });
}
