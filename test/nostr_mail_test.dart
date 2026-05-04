import 'dart:convert';

import 'package:enough_mail_plus/enough_mail.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:ndk/ndk.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:nostr_mail/src/services/bridge_resolver.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:nostr_mail/src/storage/email_repository.dart';
import 'package:nostr_mail/src/storage/models/email_record.dart';
import 'package:nostr_mail/src/storage/models/email_query.dart';
import 'package:nostr_mail/src/storage/gift_wrap_repository.dart';
import 'package:nostr_mail/src/storage/label_repository.dart';
import 'package:test/test.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  int dbCounter = 0;

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
    late EmailRepository repo;

    setUp(() async {
      final db = await databaseFactoryMemory.openDatabase(
        'test_email_db_${dbCounter++}',
      );
      repo = EmailRepository(db);
    });

    EmailRecord createRecord(
      String id, {
      DateTime? date,
      String? subject,
      String? from,
      String? body,
    }) {
      final effectiveDate = date ?? DateTime.now();
      final effectiveSubject = subject ?? 'Subject $id';
      final effectiveFrom = from ?? 'from@test.com';
      final effectiveBody = body ?? 'Body $id';
      final raw =
          'From: $effectiveFrom\r\nSubject: $effectiveSubject\r\n\r\n$effectiveBody';
      return EmailRecord(
        id: id,
        senderPubkey: 'pk-$id',
        recipientPubkey: 'rpk-$id',
        rawContent: raw,
        isPublic: false,
        createdAt: effectiveDate.millisecondsSinceEpoch ~/ 1000,
        date: effectiveDate.millisecondsSinceEpoch ~/ 1000,
        from: effectiveFrom,
        subject: effectiveSubject,
        bodyPlain: effectiveBody,
        searchText:
            '${effectiveFrom.toLowerCase()} ${effectiveSubject.toLowerCase()} ${effectiveBody.toLowerCase()}',
        attachmentCount: 0,
        folder: 'inbox',
        isRead: false,
        isStarred: false,
        labels: [],
        isBridged: false,
      );
    }

    test('saveEmail and getEmailById', () async {
      final email = createRecord('save-test');

      await repo.save(email);
      final retrieved = (await repo.getById('save-test'))?.toEmail();

      expect(retrieved, isNotNull);
      expect(retrieved!.id, 'save-test');
      expect(retrieved.mime.decodeSubject(), 'Subject save-test');
    });

    test('getEmailById returns null for non-existent email', () async {
      final result = (await repo.getById('non-existent'))?.toEmail();

      expect(result, isNull);
    });

    test('getEmails returns all emails sorted by date descending', () async {
      final email1 = createRecord(
        'e1',
        date: DateTime.utc(2024, 1, 1),
        subject: 'First',
        from: 'a@a.com',
      );
      final email2 = createRecord(
        'e2',
        date: DateTime.utc(2024, 1, 3),
        subject: 'Second',
        from: 'a@a.com',
      );
      final email3 = createRecord(
        'e3',
        date: DateTime.utc(2024, 1, 2),
        subject: 'Third',
        from: 'a@a.com',
      );

      await repo.save(email1);
      await repo.save(email2);
      await repo.save(email3);

      final emails = (await repo.query(
        EmailQuery(),
      )).items.map((r) => r.toEmail()).toList();

      expect(emails.length, 3);
      expect(emails[0].id, 'e2'); // Most recent first
      expect(emails[1].id, 'e3');
      expect(emails[2].id, 'e1');
    });

    test('getEmails respects limit parameter', () async {
      for (var i = 0; i < 5; i++) {
        await repo.save(createRecord('limit-$i'));
      }

      final emails = (await repo.query(
        EmailQuery(limit: 3),
      )).items.map((r) => r.toEmail()).toList();

      expect(emails.length, 3);
    });

    test('getEmails respects offset parameter', () async {
      for (var i = 0; i < 5; i++) {
        final email = createRecord(
          'offset-$i',
          date: DateTime.utc(2024, 1, 5 - i),
          subject: 'Subject $i',
          from: 'a@a.com',
        );
        await repo.save(email);
      }

      final emails = (await repo.query(
        EmailQuery(offset: 2, limit: 2),
      )).items.map((r) => r.toEmail()).toList();

      expect(emails.length, 2);
      expect(emails[0].id, 'offset-2');
      expect(emails[1].id, 'offset-3');
    });

    test('deleteEmail removes email from store', () async {
      final email = createRecord('delete-test');
      await repo.save(email);

      await repo.delete('delete-test');
      final result = (await repo.getById('delete-test'))?.toEmail();

      expect(result, isNull);
    });

    test('saveEmail updates existing email with same id', () async {
      final original = createRecord(
        'update-test',
        from: 'original@test.com',
        subject: 'Original Subject',
        body: 'Original Body',
      );
      final updated = createRecord(
        'update-test',
        from: 'updated@test.com',
        subject: 'Updated Subject',
        body: 'Updated Body',
      );

      await repo.save(original);
      await repo.save(updated);

      final emails = (await repo.query(
        EmailQuery(),
      )).items.map((r) => r.toEmail()).toList();
      final retrieved = (await repo.getById('update-test'))?.toEmail();

      expect(emails.length, 1);
      expect(retrieved!.mime.decodeSubject(), 'Updated Subject');
      expect(retrieved.mime.fromEmail, 'updated@test.com');
    });

    test('getEmailsByIds returns emails sorted by date descending', () async {
      final email1 = createRecord(
        'batch-1',
        date: DateTime.utc(2024, 1, 1),
        subject: 'First',
        from: 'a@a.com',
      );
      final email2 = createRecord(
        'batch-2',
        date: DateTime.utc(2024, 1, 3),
        subject: 'Second',
        from: 'a@a.com',
      );
      final email3 = createRecord(
        'batch-3',
        date: DateTime.utc(2024, 1, 2),
        subject: 'Third',
        from: 'a@a.com',
      );

      await repo.save(email1);
      await repo.save(email2);
      await repo.save(email3);

      final emails = (await repo.getByIds([
        'batch-1',
        'batch-3',
        'batch-2',
      ])).map((r) => r.toEmail()).toList();

      expect(emails.length, 3);
      expect(emails[0].id, 'batch-2'); // Most recent first
      expect(emails[1].id, 'batch-3');
      expect(emails[2].id, 'batch-1');
    });

    test('getEmailsByIds returns empty list for empty input', () async {
      final emails = (await repo.getByIds([])).map((r) => r.toEmail()).toList();

      expect(emails, isEmpty);
    });

    test('getEmailsByIds ignores non-existent IDs', () async {
      final email = createRecord(
        'exists',
        date: DateTime.utc(2024, 1, 1),
        subject: 'Exists',
        from: 'a@a.com',
      );
      await repo.save(email);

      final emails = (await repo.getByIds([
        'exists',
        'does-not-exist',
      ])).map((r) => r.toEmail()).toList();

      expect(emails.length, 1);
      expect(emails[0].id, 'exists');
    });

    test('clearAll removes all emails', () async {
      await repo.save(createRecord('email-1'));
      await repo.save(createRecord('email-2'));
      await repo.save(createRecord('email-3'));

      await repo.clearAll();

      final emails = (await repo.query(
        EmailQuery(),
      )).items.map((r) => r.toEmail()).toList();
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
    late LabelRepository repo;

    setUp(() async {
      final db = await databaseFactoryMemory.openDatabase(
        'test_label_db_${dbCounter++}',
      );
      repo = LabelRepository(db);
    });

    test('saveLabel and getLabelEventId', () async {
      await repo.saveLabel(
        emailId: 'email-1',
        label: 'folder:trash',
        labelEventId: 'label-event-1',
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      final eventId = await repo.getLabelEventId('email-1', 'folder:trash');

      expect(eventId, 'label-event-1');
    });

    test('getLabelEventId returns null for non-existent label', () async {
      final eventId = await repo.getLabelEventId('email-1', 'folder:trash');

      expect(eventId, isNull);
    });

    test('removeLabel deletes the label', () async {
      await repo.saveLabel(
        emailId: 'email-1',
        label: 'folder:trash',
        labelEventId: 'label-event-1',
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      await repo.removeLabel('email-1', 'folder:trash');
      final eventId = await repo.getLabelEventId('email-1', 'folder:trash');

      expect(eventId, isNull);
    });

    test('getLabelsForEmail returns all labels for an email', () async {
      await repo.saveLabel(
        emailId: 'email-1',
        label: 'folder:trash',
        labelEventId: 'label-event-1',
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
      await repo.saveLabel(
        emailId: 'email-1',
        label: 'state:read',
        labelEventId: 'label-event-2',
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
      await repo.saveLabel(
        emailId: 'email-1',
        label: 'flag:starred',
        labelEventId: 'label-event-3',
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
      // Different email
      await repo.saveLabel(
        emailId: 'email-2',
        label: 'folder:archive',
        labelEventId: 'label-event-4',
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      final labels = await repo.getLabelsForEmail('email-1');

      expect(labels.length, 3);
      expect(labels, contains('folder:trash'));
      expect(labels, contains('state:read'));
      expect(labels, contains('flag:starred'));
      expect(labels, isNot(contains('folder:archive')));
    });

    test(
      'getEmailIdsWithLabel returns all emails with a specific label',
      () async {
        await repo.saveLabel(
          emailId: 'email-1',
          label: 'folder:trash',
          labelEventId: 'label-event-1',
          timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );
        await repo.saveLabel(
          emailId: 'email-2',
          label: 'folder:trash',
          labelEventId: 'label-event-2',
          timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );
        await repo.saveLabel(
          emailId: 'email-3',
          label: 'folder:archive',
          labelEventId: 'label-event-3',
          timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );

        final trashedIds = await repo.getEmailIdsWithLabel('folder:trash');

        expect(trashedIds.length, 2);
        expect(trashedIds, contains('email-1'));
        expect(trashedIds, contains('email-2'));
        expect(trashedIds, isNot(contains('email-3')));
      },
    );

    test('hasLabel returns true when label exists', () async {
      await repo.saveLabel(
        emailId: 'email-1',
        label: 'folder:trash',
        labelEventId: 'label-event-1',
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      final hasTrash = await repo.hasLabel('email-1', 'folder:trash');
      final hasRead = await repo.hasLabel('email-1', 'state:read');

      expect(hasTrash, isTrue);
      expect(hasRead, isFalse);
    });

    test('deleteLabelsForEmail removes all labels for an email', () async {
      await repo.saveLabel(
        emailId: 'email-1',
        label: 'folder:trash',
        labelEventId: 'label-event-1',
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
      await repo.saveLabel(
        emailId: 'email-1',
        label: 'state:read',
        labelEventId: 'label-event-2',
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
      await repo.saveLabel(
        emailId: 'email-2',
        label: 'folder:trash',
        labelEventId: 'label-event-3',
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      await repo.deleteLabelsForEmail('email-1');

      final labels1 = await repo.getLabelsForEmail('email-1');
      final labels2 = await repo.getLabelsForEmail('email-2');

      expect(labels1, isEmpty);
      expect(labels2.length, 1);
      expect(labels2, contains('folder:trash'));
    });

    test('saveLabel updates existing label event ID', () async {
      await repo.saveLabel(
        emailId: 'email-1',
        label: 'folder:trash',
        labelEventId: 'old-event-id',
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
      await repo.saveLabel(
        emailId: 'email-1',
        label: 'folder:trash',
        labelEventId: 'new-event-id',
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      final eventId = await repo.getLabelEventId('email-1', 'folder:trash');
      final labels = await repo.getLabelsForEmail('email-1');

      expect(eventId, 'new-event-id');
      expect(labels.length, 1); // Should not duplicate
    });

    // TODO this test fail when run after other tests, need to investigate why
    test('getEmailIdsWithLabel returns empty list when no matches', () async {
      final ids = await repo.getEmailIdsWithLabel('folder:trash');

      expect(ids, isEmpty);
    });

    test('getLabelsForEmail returns empty list when no labels', () async {
      final labels = await repo.getLabelsForEmail('email-without-labels');

      expect(labels, isEmpty);
    });

    test('clearAll removes all labels', () async {
      await repo.saveLabel(
        emailId: 'email-1',
        label: 'folder:trash',
        labelEventId: 'label-event-1',
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
      await repo.saveLabel(
        emailId: 'email-2',
        label: 'state:read',
        labelEventId: 'label-event-2',
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      await repo.clearAll();

      final labels1 = await repo.getLabelsForEmail('email-1');
      final labels2 = await repo.getLabelsForEmail('email-2');
      expect(labels1, isEmpty);
      expect(labels2, isEmpty);
    });
  });

  group('GiftWrapStore', () {
    late GiftWrapRepository repo;

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
        'test_gift_wrap_db_${dbCounter++}',
      );
      repo = GiftWrapRepository(db);
    });

    test('save returns true for new event', () async {
      final result = await repo.save(createTestEvent('event-1'));

      expect(result, isTrue);
    });

    test('save returns false for existing event', () async {
      await repo.save(createTestEvent('event-1'));
      final result = await repo.save(createTestEvent('event-1'));

      expect(result, isFalse);
    });

    test('save does not overwrite existing entry', () async {
      await repo.save(createTestEvent('event-1'));
      await repo.markProcessed('event-1');
      await repo.save(createTestEvent('event-1'));

      final unprocessed = await repo.getUnprocessedEvents();
      expect(unprocessed.map((e) => e.id), isNot(contains('event-1')));
    });

    test('markProcessed updates event to processed', () async {
      await repo.save(createTestEvent('event-1'));
      await repo.markProcessed('event-1');

      final unprocessed = await repo.getUnprocessedEvents();
      expect(unprocessed.map((e) => e.id), isNot(contains('event-1')));
    });

    test('getUnprocessedEvents returns only unprocessed events', () async {
      await repo.save(createTestEvent('event-1'));
      await repo.save(createTestEvent('event-2'));
      await repo.save(createTestEvent('event-3'));
      await repo.markProcessed('event-2');

      final unprocessed = await repo.getUnprocessedEvents();

      expect(unprocessed.length, 2);
      expect(unprocessed.map((e) => e.id), contains('event-1'));
      expect(unprocessed.map((e) => e.id), contains('event-3'));
      expect(unprocessed.map((e) => e.id), isNot(contains('event-2')));
    });

    test('getUnprocessedEvents respects limit', () async {
      await repo.save(createTestEvent('event-1'));
      await repo.save(createTestEvent('event-2'));
      await repo.save(createTestEvent('event-3'));

      final unprocessed = await repo.getUnprocessedEvents(limit: 2);

      expect(unprocessed.length, 2);
    });

    test('getFailedCount returns count of unprocessed events', () async {
      await repo.save(createTestEvent('event-1'));
      await repo.save(createTestEvent('event-2'));
      await repo.save(createTestEvent('event-3'));
      await repo.markProcessed('event-2');

      final count = await repo.getFailedCount();

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
      await repo.save(event);

      final unprocessed = await repo.getUnprocessedEvents();

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
      await repo.save(createTestEvent('event-1'));
      await repo.save(createTestEvent('event-2'));
      await repo.markProcessed('event-1');

      await repo.clearAll();

      final unprocessed = await repo.getUnprocessedEvents();
      expect(unprocessed, isEmpty);
      expect(await repo.getFailedCount(), 0);
    });
  });
}
