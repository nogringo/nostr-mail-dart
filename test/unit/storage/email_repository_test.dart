import 'package:nostr_mail/src/storage/email_repository.dart';
import 'package:nostr_mail/src/storage/models/email_query.dart';
import 'package:nostr_mail/src/storage/models/email_record.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:test/test.dart';

void main() {
  group('EmailRepository', () {
    const rpk = 'rpk';
    late EmailRepository repo;

    setUp(() async {
      final db = await databaseFactoryMemory.openDatabase(
        'test_email_${DateTime.now().microsecondsSinceEpoch}',
      );
      repo = EmailRepository(db);
    });

    EmailRecord makeRecord(
      String id, {
      String folder = 'inbox',
      bool isRead = false,
      bool isStarred = false,
      int attachmentCount = 0,
      String? searchText,
      DateTime? date,
      String subject = 'sub',
      String from = 'a@b.com',
      String body = 'body',
    }) {
      final ts = (date ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
      return EmailRecord(
        id: id,
        senderPubkey: 'pk-$id',
        recipientPubkey: rpk,
        rawContent: 'From: $from\r\nSubject: $subject\r\n\r\n$body',
        isPublic: false,
        createdAt: ts,
        date: ts,
        from: from,
        subject: subject,
        bodyPlain: body,
        searchText:
            searchText ??
            '${from.toLowerCase()} ${subject.toLowerCase()} ${body.toLowerCase()}',
        attachmentCount: attachmentCount,
        folder: folder,
        isRead: isRead,
        isStarred: isStarred,
        labels: const [],
        isBridged: false,
      );
    }

    group('save / get', () {
      test('save and getById', () async {
        await repo.save(makeRecord('e1', subject: 'Hello'));
        final found = await repo.getById('e1', recipientPubkey: rpk);

        expect(found, isNotNull);
        expect(found!.id, 'e1');
        expect(found.subject, 'Hello');
      });

      test('getById returns null for non-existent record', () async {
        expect(
          await repo.getById('non-existent', recipientPubkey: rpk),
          isNull,
        );
      });

      test('save updates an existing record with the same id', () async {
        await repo.save(makeRecord('update', subject: 'Original'));
        await repo.save(makeRecord('update', subject: 'Updated'));

        final all = await repo.query(EmailQuery(recipientPubkey: rpk));
        expect(all.items.length, 1);

        final retrieved = await repo.getById('update', recipientPubkey: rpk);
        expect(retrieved!.subject, 'Updated');
      });
    });

    group('query', () {
      test('returns records sorted by date descending', () async {
        await repo.save(
          makeRecord('e1', date: DateTime.utc(2024, 1, 1), subject: 'First'),
        );
        await repo.save(
          makeRecord('e2', date: DateTime.utc(2024, 1, 3), subject: 'Second'),
        );
        await repo.save(
          makeRecord('e3', date: DateTime.utc(2024, 1, 2), subject: 'Third'),
        );

        final result = await repo.query(EmailQuery(recipientPubkey: rpk));
        expect(result.items.map((e) => e.id), ['e2', 'e3', 'e1']);
      });

      test('filters by folder', () async {
        await repo.save(makeRecord('e1', folder: 'inbox'));
        await repo.save(makeRecord('e2', folder: 'sent'));
        await repo.save(makeRecord('e3', folder: 'trash'));

        final result = await repo.query(
          const EmailQuery(recipientPubkey: rpk, folder: 'inbox'),
        );
        expect(result.items.length, 1);
        expect(result.items.first.id, 'e1');
      });

      test('filters by isRead', () async {
        await repo.save(makeRecord('e1', isRead: true));
        await repo.save(makeRecord('e2', isRead: false));

        final result = await repo.query(
          const EmailQuery(recipientPubkey: rpk, isRead: true),
        );
        expect(result.items.length, 1);
        expect(result.items.first.id, 'e1');
      });

      test('filters by hasAttachments', () async {
        await repo.save(makeRecord('e1', attachmentCount: 2));
        await repo.save(makeRecord('e2', attachmentCount: 0));

        final result = await repo.query(
          const EmailQuery(recipientPubkey: rpk, hasAttachments: true),
        );
        expect(result.items.length, 1);
        expect(result.items.first.id, 'e1');
      });

      test('combines filters', () async {
        await repo.save(
          makeRecord('e1', folder: 'inbox', isRead: false, isStarred: true),
        );
        await repo.save(
          makeRecord('e2', folder: 'inbox', isRead: true, isStarred: true),
        );
        await repo.save(
          makeRecord('e3', folder: 'sent', isRead: false, isStarred: true),
        );

        final result = await repo.query(
          const EmailQuery(
            recipientPubkey: rpk,
            folder: 'inbox',
            isRead: false,
            isStarred: true,
          ),
        );
        expect(result.items.length, 1);
        expect(result.items.first.id, 'e1');
      });

      test('paginates with limit and offset', () async {
        for (var i = 0; i < 5; i++) {
          await repo.save(
            makeRecord('e$i', date: DateTime.utc(2024, 1, 5 - i)),
          );
        }

        final page1 = await repo.query(
          const EmailQuery(recipientPubkey: rpk, limit: 2, offset: 0),
        );
        expect(page1.items.length, 2);
        expect(page1.total, 5);
        expect(page1.hasMore, true);

        final page2 = await repo.query(
          const EmailQuery(recipientPubkey: rpk, limit: 2, offset: 2),
        );
        expect(page2.items.length, 2);
        expect(page2.hasMore, true);

        final page3 = await repo.query(
          const EmailQuery(recipientPubkey: rpk, limit: 2, offset: 4),
        );
        expect(page3.items.length, 1);
        expect(page3.hasMore, false);
      });
    });

    group('search', () {
      test('finds by subject, body, or from (case insensitive)', () async {
        await repo.save(
          makeRecord(
            's1',
            date: DateTime.utc(2024, 1, 1),
            subject: 'Meeting tomorrow',
            from: 'alice@test.com',
            body: 'Let us discuss the project.',
          ),
        );
        await repo.save(
          makeRecord(
            's2',
            date: DateTime.utc(2024, 1, 2),
            subject: 'Vacation',
            from: 'charlie@test.com',
            body: 'I am going to the beach.',
          ),
        );
        await repo.save(
          makeRecord(
            's3',
            date: DateTime.utc(2024, 1, 3),
            subject: 'Project update',
            from: 'alice@test.com',
            body: 'The Meeting was good.',
          ),
        );

        final bySubject = await repo.search('meeting', recipientPubkey: rpk);
        expect(bySubject.map((e) => e.id), containsAll(['s1', 's3']));

        final byBody = await repo.search('beach', recipientPubkey: rpk);
        expect(byBody.single.id, 's2');

        final byFrom = await repo.search('charlie', recipientPubkey: rpk);
        expect(byFrom.single.id, 's2');

        expect(await repo.search('nonexistent', recipientPubkey: rpk), isEmpty);
      });

      test('respects limit and offset via EmailQuery.search', () async {
        for (var i = 0; i < 5; i++) {
          await repo.save(
            makeRecord(
              'search-$i',
              date: DateTime.utc(2024, 1, 10 - i),
              subject: 'Search match $i',
            ),
          );
        }

        final result = await repo.query(
          const EmailQuery(
            recipientPubkey: rpk,
            search: 'match',
            limit: 2,
            offset: 1,
          ),
        );

        expect(result.items.map((e) => e.id), ['search-1', 'search-2']);
      });
    });

    group('getByIds', () {
      test('returns records sorted by date descending', () async {
        await repo.save(makeRecord('b1', date: DateTime.utc(2024, 1, 1)));
        await repo.save(makeRecord('b2', date: DateTime.utc(2024, 1, 3)));
        await repo.save(makeRecord('b3', date: DateTime.utc(2024, 1, 2)));

        final emails = await repo.getByIds([
          'b1',
          'b3',
          'b2',
        ], recipientPubkey: rpk);

        expect(emails.map((e) => e.id), ['b2', 'b3', 'b1']);
      });

      test('returns empty list for empty input', () async {
        expect(await repo.getByIds([], recipientPubkey: rpk), isEmpty);
      });

      test('ignores non-existent ids', () async {
        await repo.save(makeRecord('exists'));

        final emails = await repo.getByIds([
          'exists',
          'does-not-exist',
        ], recipientPubkey: rpk);

        expect(emails.map((e) => e.id), ['exists']);
      });
    });

    group('mutations', () {
      test('delete removes the record', () async {
        await repo.save(makeRecord('to-delete'));
        await repo.delete('to-delete', recipientPubkey: rpk);
        expect(await repo.getById('to-delete', recipientPubkey: rpk), isNull);
      });

      test('clearAll removes every record', () async {
        await repo.save(makeRecord('e1'));
        await repo.save(makeRecord('e2'));
        await repo.save(makeRecord('e3'));

        await repo.clearAll();

        final result = await repo.query(EmailQuery(recipientPubkey: rpk));
        expect(result.items, isEmpty);
      });
    });
  });
}
