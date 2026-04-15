import 'package:enough_mail_plus/pop.dart';
import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:test/test.dart';

void main() {
  test("Get Technical Details", () async {
    final db = await databaseFactoryMemory.openDatabase('db');

    final keyPair = Bip340.generatePrivateKey();
    final recipientKeyPair = Bip340.generatePrivateKey();

    final ndk = Ndk(
      NdkConfig(
        eventVerifier: Bip340EventVerifier(),
        cache: MemCacheManager(),
        bootstrapRelays: ["wss://nostr-01.uid.ovh"],
        logLevel: LogLevel.off,
      ),
    );

    ndk.accounts.loginPrivateKey(
      pubkey: keyPair.publicKey,
      privkey: keyPair.privateKey!,
    );

    final client = NostrMailClient(ndk: ndk, db: db);

    await client.send(
      to: [
        MailAddress(
          null,
          "${Nip19.encodePubKey(recipientKeyPair.publicKey)}@nostr",
        ),
      ],
      subject: "Test Email",
      body: "This is a test email sent via Nostr Mail.",
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
