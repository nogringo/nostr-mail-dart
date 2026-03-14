import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:nostr_mail/src/utils/recipient_resolver.dart';
import 'package:test/test.dart';

void main() {
  final keyPair = Bip340.generatePrivateKey();
  final npub = Nip19.encodePubKey(keyPair.publicKey);

  group("raw address", () {
    test("npub@domain", () async {
      final result = await resolveRecipient(to: '$npub@example.com');
      expect(result, keyPair.publicKey);
    });

    test("npub@nostr", () async {
      final result = await resolveRecipient(to: '$npub@nostr');
      expect(result, keyPair.publicKey);
    });

    test("npub", () async {
      final result = await resolveRecipient(to: npub);
      expect(result, keyPair.publicKey);
    });

    test("pubkey", () async {
      final result = await resolveRecipient(to: keyPair.publicKey);
      expect(result, keyPair.publicKey);
    });

    test("nip05", () async {
      final result = await resolveRecipient(to: "russell@uid.ovh");
      expect(
        result,
        "b22b06b051fd5232966a9344a634d956c3dc33a7f5ecdcad9ed11ddc4120a7f2",
      );
    });
  });

  group("address with name", () {
    test("npub@domain", () async {
      final result = await resolveRecipient(to: 'Bob <$npub@example.com>');
      expect(result, keyPair.publicKey);
    });

    test("npub@nostr", () async {
      final result = await resolveRecipient(to: 'Bob <$npub@nostr>');
      expect(result, keyPair.publicKey);
    });

    test("nip05", () async {
      final result = await resolveRecipient(to: "Bob <russell@uid.ovh>");
      expect(
        result,
        "b22b06b051fd5232966a9344a634d956c3dc33a7f5ecdcad9ed11ddc4120a7f2",
      );
    });
  });
}
