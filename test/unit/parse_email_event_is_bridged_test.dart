import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:nostr_mail/src/utils/event_email_parser.dart';
import 'package:test/test.dart';

import '../helpers/test_blossom_cache.dart';

/// Verifies that bridge detection follows the protocol spec
/// (nostrhub/nostr-mail-core.md): a kind 1301 rumor is bridged when it
/// carries a `mail-from` tag, and only then. The MIME `From:` header is
/// content and must not be the source of truth.
void main() {
  group('parseEmailEvent isBridged (spec-compliant)', () {
    late Ndk ndk;
    late String recipientPubkey;

    setUp(() async {
      final keyPair = Bip340.generatePrivateKey();
      recipientPubkey = keyPair.publicKey;
      ndk = Ndk(
        NdkConfig(
          eventVerifier: Bip340EventVerifier(),
          cache: MemCacheManager(),
          bootstrapRelays: const [],
        ),
      );
    });

    tearDown(() async {
      await ndk.destroy();
    });

    test(
      'rumor without mail-from tag is NOT bridged, even when MIME has no From header',
      () async {
        // Reproduces the user-reported bug: a nostr-native email whose
        // sender forgot to set a MIME From header should still be
        // classified as non-bridged.
        final senderKeyPair = Bip340.generatePrivateKey();
        final rumor = Nip01Event(
          pubKey: senderKeyPair.publicKey,
          kind: 1301,
          tags: [
            ['p', recipientPubkey],
          ],
          content:
              'To: "Test" <npub1xxx@nostr>\r\n'
              'Date: Sun, 24 May 2026 16:01:02 +0200\r\n'
              'Subject: tt\r\n'
              'MIME-Version: 1.0\r\n'
              'Content-Type: text/plain; charset="utf-8"\r\n\r\n'
              'hello',
        );

        final email = await parseEmailEvent(
          event: rumor,
          ndk: ndk,
          recipientPubkey: recipientPubkey,
          blossomCache: await openTestBlossomCache(
            'parse_no_mail_from_${DateTime.now().microsecondsSinceEpoch}',
          ),
        );

        expect(email.isBridged, isFalse);
      },
    );

    test('rumor with mail-from tag IS bridged', () async {
      final senderKeyPair = Bip340.generatePrivateKey();
      final rumor = Nip01Event(
        pubKey: senderKeyPair.publicKey,
        kind: 1301,
        tags: [
          ['p', recipientPubkey],
          ['mail-from', 'alice@gmail.com'],
          ['rcpt-to', 'npub1bob...@bridge.com'],
        ],
        content:
            'From: alice@gmail.com\r\n'
            'To: bob@bridge.com\r\n'
            'Subject: hi\r\n\r\n'
            'body',
      );

      final email = await parseEmailEvent(
        event: rumor,
        ndk: ndk,
        recipientPubkey: recipientPubkey,
        blossomCache: await openTestBlossomCache(
          'parse_with_mail_from_${DateTime.now().microsecondsSinceEpoch}',
        ),
      );

      expect(email.isBridged, isTrue);
    });
  });
}
