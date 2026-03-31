import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:test/test.dart';

void main() {
  group('Email.isBridged', () {
    final parser = EmailParser();

    group('direct nostr emails (no bridge)', () {
      test('returns false for @nostr address matching senderPubkey', () async {
        // Generate a random keypair
        final keyPair = Bip340.generatePrivateKey();
        final pubkey = keyPair.publicKey;
        final npub = Nip19.encodePubKey(pubkey);

        final rawContent = parser.build(
          from: MailAddress(null, '$npub@nostr'),
          to: [MailAddress(null, 'recipient@nostr')],
          subject: 'Direct Nostr Email',
          body: 'Test body',
        );

        final email = await parser.parseMime(
          rawContent: rawContent,
          eventId: 'test-1',
          senderPubkey: pubkey,
          recipientPubkey: 'recipient-pubkey',
          createdAt: DateTime.now(),
        );

        expect(email.isBridged, isFalse);
      });

      test(
        'returns false for hex@nostr address matching senderPubkey',
        () async {
          final keyPair = Bip340.generatePrivateKey();
          final pubkey = keyPair.publicKey;

          final rawContent = parser.build(
            from: MailAddress(null, '$pubkey@nostr'),
            to: [MailAddress(null, 'recipient@nostr')],
            subject: 'Hex Nostr Email',
            body: 'Test body',
          );

          final email = await parser.parseMime(
            rawContent: rawContent,
            eventId: 'test-2',
            senderPubkey: pubkey,
            recipientPubkey: 'recipient-pubkey',
            createdAt: DateTime.now(),
          );

          expect(email.isBridged, isFalse);
        },
      );

      test('returns false when sender has display name', () async {
        final keyPair = Bip340.generatePrivateKey();
        final pubkey = keyPair.publicKey;
        final npub = Nip19.encodePubKey(pubkey);

        final rawContent = parser.build(
          from: MailAddress('Test User', '$npub@nostr'),
          to: [MailAddress(null, 'recipient@nostr')],
          subject: 'With Display Name',
          body: 'Test body',
        );

        final email = await parser.parseMime(
          rawContent: rawContent,
          eventId: 'test-3',
          senderPubkey: pubkey,
          recipientPubkey: 'recipient-pubkey',
          createdAt: DateTime.now(),
        );

        expect(email.isBridged, isFalse);
      });
    });

    group('bridged emails', () {
      test(
        'returns false for bridge domain address matching senderPubkey',
        () async {
          // Using a bridge domain but same pubkey = NOT bridged
          final keyPair = Bip340.generatePrivateKey();
          final pubkey = keyPair.publicKey;
          final npub = Nip19.encodePubKey(pubkey);

          final rawContent = parser.build(
            from: MailAddress(null, '$npub@uid.ovh'),
            to: [MailAddress(null, 'recipient@nostr')],
            subject: 'Bridge Domain Email',
            body: 'Test body',
          );

          final email = await parser.parseMime(
            rawContent: rawContent,
            eventId: 'test-4',
            senderPubkey: pubkey,
            recipientPubkey: 'recipient-pubkey',
            createdAt: DateTime.now(),
          );

          // Same pubkey, just different domain - NOT bridged
          expect(email.isBridged, isFalse);
        },
      );

      test('returns true for legacy email (no pubkey in address)', () async {
        final keyPair = Bip340.generatePrivateKey();
        final bridgePubkey = keyPair.publicKey;

        final rawContent = parser.build(
          from: MailAddress('Alice', 'alice@gmail.com'),
          to: [MailAddress(null, 'recipient@nostr')],
          subject: 'Legacy Email',
          body: 'Test body',
        );

        final email = await parser.parseMime(
          rawContent: rawContent,
          eventId: 'test-5',
          senderPubkey: bridgePubkey,
          recipientPubkey: 'recipient-pubkey',
          createdAt: DateTime.now(),
        );

        expect(email.isBridged, isTrue);
      });

      test(
        'returns true when address pubkey differs from senderPubkey',
        () async {
          final keyPair1 = Bip340.generatePrivateKey();
          final keyPair2 = Bip340.generatePrivateKey();
          final addressPubkey = keyPair1.publicKey;
          final senderPubkey = keyPair2.publicKey;
          final npub = Nip19.encodePubKey(addressPubkey);

          final rawContent = parser.build(
            from: MailAddress(null, '$npub@nostr'),
            to: [MailAddress(null, 'recipient@nostr')],
            subject: 'Mismatched Pubkey',
            body: 'Test body',
          );

          final email = await parser.parseMime(
            rawContent: rawContent,
            eventId: 'test-6',
            senderPubkey: senderPubkey,
            recipientPubkey: 'recipient-pubkey',
            createdAt: DateTime.now(),
          );

          expect(email.isBridged, isTrue);
        },
      );
    });

    group('edge cases', () {
      test('returns true when sender address is null', () async {
        final rawContent = 'not a valid email';

        final email = await parser.parseMime(
          rawContent: rawContent,
          eventId: 'test-7',
          senderPubkey: 'some-pubkey',
          recipientPubkey: 'recipient-pubkey',
          createdAt: DateTime.now(),
        );

        expect(email.isBridged, isTrue);
      });

      test('returns true when sender has no @ symbol', () async {
        final rawContent = parser.build(
          from: MailAddress(null, 'invalid-address'),
          to: [MailAddress(null, 'recipient@nostr')],
          subject: 'Invalid',
          body: 'Test body',
        );

        final email = await parser.parseMime(
          rawContent: rawContent,
          eventId: 'test-8',
          senderPubkey: 'some-pubkey',
          recipientPubkey: 'recipient-pubkey',
          createdAt: DateTime.now(),
        );

        expect(email.isBridged, isTrue);
      });

      test('returns true for invalid npub format', () async {
        final rawContent = parser.build(
          from: MailAddress(null, 'npub_invalid@nostr'),
          to: [MailAddress(null, 'recipient@nostr')],
          subject: 'Invalid NPUB',
          body: 'Test body',
        );

        final email = await parser.parseMime(
          rawContent: rawContent,
          eventId: 'test-9',
          senderPubkey: 'some-pubkey',
          recipientPubkey: 'recipient-pubkey',
          createdAt: DateTime.now(),
        );

        expect(email.isBridged, isTrue);
      });

      test('returns true for invalid hex format (wrong length)', () async {
        final rawContent = parser.build(
          from: MailAddress(null, 'abc123@nostr'),
          to: [MailAddress(null, 'recipient@nostr')],
          subject: 'Invalid Hex',
          body: 'Test body',
        );

        final email = await parser.parseMime(
          rawContent: rawContent,
          eventId: 'test-10',
          senderPubkey: 'some-pubkey',
          recipientPubkey: 'recipient-pubkey',
          createdAt: DateTime.now(),
        );

        expect(email.isBridged, isTrue);
      });

      test('returns true for hex with invalid characters', () async {
        final rawContent = parser.build(
          from: MailAddress(null, 'xyz123@nostr'),
          to: [MailAddress(null, 'recipient@nostr')],
          subject: 'Invalid Hex Chars',
          body: 'Test body',
        );

        final email = await parser.parseMime(
          rawContent: rawContent,
          eventId: 'test-11',
          senderPubkey: 'some-pubkey',
          recipientPubkey: 'recipient-pubkey',
          createdAt: DateTime.now(),
        );

        expect(email.isBridged, isTrue);
      });
    });

    group('real-world scenarios', () {
      test('user sending from npub@nostr directly', () async {
        final keyPair = Bip340.generatePrivateKey();
        final pubkey = keyPair.publicKey;
        final npub = Nip19.encodePubKey(pubkey);

        final rawContent = parser.build(
          from: MailAddress('LEF', '$npub@nostr'),
          to: [
            MailAddress(
              null,
              'npub12veng4g7mdlz9v2yryx2apy3d75m3nmuht28naq5l3qfdaegy90szan7m7@nostr',
            ),
          ],
          subject: 's',
          body: 'test',
        );

        final email = await parser.parseMime(
          rawContent: rawContent,
          eventId: 'real-1',
          senderPubkey: pubkey,
          recipientPubkey: 'recipient-pubkey',
          createdAt: DateTime.now(),
        );

        expect(email.isBridged, isFalse);
      });

      test('user sending via bridge domain (testnmail.uid.ovh)', () async {
        final keyPair = Bip340.generatePrivateKey();
        final pubkey = keyPair.publicKey;
        final npub = Nip19.encodePubKey(pubkey);

        final rawContent = parser.build(
          from: MailAddress('LEF', '$npub@testnmail.uid.ovh'),
          to: [
            MailAddress(
              null,
              'npub12veng4g7mdlz9v2yryx2apy3d75m3nmuht28naq5l3qfdaegy90szan7m7@nostr',
            ),
          ],
          subject: 's',
          body: 'test',
        );

        final email = await parser.parseMime(
          rawContent: rawContent,
          eventId: 'real-2',
          senderPubkey: pubkey,
          recipientPubkey: 'recipient-pubkey',
          createdAt: DateTime.now(),
        );

        // Same pubkey, just using bridge domain - NOT bridged
        expect(email.isBridged, isFalse);
      });

      test('legacy email from gmail user', () async {
        final keyPair = Bip340.generatePrivateKey();
        final bridgePubkey = keyPair.publicKey;

        final rawContent = parser.build(
          from: MailAddress('Alice', 'alice@gmail.com'),
          to: [
            MailAddress(
              null,
              'npub12veng4g7mdlz9v2yryx2apy3d75m3nmuht28naq5l3qfdaegy90szan7m7@nostr',
            ),
          ],
          subject: 'Hello from Gmail',
          body: 'Test message',
        );

        final email = await parser.parseMime(
          rawContent: rawContent,
          eventId: 'real-3',
          senderPubkey: bridgePubkey,
          recipientPubkey: 'recipient-pubkey',
          createdAt: DateTime.now(),
        );

        expect(email.isBridged, isTrue);
      });
    });
  });
}
