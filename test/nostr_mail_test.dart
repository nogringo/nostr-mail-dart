import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:nostr_mail/src/services/bridge_resolver.dart';
import 'package:nostr_mail/src/services/email_parser.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:nostr_mail/src/storage/email_store.dart';
import 'package:nostr_mail/src/storage/gift_wrap_store.dart';
import 'package:nostr_mail/src/storage/label_store.dart';
import 'package:test/test.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  group('Email', () {
    test('toJson serializes correctly', () {
      final email = Email(
        id: 'test-id',
        from: 'sender@example.com',
        to: 'recipient@example.com',
        subject: 'Test Subject',
        body: 'Test body content',
        date: DateTime.utc(2024, 1, 15, 10, 30),
        senderPubkey: 'abc123pubkey',
        recipientPubkey: 'recipient123pubkey',
        rawContent: 'raw email content',
      );

      final json = email.toJson();

      expect(json['id'], 'test-id');
      expect(json['from'], 'sender@example.com');
      expect(json['to'], 'recipient@example.com');
      expect(json['subject'], 'Test Subject');
      expect(json['body'], 'Test body content');
      expect(json['date'], '2024-01-15T10:30:00.000Z');
      expect(json['senderPubkey'], 'abc123pubkey');
      expect(json['recipientPubkey'], 'recipient123pubkey');
      expect(json['rawContent'], 'raw email content');
    });

    test('fromJson deserializes correctly', () {
      final json = {
        'id': 'test-id',
        'from': 'sender@example.com',
        'to': 'recipient@example.com',
        'subject': 'Test Subject',
        'body': 'Test body content',
        'date': '2024-01-15T10:30:00.000Z',
        'senderPubkey': 'abc123pubkey',
        'recipientPubkey': 'recipient123pubkey',
        'rawContent': 'raw email content',
      };

      final email = Email.fromJson(json);

      expect(email.id, 'test-id');
      expect(email.from, 'sender@example.com');
      expect(email.to, 'recipient@example.com');
      expect(email.subject, 'Test Subject');
      expect(email.body, 'Test body content');
      expect(email.date, DateTime.utc(2024, 1, 15, 10, 30));
      expect(email.senderPubkey, 'abc123pubkey');
      expect(email.recipientPubkey, 'recipient123pubkey');
      expect(email.rawContent, 'raw email content');
    });

    test('roundtrip serialization preserves data', () {
      final original = Email(
        id: 'roundtrip-id',
        from: 'test@test.com',
        to: 'dest@dest.com',
        subject: 'Roundtrip Test',
        body: 'Body with special chars: é à ü',
        date: DateTime.utc(2024, 6, 20, 14, 45, 30),
        senderPubkey: 'pubkey123',
        recipientPubkey: 'recipient456',
        rawContent: 'raw content here',
      );

      final restored = Email.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.from, original.from);
      expect(restored.to, original.to);
      expect(restored.subject, original.subject);
      expect(restored.body, original.body);
      expect(restored.date, original.date);
      expect(restored.senderPubkey, original.senderPubkey);
      expect(restored.recipientPubkey, original.recipientPubkey);
      expect(restored.rawContent, original.rawContent);
    });

    test('equality is based on id', () {
      final email1 = Email(
        id: 'same-id',
        from: 'a@a.com',
        to: 'b@b.com',
        subject: 'Subject 1',
        body: 'Body 1',
        date: DateTime.now(),
        senderPubkey: 'pk1',
        recipientPubkey: 'rpk1',
        rawContent: 'raw1',
      );

      final email2 = Email(
        id: 'same-id',
        from: 'different@email.com',
        to: 'other@email.com',
        subject: 'Different Subject',
        body: 'Different Body',
        date: DateTime.now(),
        senderPubkey: 'pk2',
        recipientPubkey: 'rpk2',
        rawContent: 'raw2',
      );

      final email3 = Email(
        id: 'different-id',
        from: 'a@a.com',
        to: 'b@b.com',
        subject: 'Subject 1',
        body: 'Body 1',
        date: DateTime.now(),
        senderPubkey: 'pk1',
        recipientPubkey: 'rpk1',
        rawContent: 'raw1',
      );

      expect(email1, equals(email2));
      expect(email1, isNot(equals(email3)));
      expect(email1.hashCode, equals(email2.hashCode));
    });

    test('toString returns readable format', () {
      final email = Email(
        id: 'test-id',
        from: 'sender@test.com',
        to: 'recipient@test.com',
        subject: 'Hello World',
        body: 'Body',
        date: DateTime.now(),
        senderPubkey: 'pk',
        recipientPubkey: 'rpk',
        rawContent: 'raw',
      );

      final str = email.toString();

      expect(str, contains('test-id'));
      expect(str, contains('sender@test.com'));
      expect(str, contains('recipient@test.com'));
      expect(str, contains('Hello World'));
    });
  });

  group('EmailParser', () {
    late EmailParser parser;

    setUp(() {
      parser = EmailParser();
    });

    test('build creates valid RFC 2822 email', () {
      final rawContent = parser.build(
        from: 'sender@nostr.com',
        to: 'recipient@example.com',
        subject: 'Test Email',
        body: 'Hello, this is a test email.',
      );

      expect(rawContent, contains('From:'));
      expect(rawContent, contains('To:'));
      expect(rawContent, contains('Subject: Test Email'));
      expect(rawContent, contains('Hello, this is a test email.'));
    });

    test('parse extracts email fields from RFC 2822', () {
      final rawContent = parser.build(
        from: 'alice@nostr.com',
        to: 'bob@example.com',
        subject: 'Important Message',
        body: 'This is the message body.',
      );

      final email = parser.parse(
        rawContent: rawContent,
        eventId: 'event-123',
        senderPubkey: 'sender-pubkey-abc',
        recipientPubkey: 'recipient-pubkey-xyz',
      );

      expect(email.id, 'event-123');
      expect(email.from, 'alice@nostr.com');
      expect(email.to, 'bob@example.com');
      expect(email.subject, 'Important Message');
      expect(email.body, contains('This is the message body.'));
      expect(email.senderPubkey, 'sender-pubkey-abc');
      expect(email.recipientPubkey, 'recipient-pubkey-xyz');
      expect(email.rawContent, rawContent);
    });

    test('parse handles special characters in subject', () {
      final rawContent = parser.build(
        from: 'test@test.com',
        to: 'dest@dest.com',
        subject: 'Special: émojis 🎉 and symbols!',
        body: 'Body text',
      );

      final email = parser.parse(
        rawContent: rawContent,
        eventId: 'id',
        senderPubkey: 'pk',
        recipientPubkey: 'rpk',
      );

      expect(email.subject, contains('Special'));
    });

    test('parse handles minimal/empty content gracefully', () {
      // The parser is lenient and returns empty fields for invalid content
      final email = parser.parse(
        rawContent: 'not a valid email',
        eventId: 'id',
        senderPubkey: 'pk',
        recipientPubkey: 'rpk',
      );

      expect(email.id, 'id');
      expect(email.senderPubkey, 'pk');
      expect(email.recipientPubkey, 'rpk');
      // Fields are empty but no exception is thrown
      expect(email.from, isEmpty);
      expect(email.to, isEmpty);
    });

    test('roundtrip build and parse preserves data', () {
      const from = 'roundtrip@sender.com';
      const to = 'roundtrip@recipient.com';
      const subject = 'Roundtrip Subject';
      const body = 'Roundtrip body content.';

      final rawContent = parser.build(
        from: from,
        to: to,
        subject: subject,
        body: body,
      );

      final email = parser.parse(
        rawContent: rawContent,
        eventId: 'rt-id',
        senderPubkey: 'rt-pk',
        recipientPubkey: 'rt-rpk',
      );

      expect(email.from, from);
      expect(email.to, to);
      expect(email.subject, subject);
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

    setUpAll(() {
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

    Email createTestEmail(String id) => Email(
      id: id,
      from: 'from@test.com',
      to: 'to@test.com',
      subject: 'Subject $id',
      body: 'Body $id',
      date: DateTime.now(),
      senderPubkey: 'pk-$id',
      recipientPubkey: 'rpk-$id',
      rawContent: 'raw-$id',
    );

    test('saveEmail and getEmailById', () async {
      final email = createTestEmail('save-test');

      await store.saveEmail(email);
      final retrieved = await store.getEmailById('save-test');

      expect(retrieved, isNotNull);
      expect(retrieved!.id, 'save-test');
      expect(retrieved.subject, 'Subject save-test');
    });

    test('getEmailById returns null for non-existent email', () async {
      final result = await store.getEmailById('non-existent');

      expect(result, isNull);
    });

    test('getEmails returns all emails sorted by date descending', () async {
      final email1 = Email(
        id: 'e1',
        from: 'a@a.com',
        to: 'b@b.com',
        subject: 'First',
        body: 'Body',
        date: DateTime.utc(2024, 1, 1),
        senderPubkey: 'pk',
        recipientPubkey: 'rpk',
        rawContent: 'raw',
      );
      final email2 = Email(
        id: 'e2',
        from: 'a@a.com',
        to: 'b@b.com',
        subject: 'Second',
        body: 'Body',
        date: DateTime.utc(2024, 1, 3),
        senderPubkey: 'pk',
        recipientPubkey: 'rpk',
        rawContent: 'raw',
      );
      final email3 = Email(
        id: 'e3',
        from: 'a@a.com',
        to: 'b@b.com',
        subject: 'Third',
        body: 'Body',
        date: DateTime.utc(2024, 1, 2),
        senderPubkey: 'pk',
        recipientPubkey: 'rpk',
        rawContent: 'raw',
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
          from: 'a@a.com',
          to: 'b@b.com',
          subject: 'Subject $i',
          body: 'Body',
          date: DateTime.utc(2024, 1, 5 - i), // Descending dates
          senderPubkey: 'pk',
          recipientPubkey: 'rpk',
          rawContent: 'raw',
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
        from: 'original@test.com',
        to: 'to@test.com',
        subject: 'Original Subject',
        body: 'Original Body',
        date: DateTime.now(),
        senderPubkey: 'pk',
        recipientPubkey: 'rpk',
        rawContent: 'raw',
      );

      final updated = Email(
        id: 'update-test',
        from: 'updated@test.com',
        to: 'to@test.com',
        subject: 'Updated Subject',
        body: 'Updated Body',
        date: DateTime.now(),
        senderPubkey: 'pk',
        recipientPubkey: 'rpk',
        rawContent: 'raw',
      );

      await store.saveEmail(original);
      await store.saveEmail(updated);

      final emails = await store.getEmails();
      final retrieved = await store.getEmailById('update-test');

      expect(emails.length, 1);
      expect(retrieved!.subject, 'Updated Subject');
      expect(retrieved.from, 'updated@test.com');
    });

    test('getEmailsByIds returns emails sorted by date descending', () async {
      final email1 = Email(
        id: 'batch-1',
        from: 'a@a.com',
        to: 'b@b.com',
        subject: 'First',
        body: 'Body',
        date: DateTime.utc(2024, 1, 1),
        senderPubkey: 'pk',
        recipientPubkey: 'rpk',
        rawContent: 'raw',
      );
      final email2 = Email(
        id: 'batch-2',
        from: 'a@a.com',
        to: 'b@b.com',
        subject: 'Second',
        body: 'Body',
        date: DateTime.utc(2024, 1, 3),
        senderPubkey: 'pk',
        recipientPubkey: 'rpk',
        rawContent: 'raw',
      );
      final email3 = Email(
        id: 'batch-3',
        from: 'a@a.com',
        to: 'b@b.com',
        subject: 'Third',
        body: 'Body',
        date: DateTime.utc(2024, 1, 2),
        senderPubkey: 'pk',
        recipientPubkey: 'rpk',
        rawContent: 'raw',
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
        from: 'a@a.com',
        to: 'b@b.com',
        subject: 'Exists',
        body: 'Body',
        date: DateTime.utc(2024, 1, 1),
        senderPubkey: 'pk',
        recipientPubkey: 'rpk',
        rawContent: 'raw',
      );
      await store.saveEmail(email);

      final emails = await store.getEmailsByIds(['exists', 'does-not-exist']);

      expect(emails.length, 1);
      expect(emails[0].id, 'exists');
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
  });

  group('GiftWrapStore', () {
    late GiftWrapStore store;

    setUp(() async {
      final db = await databaseFactoryMemory.openDatabase(
        'test_gift_wrap_db_${DateTime.now().millisecondsSinceEpoch}',
      );
      store = GiftWrapStore(db);
    });

    test('isProcessed returns false for unknown event', () async {
      final result = await store.isProcessed('unknown-id');

      expect(result, isFalse);
    });

    test('isKnown returns false for unknown event', () async {
      final result = await store.isKnown('unknown-id');

      expect(result, isFalse);
    });

    test('markFetched adds event as unprocessed', () async {
      await store.markFetched('event-1');

      expect(await store.isKnown('event-1'), isTrue);
      expect(await store.isProcessed('event-1'), isFalse);
    });

    test('markFetched does not overwrite existing entry', () async {
      await store.markFetched('event-1');
      await store.markProcessed('event-1');
      await store.markFetched('event-1'); // Should not reset to unprocessed

      expect(await store.isProcessed('event-1'), isTrue);
    });

    test('markProcessed updates event to processed', () async {
      await store.markFetched('event-1');
      await store.markProcessed('event-1');

      expect(await store.isProcessed('event-1'), isTrue);
    });

    test('getUnprocessed returns only unprocessed events', () async {
      await store.markFetched('event-1');
      await store.markFetched('event-2');
      await store.markFetched('event-3');
      await store.markProcessed('event-2');

      final unprocessed = await store.getUnprocessed();

      expect(unprocessed.length, 2);
      expect(unprocessed, contains('event-1'));
      expect(unprocessed, contains('event-3'));
      expect(unprocessed, isNot(contains('event-2')));
    });

    test('getUnprocessed respects limit', () async {
      await store.markFetched('event-1');
      await store.markFetched('event-2');
      await store.markFetched('event-3');

      final unprocessed = await store.getUnprocessed(limit: 2);

      expect(unprocessed.length, 2);
    });

    test('markFetchedBatch adds multiple events', () async {
      await store.markFetchedBatch(['event-1', 'event-2', 'event-3']);

      expect(await store.isKnown('event-1'), isTrue);
      expect(await store.isKnown('event-2'), isTrue);
      expect(await store.isKnown('event-3'), isTrue);
      expect(await store.isProcessed('event-1'), isFalse);
    });

    test('markProcessedBatch updates multiple events', () async {
      await store.markFetchedBatch(['event-1', 'event-2', 'event-3']);
      await store.markProcessedBatch(['event-1', 'event-3']);

      expect(await store.isProcessed('event-1'), isTrue);
      expect(await store.isProcessed('event-2'), isFalse);
      expect(await store.isProcessed('event-3'), isTrue);
    });
  });
}
