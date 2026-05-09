import 'package:enough_mail_plus/enough_mail.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:test/test.dart';

void main() {
  group('Email', () {
    final parser = EmailParser();

    test('toJson serializes correctly', () {
      final date = DateTime.utc(2024, 1, 15, 10, 30);
      final rawContent = parser.build(
        from: MailAddress(null, 'sender@example.com'),
        to: [MailAddress(null, 'recipient@example.com')],
        subject: 'Test Subject',
        body: 'Test body content',
      );

      final email = Email(
        id: 'test-id',
        senderPubkey: 'abc123pubkey',
        recipientPubkey: 'recipient123pubkey',
        rawContent: rawContent,
        createdAt: date,
      );

      final json = email.toJson();

      expect(json['id'], 'test-id');
      expect(json['from'], contains('sender@example.com'));
      expect(json['subject'], 'Test Subject');
      expect(json['body'].trim(), 'Test body content');
      expect(json['senderPubkey'], 'abc123pubkey');
      expect(json['recipientPubkey'], 'recipient123pubkey');
      expect(json['rawContent'], rawContent);
    });

    test('fromJson deserializes correctly', () {
      final date = DateTime.utc(2024, 1, 15, 10, 30);
      final json = {
        'id': 'test-id',
        'senderPubkey': 'abc123pubkey',
        'recipientPubkey': 'recipient123pubkey',
        'rawContent':
            'From: sender@example.com\r\nSubject: Test Subject\r\n\r\nTest body content',
        'createdAt': date.toIso8601String(),
      };

      final email = Email.fromJson(json);

      expect(email.id, 'test-id');
      expect(email.mime.fromEmail, 'sender@example.com');
      expect(email.mime.decodeSubject(), 'Test Subject');
      expect(email.body.trim(), 'Test body content');
      expect(email.createdAt, date);
      expect(email.senderPubkey, 'abc123pubkey');
      expect(email.recipientPubkey, 'recipient123pubkey');
      expect(email.rawContent, json['rawContent']);
    });

    test('roundtrip serialization preserves data', () {
      final original = Email(
        id: 'roundtrip-id',
        senderPubkey: 'pubkey123',
        recipientPubkey: 'recipient456',
        rawContent:
            'From: test@test.com\r\nSubject: Roundtrip Test\r\n\r\nBody content',
        createdAt: DateTime.utc(2024, 6, 20, 14, 45, 30),
      );

      final restored = Email.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.senderPubkey, original.senderPubkey);
      expect(restored.recipientPubkey, original.recipientPubkey);
      expect(restored.rawContent, original.rawContent);
      expect(restored.createdAt, original.createdAt);
    });

    test('equality is based on id', () {
      final email1 = Email(
        id: 'same-id',
        senderPubkey: 'pk1',
        recipientPubkey: 'rpk1',
        rawContent: 'raw1',
        createdAt: DateTime.now(),
      );

      final email2 = Email(
        id: 'same-id',
        senderPubkey: 'pk2',
        recipientPubkey: 'rpk2',
        rawContent: 'raw2',
        createdAt: DateTime.now(),
      );

      final email3 = Email(
        id: 'different-id',
        senderPubkey: 'pk1',
        recipientPubkey: 'rpk1',
        rawContent: 'raw1',
        createdAt: DateTime.now(),
      );

      expect(email1, equals(email2));
      expect(email1, isNot(equals(email3)));
      expect(email1.hashCode, equals(email2.hashCode));
    });
  });
}
