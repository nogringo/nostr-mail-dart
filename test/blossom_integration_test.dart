import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:test/test.dart';

void main() {
  test(
    'send and receive large email (> 60KB) via Blossom',
    () async {
      final senderDb = await databaseFactoryMemory.openDatabase('sender');
      final recipientDb = await databaseFactoryMemory.openDatabase('recipient');

      final senderKeys = Bip340.generatePrivateKey();
      final recipientKeys = Bip340.generatePrivateKey();

      final senderNdk = Ndk(
        NdkConfig(
          eventVerifier: Bip340EventVerifier(),
          cache: MemCacheManager(),
          bootstrapRelays: ["wss://nostr-01.uid.ovh"],
          logLevel: LogLevel.off,
        ),
      );
      final recipientNdk = Ndk(
        NdkConfig(
          eventVerifier: Bip340EventVerifier(),
          cache: MemCacheManager(),
          bootstrapRelays: ["wss://nostr-01.uid.ovh"],
          logLevel: LogLevel.off,
        ),
      );

      senderNdk.accounts.loginPrivateKey(
        pubkey: senderKeys.publicKey,
        privkey: senderKeys.privateKey!,
      );
      recipientNdk.accounts.loginPrivateKey(
        pubkey: recipientKeys.publicKey,
        privkey: recipientKeys.privateKey!,
      );

      final senderClient = NostrMailClient(ndk: senderNdk, db: senderDb);
      final recipientClient = NostrMailClient(
        ndk: recipientNdk,
        db: recipientDb,
      );

      recipientClient.watch().listen((e) => print(e));

      // Create large body (> 60KB)
      final largeBody = 'A' * (100 * 1024); // 100KB of text
      final testSubject =
          'Large Email Test - ${DateTime.now().toIso8601String()}';

      await Future.delayed(const Duration(seconds: 5));

      final sw = Stopwatch()..start();
      await senderClient.send(
        to: "${Nip19.encodePubKey(recipientKeys.publicKey)}@nostr",
        subject: testSubject,
        body: largeBody,
      );
      sw.stop();
      print("Send took ${sw.elapsedMilliseconds}ms");

      await Future.delayed(const Duration(seconds: 15));

      await recipientClient.fetchRecent();

      await Future.delayed(const Duration(seconds: 5));

      final receivedEmails = await recipientClient.getInboxEmails();
      print(receivedEmails);
      expect(receivedEmails, isNotEmpty);

      final email = receivedEmails.firstWhere(
        (e) => e.subject.contains('Large Email Test'),
      );

      expect(email.subject, contains('Large Email Test'));
      expect(email.body, contains("AAAAAAA"));
      expect(email.from, isNotEmpty);
      expect(email.to, isNotEmpty);
      expect(email.senderPubkey, equals(senderKeys.publicKey));
      expect(email.recipientPubkey, equals(recipientKeys.publicKey));
    },
    timeout: Timeout(const Duration(seconds: 300)),
  );
}
