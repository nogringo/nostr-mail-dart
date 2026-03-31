import 'dart:convert';

import 'package:enough_mail_plus/enough_mail.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:ndk/ndk.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:nostr_mail/src/services/bridge_resolver.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:nostr_mail/src/storage/email_store.dart';
import 'package:nostr_mail/src/storage/gift_wrap_store.dart';
import 'package:nostr_mail/src/storage/label_store.dart';
import 'package:test/test.dart';

class MockHttpClient extends Mock implements http.Client {}

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

  group('EmailParser', () {
    late EmailParser parser;

    setUp(() {
      parser = EmailParser();
    });

    test('build creates valid RFC 2822 email', () {
      final rawContent = parser.build(
        from: MailAddress(null, 'sender@nostr.com'),
        to: [MailAddress(null, 'recipient@example.com')],
        subject: 'Test Email',
        body: 'Hello, this is a test email.',
      );

      expect(rawContent, contains('From:'));
      expect(rawContent, contains('To:'));
      expect(rawContent, contains('Subject: Test Email'));
      expect(rawContent, contains('Hello, this is a test email.'));
    });

    test('parse extracts email fields from RFC 2822', () async {
      final createdAt = DateTime.utc(2024, 1, 15, 10, 30);
      final rawContent = parser.build(
        from: MailAddress(null, 'alice@nostr.com'),
        to: [MailAddress(null, 'bob@example.com')],
        subject: 'Important Message',
        body: 'This is the message body.',
      );

      final email = await parser.parseMime(
        rawContent: rawContent,
        eventId: 'event-123',
        senderPubkey: 'sender-pubkey-abc',
        recipientPubkey: 'recipient-pubkey-xyz',
        createdAt: createdAt,
      );

      expect(email.id, 'event-123');
      expect(email.mime.fromEmail, 'alice@nostr.com');
      expect(email.mime.to?.first.email, 'bob@example.com');
      expect(email.mime.decodeSubject(), 'Important Message');
      expect(email.body, contains('This is the message body.'));
      expect(email.senderPubkey, 'sender-pubkey-abc');
      expect(email.recipientPubkey, 'recipient-pubkey-xyz');
      expect(email.rawContent, rawContent);
      expect(email.createdAt, createdAt);
    });

    test('parse handles special characters in subject', () async {
      final rawContent = parser.build(
        from: MailAddress(null, 'test@test.com'),
        to: [MailAddress(null, 'dest@dest.com')],
        subject: 'Special: émojis 🎉 and symbols!',
        body: 'Body text',
      );

      final email = await parser.parseMime(
        rawContent: rawContent,
        eventId: 'id',
        senderPubkey: 'pk',
        recipientPubkey: 'rpk',
        createdAt: DateTime.now(),
      );

      expect(email.mime.decodeSubject(), contains('Special'));
    });

    test('parse handles minimal/empty content gracefully', () async {
      final email = await parser.parseMime(
        rawContent: 'not a valid email',
        eventId: 'id',
        senderPubkey: 'pk',
        recipientPubkey: 'rpk',
        createdAt: DateTime.now(),
      );

      expect(email.id, 'id');
      expect(email.senderPubkey, 'pk');
      expect(email.recipientPubkey, 'rpk');
      expect(email.mime.fromEmail, isNull);
    });

    test('roundtrip build and parse preserves data', () async {
      final from = MailAddress(null, 'roundtrip@sender.com');
      final to = [MailAddress(null, 'roundtrip@recipient.com')];
      const subject = 'Roundtrip Subject';
      const body = 'Roundtrip body content.';
      final createdAt = DateTime.now();

      final rawContent = parser.build(
        from: from,
        to: to,
        subject: subject,
        body: body,
      );

      final email = await parser.parseMime(
        rawContent: rawContent,
        eventId: 'rt-id',
        senderPubkey: 'rt-pk',
        recipientPubkey: 'rt-rpk',
        createdAt: createdAt,
      );

      expect(email.mime.fromEmail, from.email);
      expect(email.mime.to?.first.email, to.first.email);
      expect(email.mime.decodeSubject(), subject);
      expect(email.body, contains(body));
      expect(email.recipientPubkey, 'rt-rpk');
    });
  });

  group('BridgeResolver', () {
    late MockHttpClient mockClient;
    late BridgeResolver resolver;

    setUp(() {
      mockClient = MockHttpClient();
      resolver = BridgeResolver(client: mockClient);
    });

    setUpAll(() async {
      registerFallbackValue(Uri.parse('https://example.com'));
    });

    test('resolveBridgePubkey returns pubkey for valid response', () async {
      final responseBody = jsonEncode({
        'names': {'_smtp': 'bridge-pubkey-123'},
      });

      when(
        () => mockClient.get(any()),
      ).thenAnswer((_) async => http.Response(responseBody, 200));

      final pubkey = await resolver.resolveBridgePubkey('example.com');

      expect(pubkey, 'bridge-pubkey-123');
      verify(
        () => mockClient.get(
          Uri.https('example.com', '/.well-known/nostr.json', {
            'name': '_smtp',
          }),
        ),
      ).called(1);
    });

    test('resolveBridgePubkey throws for non-200 response', () async {
      when(
        () => mockClient.get(any()),
      ).thenAnswer((_) async => http.Response('Not found', 404));

      expect(
        () => resolver.resolveBridgePubkey('example.com'),
        throwsA(isA<BridgeResolutionException>()),
      );
    });

    test('resolveBridgePubkey throws when _smtp not in response', () async {
      final responseBody = jsonEncode({
        'names': {'other': 'some-pubkey'},
      });

      when(
        () => mockClient.get(any()),
      ).thenAnswer((_) async => http.Response(responseBody, 200));

      expect(
        () => resolver.resolveBridgePubkey('example.com'),
        throwsA(isA<BridgeResolutionException>()),
      );
    });

    test('resolveNip05 returns pubkey for valid identifier', () async {
      final responseBody = jsonEncode({
        'names': {'alice': 'alice-pubkey-456'},
      });

      when(
        () => mockClient.get(any()),
      ).thenAnswer((_) async => http.Response(responseBody, 200));

      final pubkey = await resolver.resolveNip05('alice@example.com');

      expect(pubkey, 'alice-pubkey-456');
      verify(
        () => mockClient.get(
          Uri.https('example.com', '/.well-known/nostr.json', {
            'name': 'alice',
          }),
        ),
      ).called(1);
    });

    test('resolveNip05 returns null for invalid identifier format', () async {
      final result = await resolver.resolveNip05('invalid-no-at-sign');

      expect(result, isNull);
      verifyNever(() => mockClient.get(any()));
    });

    test('resolveNip05 returns null for non-200 response', () async {
      when(
        () => mockClient.get(any()),
      ).thenAnswer((_) async => http.Response('Error', 500));

      final result = await resolver.resolveNip05('user@example.com');

      expect(result, isNull);
    });

    test('resolveNip05 returns null when name not found', () async {
      final responseBody = jsonEncode({
        'names': {'other': 'other-pubkey'},
      });

      when(
        () => mockClient.get(any()),
      ).thenAnswer((_) async => http.Response(responseBody, 200));

      final result = await resolver.resolveNip05('missing@example.com');

      expect(result, isNull);
    });

    test('resolveNip05 returns null on network error', () async {
      when(() => mockClient.get(any())).thenThrow(Exception('Network error'));

      final result = await resolver.resolveNip05('user@example.com');

      expect(result, isNull);
    });
  });

  group('EmailStore', () {
    late EmailStore store;

    setUp(() async {
      final db = await databaseFactoryMemory.openDatabase(
        'test_db_${DateTime.now().millisecondsSinceEpoch}',
      );
      store = EmailStore(db);
    });

    Email createTestEmail(String id) {
      final parser = EmailParser();
      final rawContent = parser.build(
        from: MailAddress(null, 'from@test.com'),
        to: [MailAddress(null, 'to@test.com')],
        subject: 'Subject $id',
        body: 'Body $id',
      );
      return Email(
        id: id,
        senderPubkey: 'pk-$id',
        recipientPubkey: 'rpk-$id',
        rawContent: rawContent,
        createdAt: DateTime.now(),
      );
    }

    test('saveEmail and getEmailById', () async {
      final email = createTestEmail('save-test');

      await store.saveEmail(email);
      final retrieved = await store.getEmailById('save-test');

      expect(retrieved, isNotNull);
      expect(retrieved!.id, 'save-test');
      expect(retrieved.mime.decodeSubject(), 'Subject save-test');
    });

    test('getEmailById returns null for non-existent email', () async {
      final result = await store.getEmailById('non-existent');

      expect(result, isNull);
    });

    test('getEmails returns all emails sorted by date descending', () async {
      final email1 = Email(
        id: 'e1',
        senderPubkey: 'pk',
        recipientPubkey: 'rpk',
        rawContent: 'From: a@a.com\r\nSubject: First\r\n\r\nBody',
        createdAt: DateTime.utc(2024, 1, 1),
      );
      final email2 = Email(
        id: 'e2',
        senderPubkey: 'pk',
        recipientPubkey: 'rpk',
        rawContent: 'From: a@a.com\r\nSubject: Second\r\n\r\nBody',
        createdAt: DateTime.utc(2024, 1, 3),
      );
      final email3 = Email(
        id: 'e3',
        senderPubkey: 'pk',
        recipientPubkey: 'rpk',
        rawContent: 'From: a@a.com\r\nSubject: Third\r\n\r\nBody',
        createdAt: DateTime.utc(2024, 1, 2),
      );

      await store.saveEmail(email1);
      await store.saveEmail(email2);
      await store.saveEmail(email3);

      final emails = await store.getEmails();

      expect(emails.length, 3);
      expect(emails[0].id, 'e2'); // Most recent first
      expect(emails[1].id, 'e3');
      expect(emails[2].id, 'e1');
    });

    test('getEmails respects limit parameter', () async {
      for (var i = 0; i < 5; i++) {
        await store.saveEmail(createTestEmail('limit-$i'));
      }

      final emails = await store.getEmails(limit: 3);

      expect(emails.length, 3);
    });

    test('getEmails respects offset parameter', () async {
      for (var i = 0; i < 5; i++) {
        final email = Email(
          id: 'offset-$i',
          senderPubkey: 'pk',
          recipientPubkey: 'rpk',
          rawContent: 'From: a@a.com\r\nSubject: Subject $i\r\n\r\nBody',
          createdAt: DateTime.utc(2024, 1, 5 - i), // Descending dates
        );
        await store.saveEmail(email);
      }

      final emails = await store.getEmails(offset: 2, limit: 2);

      expect(emails.length, 2);
      expect(emails[0].id, 'offset-2');
      expect(emails[1].id, 'offset-3');
    });

    test('deleteEmail removes email from store', () async {
      final email = createTestEmail('delete-test');
      await store.saveEmail(email);

      await store.deleteEmail('delete-test');
      final result = await store.getEmailById('delete-test');

      expect(result, isNull);
    });

    test('saveEmail updates existing email with same id', () async {
      final original = Email(
        id: 'update-test',
        senderPubkey: 'pk',
        recipientPubkey: 'rpk',
        rawContent:
            'From: original@test.com\r\nSubject: Original Subject\r\n\r\nOriginal Body',
        createdAt: DateTime.now(),
      );

      final updated = Email(
        id: 'update-test',
        senderPubkey: 'pk',
        recipientPubkey: 'rpk',
        rawContent:
            'From: updated@test.com\r\nSubject: Updated Subject\r\n\r\nUpdated Body',
        createdAt: DateTime.now(),
      );

      await store.saveEmail(original);
      await store.saveEmail(updated);

      final emails = await store.getEmails();
      final retrieved = await store.getEmailById('update-test');

      expect(emails.length, 1);
      expect(retrieved!.mime.decodeSubject(), 'Updated Subject');
      expect(retrieved.mime.fromEmail, 'updated@test.com');
    });

    test('getEmailsByIds returns emails sorted by date descending', () async {
      final email1 = Email(
        id: 'batch-1',
        senderPubkey: 'pk',
        recipientPubkey: 'rpk',
        rawContent: 'From: a@a.com\r\nSubject: First\r\n\r\nBody',
        createdAt: DateTime.utc(2024, 1, 1),
      );
      final email2 = Email(
        id: 'batch-2',
        senderPubkey: 'pk',
        recipientPubkey: 'rpk',
        rawContent: 'From: a@a.com\r\nSubject: Second\r\n\r\nBody',
        createdAt: DateTime.utc(2024, 1, 3),
      );
      final email3 = Email(
        id: 'batch-3',
        senderPubkey: 'pk',
        recipientPubkey: 'rpk',
        rawContent: 'From: a@a.com\r\nSubject: Third\r\n\r\nBody',
        createdAt: DateTime.utc(2024, 1, 2),
      );

      await store.saveEmail(email1);
      await store.saveEmail(email2);
      await store.saveEmail(email3);

      final emails = await store.getEmailsByIds([
        'batch-1',
        'batch-3',
        'batch-2',
      ]);

      expect(emails.length, 3);
      expect(emails[0].id, 'batch-2'); // Most recent first
      expect(emails[1].id, 'batch-3');
      expect(emails[2].id, 'batch-1');
    });

    test('getEmailsByIds returns empty list for empty input', () async {
      final emails = await store.getEmailsByIds([]);

      expect(emails, isEmpty);
    });

    test('getEmailsByIds ignores non-existent IDs', () async {
      final email = Email(
        id: 'exists',
        senderPubkey: 'pk',
        recipientPubkey: 'rpk',
        rawContent: 'From: a@a.com\r\nSubject: Exists\r\n\r\nBody',
        createdAt: DateTime.utc(2024, 1, 1),
      );
      await store.saveEmail(email);

      final emails = await store.getEmailsByIds(['exists', 'does-not-exist']);

      expect(emails.length, 1);
      expect(emails[0].id, 'exists');
    });

    test('clearAll removes all emails', () async {
      await store.saveEmail(createTestEmail('email-1'));
      await store.saveEmail(createTestEmail('email-2'));
      await store.saveEmail(createTestEmail('email-3'));

      await store.clearAll();

      final emails = await store.getEmails();
      expect(emails, isEmpty);
    });
  });

  group('Exceptions', () {
    test('NostrMailException has correct message', () {
      final exception = NostrMailException('Test error');

      expect(exception.message, 'Test error');
      expect(exception.toString(), 'NostrMailException: Test error');
    });

    test('BridgeResolutionException includes domain', () {
      final exception = BridgeResolutionException('example.com');

      expect(exception.toString(), contains('example.com'));
    });

    test('RecipientResolutionException includes recipient', () {
      final exception = RecipientResolutionException('bad@email');

      expect(exception.toString(), contains('bad@email'));
    });

    test('EmailParseException includes details', () {
      final exception = EmailParseException('Invalid format');

      expect(exception.toString(), contains('Invalid format'));
    });

    test('RelayException includes details', () {
      final exception = RelayException('Connection failed');

      expect(exception.toString(), contains('Connection failed'));
    });
  });

  group('LabelStore', () {
    late LabelStore store;

    setUp(() async {
      final db = await databaseFactoryMemory.openDatabase(
        'test_label_db_${DateTime.now().millisecondsSinceEpoch}',
      );
      store = LabelStore(db);
    });

    test('saveLabel and getLabelEventId', () async {
      await store.saveLabel(
        emailId: 'email-1',
        label: 'folder:trash',
        labelEventId: 'label-event-1',
      );

      final eventId = await store.getLabelEventId('email-1', 'folder:trash');

      expect(eventId, 'label-event-1');
    });

    test('getLabelEventId returns null for non-existent label', () async {
      final eventId = await store.getLabelEventId('email-1', 'folder:trash');

      expect(eventId, isNull);
    });

    test('removeLabel deletes the label', () async {
      await store.saveLabel(
        emailId: 'email-1',
        label: 'folder:trash',
        labelEventId: 'label-event-1',
      );

      await store.removeLabel('email-1', 'folder:trash');
      final eventId = await store.getLabelEventId('email-1', 'folder:trash');

      expect(eventId, isNull);
    });

    test('getLabelsForEmail returns all labels for an email', () async {
      await store.saveLabel(
        emailId: 'email-1',
        label: 'folder:trash',
        labelEventId: 'label-event-1',
      );
      await store.saveLabel(
        emailId: 'email-1',
        label: 'state:read',
        labelEventId: 'label-event-2',
      );
      await store.saveLabel(
        emailId: 'email-1',
        label: 'flag:starred',
        labelEventId: 'label-event-3',
      );
      // Different email
      await store.saveLabel(
        emailId: 'email-2',
        label: 'folder:archive',
        labelEventId: 'label-event-4',
      );

      final labels = await store.getLabelsForEmail('email-1');

      expect(labels.length, 3);
      expect(labels, contains('folder:trash'));
      expect(labels, contains('state:read'));
      expect(labels, contains('flag:starred'));
      expect(labels, isNot(contains('folder:archive')));
    });

    test(
      'getEmailIdsWithLabel returns all emails with a specific label',
      () async {
        await store.saveLabel(
          emailId: 'email-1',
          label: 'folder:trash',
          labelEventId: 'label-event-1',
        );
        await store.saveLabel(
          emailId: 'email-2',
          label: 'folder:trash',
          labelEventId: 'label-event-2',
        );
        await store.saveLabel(
          emailId: 'email-3',
          label: 'folder:archive',
          labelEventId: 'label-event-3',
        );

        final trashedIds = await store.getEmailIdsWithLabel('folder:trash');

        expect(trashedIds.length, 2);
        expect(trashedIds, contains('email-1'));
        expect(trashedIds, contains('email-2'));
        expect(trashedIds, isNot(contains('email-3')));
      },
    );

    test('hasLabel returns true when label exists', () async {
      await store.saveLabel(
        emailId: 'email-1',
        label: 'folder:trash',
        labelEventId: 'label-event-1',
      );

      final hasTrash = await store.hasLabel('email-1', 'folder:trash');
      final hasRead = await store.hasLabel('email-1', 'state:read');

      expect(hasTrash, isTrue);
      expect(hasRead, isFalse);
    });

    test('deleteLabelsForEmail removes all labels for an email', () async {
      await store.saveLabel(
        emailId: 'email-1',
        label: 'folder:trash',
        labelEventId: 'label-event-1',
      );
      await store.saveLabel(
        emailId: 'email-1',
        label: 'state:read',
        labelEventId: 'label-event-2',
      );
      await store.saveLabel(
        emailId: 'email-2',
        label: 'folder:trash',
        labelEventId: 'label-event-3',
      );

      await store.deleteLabelsForEmail('email-1');

      final labels1 = await store.getLabelsForEmail('email-1');
      final labels2 = await store.getLabelsForEmail('email-2');

      expect(labels1, isEmpty);
      expect(labels2.length, 1);
      expect(labels2, contains('folder:trash'));
    });

    test('saveLabel updates existing label event ID', () async {
      await store.saveLabel(
        emailId: 'email-1',
        label: 'folder:trash',
        labelEventId: 'old-event-id',
      );
      await store.saveLabel(
        emailId: 'email-1',
        label: 'folder:trash',
        labelEventId: 'new-event-id',
      );

      final eventId = await store.getLabelEventId('email-1', 'folder:trash');
      final labels = await store.getLabelsForEmail('email-1');

      expect(eventId, 'new-event-id');
      expect(labels.length, 1); // Should not duplicate
    });

    test('getEmailIdsWithLabel returns empty list when no matches', () async {
      final ids = await store.getEmailIdsWithLabel('folder:trash');

      expect(ids, isEmpty);
    });

    test('getLabelsForEmail returns empty list when no labels', () async {
      final labels = await store.getLabelsForEmail('email-without-labels');

      expect(labels, isEmpty);
    });

    test('clearAll removes all labels', () async {
      await store.saveLabel(
        emailId: 'email-1',
        label: 'folder:trash',
        labelEventId: 'label-event-1',
      );
      await store.saveLabel(
        emailId: 'email-2',
        label: 'state:read',
        labelEventId: 'label-event-2',
      );

      await store.clearAll();

      final labels1 = await store.getLabelsForEmail('email-1');
      final labels2 = await store.getLabelsForEmail('email-2');
      expect(labels1, isEmpty);
      expect(labels2, isEmpty);
    });
  });

  group('GiftWrapStore', () {
    late GiftWrapStore store;

    Nip01Event createTestEvent(String id) {
      return Nip01Event(
        id: id,
        pubKey: 'test-pubkey',
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        kind: 1059,
        tags: [],
        content: 'test content',
        sig: 'test-sig',
      );
    }

    setUp(() async {
      final db = await databaseFactoryMemory.openDatabase(
        'test_gift_wrap_db_${DateTime.now().millisecondsSinceEpoch}',
      );
      store = GiftWrapStore(db);
    });

    test('save returns true for new event', () async {
      final result = await store.save(createTestEvent('event-1'));

      expect(result, isTrue);
    });

    test('save returns false for existing event', () async {
      await store.save(createTestEvent('event-1'));
      final result = await store.save(createTestEvent('event-1'));

      expect(result, isFalse);
    });

    test('save does not overwrite existing entry', () async {
      await store.save(createTestEvent('event-1'));
      await store.markProcessed('event-1');
      await store.save(createTestEvent('event-1'));

      final unprocessed = await store.getUnprocessedEvents();
      expect(unprocessed.map((e) => e.id), isNot(contains('event-1')));
    });

    test('markProcessed updates event to processed', () async {
      await store.save(createTestEvent('event-1'));
      await store.markProcessed('event-1');

      final unprocessed = await store.getUnprocessedEvents();
      expect(unprocessed.map((e) => e.id), isNot(contains('event-1')));
    });

    test('getUnprocessedEvents returns only unprocessed events', () async {
      await store.save(createTestEvent('event-1'));
      await store.save(createTestEvent('event-2'));
      await store.save(createTestEvent('event-3'));
      await store.markProcessed('event-2');

      final unprocessed = await store.getUnprocessedEvents();

      expect(unprocessed.length, 2);
      expect(unprocessed.map((e) => e.id), contains('event-1'));
      expect(unprocessed.map((e) => e.id), contains('event-3'));
      expect(unprocessed.map((e) => e.id), isNot(contains('event-2')));
    });

    test('getUnprocessedEvents respects limit', () async {
      await store.save(createTestEvent('event-1'));
      await store.save(createTestEvent('event-2'));
      await store.save(createTestEvent('event-3'));

      final unprocessed = await store.getUnprocessedEvents(limit: 2);

      expect(unprocessed.length, 2);
    });

    test('getFailedCount returns count of unprocessed events', () async {
      await store.save(createTestEvent('event-1'));
      await store.save(createTestEvent('event-2'));
      await store.save(createTestEvent('event-3'));
      await store.markProcessed('event-2');

      final count = await store.getFailedCount();

      expect(count, 2);
    });

    test('getUnprocessedEvents returns complete event data', () async {
      final event = Nip01Event(
        id: 'test-id',
        pubKey: 'test-pubkey-123',
        createdAt: 1234567890,
        kind: 1059,
        tags: [
          ['p', 'recipient'],
        ],
        content: 'encrypted content',
        sig: 'signature-123',
      );
      await store.save(event);

      final unprocessed = await store.getUnprocessedEvents();

      expect(unprocessed.length, 1);
      expect(unprocessed.first.id, 'test-id');
      expect(unprocessed.first.pubKey, 'test-pubkey-123');
      expect(unprocessed.first.createdAt, 1234567890);
      expect(unprocessed.first.kind, 1059);
      expect(unprocessed.first.tags, [
        ['p', 'recipient'],
      ]);
      expect(unprocessed.first.content, 'encrypted content');
      expect(unprocessed.first.sig, 'signature-123');
    });

    test('clearAll removes all gift wraps', () async {
      await store.save(createTestEvent('event-1'));
      await store.save(createTestEvent('event-2'));
      await store.markProcessed('event-1');

      await store.clearAll();

      final unprocessed = await store.getUnprocessedEvents();
      expect(unprocessed, isEmpty);
      expect(await store.getFailedCount(), 0);
    });
  });
}
