import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:test/test.dart';

/// End-to-end test that verifies isBridged works correctly with real-world
/// email scenarios, including the bug fix for @nostr -> @nostr emails.
void main() {
  group('Email.isBridged E2E', () {
    final parser = EmailParser();

    test('BUG FIX: @nostr to @nostr email should NOT be bridged', () async {
      // This is the exact bug scenario: user sends from npub@nostr to npub@nostr
      // Before the fix, isBridged returned true incorrectly
      final senderKeyPair = Bip340.generatePrivateKey();
      final senderPubkey = senderKeyPair.publicKey;
      final senderNpub = Nip19.encodePubKey(senderPubkey);

      final recipientKeyPair = Bip340.generatePrivateKey();
      final recipientPubkey = recipientKeyPair.publicKey;
      final recipientNpub = Nip19.encodePubKey(recipientPubkey);

      // Build email exactly like the app does with MessageBuilder
      final rawContent = parser.build(
        from: MailAddress('Test User', '$senderNpub@nostr'),
        to: [MailAddress(null, '$recipientNpub@nostr')],
        subject: 'Direct Nostr Message',
        body: 'This is a test message sent directly via Nostr',
      );

      print('=== Raw MIME Content ===');
      print(rawContent);
      print('========================\n');

      // Parse the email as the app would
      final email = await parser.parseMime(
        rawContent: rawContent,
        eventId: 'test-event-id',
        senderPubkey: senderPubkey,
        recipientPubkey: recipientPubkey,
        createdAt: DateTime.now(),
      );

      // Debug info
      print('email.sender: ${email.sender}');
      print('email.sender?.email: ${email.sender?.email}');
      print('email.mime.from: ${email.mime.from}');
      print('email.senderPubkey: ${email.senderPubkey}');
      print('email.isBridged: ${email.isBridged}');

      // THE ASSERTION: This should be FALSE for direct @nostr emails
      expect(
        email.isBridged,
        isFalse,
        reason:
            'Direct @nostr to @nostr emails should NOT be marked as bridged',
      );

      // Additional assertions to verify the fix
      expect(
        email.sender,
        isNotNull,
        reason: 'Sender should be parsed from MIME headers',
      );
      expect(
        email.sender!.email,
        contains('@nostr'),
        reason: 'Sender email should be @nostr address',
      );
    });

    test(
      'bridge domain (uid.ovh) with same pubkey should NOT be bridged',
      () async {
        final senderKeyPair = Bip340.generatePrivateKey();
        final senderPubkey = senderKeyPair.publicKey;
        final senderNpub = Nip19.encodePubKey(senderPubkey);

        final recipientKeyPair = Bip340.generatePrivateKey();
        final recipientPubkey = recipientKeyPair.publicKey;

        final rawContent = parser.build(
          from: MailAddress('User', '$senderNpub@uid.ovh'),
          to: [MailAddress(null, '$recipientPubkey@nostr')],
          subject: 'Via Bridge Domain',
          body: 'Sent via bridge domain but same pubkey',
        );

        final email = await parser.parseMime(
          rawContent: rawContent,
          eventId: 'test-2',
          senderPubkey: senderPubkey,
          recipientPubkey: recipientPubkey,
          createdAt: DateTime.now(),
        );

        // Same pubkey = NOT bridged (just using bridge as SMTP relay)
        expect(email.isBridged, isFalse);
      },
    );

    test('legacy gmail email SHOULD be bridged', () async {
      final bridgeKeyPair = Bip340.generatePrivateKey();
      final bridgePubkey = bridgeKeyPair.publicKey;

      final recipientKeyPair = Bip340.generatePrivateKey();
      final recipientPubkey = recipientKeyPair.publicKey;
      final recipientNpub = Nip19.encodePubKey(recipientPubkey);

      final rawContent = parser.build(
        from: MailAddress('Alice', 'alice@gmail.com'),
        to: [MailAddress(null, '$recipientNpub@nostr')],
        subject: 'From Gmail',
        body: 'Legacy email from Gmail',
      );

      final email = await parser.parseMime(
        rawContent: rawContent,
        eventId: 'test-3',
        senderPubkey: bridgePubkey,
        recipientPubkey: recipientPubkey,
        createdAt: DateTime.now(),
      );

      // Legacy email = MUST be bridged
      expect(email.isBridged, isTrue);
      expect(email.sender, isNotNull);
      expect(email.sender!.email, equals('alice@gmail.com'));
    });

    test('mismatched pubkeys SHOULD be bridged', () async {
      final addressKeyPair = Bip340.generatePrivateKey();
      final addressPubkey = addressKeyPair.publicKey;
      final addressNpub = Nip19.encodePubKey(addressPubkey);

      final actualSenderKeyPair = Bip340.generatePrivateKey();
      final actualSenderPubkey = actualSenderKeyPair.publicKey;

      final recipientKeyPair = Bip340.generatePrivateKey();
      final recipientPubkey = recipientKeyPair.publicKey;

      final rawContent = parser.build(
        from: MailAddress(null, '$addressNpub@nostr'),
        to: [MailAddress(null, '$recipientPubkey@nostr')],
        subject: 'Mismatched Sender',
        body: 'Address pubkey differs from actual sender',
      );

      final email = await parser.parseMime(
        rawContent: rawContent,
        eventId: 'test-4',
        senderPubkey: actualSenderPubkey,
        recipientPubkey: recipientPubkey,
        createdAt: DateTime.now(),
      );

      // Different pubkeys = bridged (someone sent on behalf of another)
      expect(email.isBridged, isTrue);
    });

    test('multipart/alternative email (HTML + plain) from @nostr', () async {
      final senderKeyPair = Bip340.generatePrivateKey();
      final senderPubkey = senderKeyPair.publicKey;
      final senderNpub = Nip19.encodePubKey(senderPubkey);

      final recipientKeyPair = Bip340.generatePrivateKey();
      final recipientPubkey = recipientKeyPair.publicKey;

      // Build multipart email like the app does with MessageBuilder
      final builder = MessageBuilder.prepareMultipartAlternativeMessage();
      builder.from = [MailAddress('HTML User', '$senderNpub@nostr')];
      builder.to = [MailAddress(null, '$recipientPubkey@nostr')];
      builder.subject = 'HTML Email Test';
      builder.addTextPlain('Plain text version');
      builder.addTextHtml('<html><body><b>HTML version</b></body></html>');

      final message = builder.buildMimeMessage();
      final rawContent = message.renderMessage();

      print('=== Multipart MIME Content ===');
      print(rawContent);
      print('==============================\n');

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

    test('email with display name in From header', () async {
      final senderKeyPair = Bip340.generatePrivateKey();
      final senderPubkey = senderKeyPair.publicKey;
      final senderNpub = Nip19.encodePubKey(senderPubkey);

      final recipientKeyPair = Bip340.generatePrivateKey();
      final recipientPubkey = recipientKeyPair.publicKey;

      // Email with quoted display name
      final rawContent = parser.build(
        from: MailAddress('John "JD" Doe', '$senderNpub@nostr'),
        to: [MailAddress(null, '$recipientPubkey@nostr')],
        subject: 'With Display Name',
        body: 'Test',
      );

      final email = await parser.parseMime(
        rawContent: rawContent,
        eventId: 'test-6',
        senderPubkey: senderPubkey,
        recipientPubkey: recipientPubkey,
        createdAt: DateTime.now(),
      );

      expect(email.isBridged, isFalse);
      expect(email.sender, isNotNull);
    });
  });
}
