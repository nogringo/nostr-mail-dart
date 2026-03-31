import 'package:enough_mail_plus/enough_mail.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:nostr_mail/src/storage/email_store.dart';
import 'package:test/test.dart';

void main() {
  group('EmailStore Search', () {
    late EmailStore store;
    final parser = EmailParser();

    setUp(() async {
      final db = await databaseFactoryMemory.openDatabase(
        'test_search_db_${DateTime.now().millisecondsSinceEpoch}',
      );
      store = EmailStore(db);
    });

    test('searchEmails filters by subject, body, or from', () async {
      final email1 = Email(
        id: 's1',
        senderPubkey: 'pk1',
        recipientPubkey: 'rpk1',
        rawContent: parser.build(
          from: MailAddress(null, 'alice@test.com'),
          to: [MailAddress(null, 'bob@test.com')],
          subject: 'Meeting tomorrow',
          body: 'Let us discuss the project.',
        ),
        createdAt: DateTime.utc(2024, 1, 1),
      );
      final email2 = Email(
        id: 's2',
        senderPubkey: 'pk2',
        recipientPubkey: 'rpk2',
        rawContent: parser.build(
          from: MailAddress(null, 'charlie@test.com'),
          to: [MailAddress(null, 'bob@test.com')],
          subject: 'Vacation',
          body: 'I am going to the beach.',
        ),
        createdAt: DateTime.utc(2024, 1, 2),
      );
      final email3 = Email(
        id: 's3',
        senderPubkey: 'pk1',
        recipientPubkey: 'rpk1',
        rawContent: parser.build(
          from: MailAddress(null, 'alice@test.com'),
          to: [MailAddress(null, 'bob@test.com')],
          subject: 'Project update',
          body: 'The Meeting was good.',
        ),
        createdAt: DateTime.utc(2024, 1, 3),
      );

      await store.saveEmail(email1);
      await store.saveEmail(email2);
      await store.saveEmail(email3);

      // Search by subject (case insensitive)
      var results = await store.searchEmails('meeting');
      expect(results.length, 2);
      var ids = results.map((e) => e.id).toList();
      expect(ids, contains('s1'));
      expect(ids, contains('s3'));

      // Search by body
      results = await store.searchEmails('beach');
      expect(results.length, 1);
      expect(results.first.id, 's2');

      // Search by from
      results = await store.searchEmails('charlie');
      expect(results.length, 1);
      expect(results.first.id, 's2');

      // No results
      results = await store.searchEmails('nonexistent');
      expect(results, isEmpty);
    });

    test('searchEmails respects limit and offset', () async {
      for (var i = 0; i < 5; i++) {
        await store.saveEmail(
          Email(
            id: 'search-$i',
            senderPubkey: 'pk',
            recipientPubkey: 'rpk',
            rawContent: parser.build(
              from: MailAddress(null, 'test@test.com'),
              to: [MailAddress(null, 'to@test.com')],
              subject: 'Search match $i',
              body: 'Body text',
            ),
            createdAt: DateTime.utc(2024, 1, 10 - i),
          ),
        );
      }

      final results = await store.searchEmails('match', limit: 2, offset: 1);

      expect(results.length, 2);
      expect(results[0].id, 'search-1');
      expect(results[1].id, 'search-2');
    });
  });
}
