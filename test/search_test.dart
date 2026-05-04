import 'package:sembast/sembast_memory.dart';
import 'package:nostr_mail/src/storage/email_repository.dart';
import 'package:nostr_mail/src/storage/models/email_record.dart';
import 'package:nostr_mail/src/storage/models/email_query.dart';
import 'package:test/test.dart';

void main() {
  group('EmailStore Search', () {
    late EmailRepository repo;

    setUp(() async {
      final db = await databaseFactoryMemory.openDatabase(
        'test_search_db_${DateTime.now().millisecondsSinceEpoch}',
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
      final effectiveSubject = subject ?? 'Subject';
      final effectiveFrom = from ?? 'test@test.com';
      final effectiveBody = body ?? 'Body text';
      final raw =
          'From: $effectiveFrom\r\nSubject: $effectiveSubject\r\n\r\n$effectiveBody';
      return EmailRecord(
        id: id,
        senderPubkey: 'pk',
        recipientPubkey: 'rpk',
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

    test('searchEmails filters by subject, body, or from', () async {
      final email1 = createRecord(
        's1',
        date: DateTime.utc(2024, 1, 1),
        subject: 'Meeting tomorrow',
        from: 'alice@test.com',
        body: 'Let us discuss the project.',
      );
      final email2 = createRecord(
        's2',
        date: DateTime.utc(2024, 1, 2),
        subject: 'Vacation',
        from: 'charlie@test.com',
        body: 'I am going to the beach.',
      );
      final email3 = createRecord(
        's3',
        date: DateTime.utc(2024, 1, 3),
        subject: 'Project update',
        from: 'alice@test.com',
        body: 'The Meeting was good.',
      );

      await repo.save(email1);
      await repo.save(email2);
      await repo.save(email3);

      // Search by subject (case insensitive)
      var results = (await repo.search(
        'meeting',
      )).map((r) => r.toEmail()).toList();
      expect(results.length, 2);
      var ids = results.map((e) => e.id).toList();
      expect(ids, contains('s1'));
      expect(ids, contains('s3'));

      // Search by body
      results = (await repo.search('beach')).map((r) => r.toEmail()).toList();
      expect(results.length, 1);
      expect(results.first.id, 's2');

      // Search by from
      results = (await repo.search('charlie')).map((r) => r.toEmail()).toList();
      expect(results.length, 1);
      expect(results.first.id, 's2');

      // No results
      results = (await repo.search(
        'nonexistent',
      )).map((r) => r.toEmail()).toList();
      expect(results, isEmpty);
    });

    test('searchEmails respects limit and offset', () async {
      for (var i = 0; i < 5; i++) {
        await repo.save(
          createRecord(
            'search-$i',
            date: DateTime.utc(2024, 1, 10 - i),
            subject: 'Search match $i',
            from: 'test@test.com',
          ),
        );
      }

      final results = (await repo.query(
        EmailQuery(search: 'match', limit: 2, offset: 1),
      )).items.map((r) => r.toEmail()).toList();

      expect(results.length, 2);
      expect(results[0].id, 'search-1');
      expect(results[1].id, 'search-2');
    });
  });
}
