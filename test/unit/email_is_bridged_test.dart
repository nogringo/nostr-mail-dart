import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:test/test.dart';

void main() {
  group('Email.isBridged', () {
    final parser = EmailParser();

    group('direct nostr emails (no bridge)', () {
      test('returns false for npub@nostr matching senderPubkey', () async {
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

      test('returns false for hex@nostr matching senderPubkey', () async {
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
      });

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
        expect(email.sender, isNotNull);
      });

      test('returns false for bridge domain matching senderPubkey', () async {
        // Same pubkey, just using bridge domain as SMTP relay = NOT bridged
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

        expect(email.isBridged, isFalse);
      });

      test('returns false for multipart/alternative @nostr email', () async {
        final senderKeyPair = Bip340.generatePrivateKey();
        final senderPubkey = senderKeyPair.publicKey;
        final senderNpub = Nip19.encodePubKey(senderPubkey);

        final recipientKeyPair = Bip340.generatePrivateKey();
        final recipientPubkey = recipientKeyPair.publicKey;

        final builder = MessageBuilder.prepareMultipartAlternativeMessage();
        builder.from = [MailAddress('HTML User', '$senderNpub@nostr')];
        builder.to = [MailAddress(null, '$recipientPubkey@nostr')];
        builder.subject = 'HTML Email Test';
        builder.addTextPlain('Plain text version');
        builder.addTextHtml('<html><body><b>HTML version</b></body></html>');

        final rawContent = builder.buildMimeMessage().renderMessage();

        final email = await parser.parseMime(
          rawContent: rawContent,
          eventId: 'test-5',
          senderPubkey: senderPubkey,
          recipientPubkey: recipientPubkey,
          createdAt: DateTime.now(),
        );

        expect(email.isBridged, isFalse);
        expect(email.sender, isNotNull);
        expect(email.htmlBody, contains('<html>'));
        expect(email.body, contains('Plain text version'));
      });
    });

    group('bridged emails', () {
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
        expect(email.sender!.email, equals('alice@gmail.com'));
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
        final email = await parser.parseMime(
          rawContent: 'not a valid email',
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

      test('returns true for invalid hex (wrong length)', () async {
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
  });
}
