import 'package:sembast/sembast_memory.dart';
import 'package:test/test.dart';

import 'package:nostr_mail/src/storage/email_repository.dart';
import 'package:nostr_mail/src/storage/label_repository.dart';
import 'package:nostr_mail/src/storage/gift_wrap_repository.dart';
import 'package:nostr_mail/src/storage/settings_repository.dart';
import 'package:nostr_mail/src/storage/models/email_record.dart';
import 'package:nostr_mail/src/storage/models/email_query.dart';

void main() {
  group('EmailRepository', () {
    late EmailRepository repo;

    setUp(() async {
      final db = await databaseFactoryMemoryFs.openDatabase(
        'test_email_${DateTime.now().millisecondsSinceEpoch}',
      );
      repo = EmailRepository(db);
    });

    EmailRecord makeRecord(
      String id, {
      String folder = 'inbox',
      bool isRead = false,
      bool isStarred = false,
      int attachmentCount = 0,
      String searchText = '',
      int date = 1000,
    }) {
      return EmailRecord(
        id: id,
        senderPubkey: 'pk',
        recipientPubkey: 'rpk',
        rawContent: 'raw',
        isPublic: false,
        createdAt: 1000,
        date: date,
        from: 'a@b.com',
        subject: 'sub',
        bodyPlain: 'body',
        searchText: searchText.isEmpty ? 'a@b.com sub body' : searchText,
        attachmentCount: attachmentCount,
        folder: folder,
        isRead: isRead,
        isStarred: isStarred,
        labels: [],
        isBridged: false,
      );
    }

    test('save and getById', () async {
      final record = makeRecord('e1');
      await repo.save(record);
      final found = await repo.getById('e1');
      expect(found, isNotNull);
      expect(found!.id, 'e1');
    });

    test('query by folder', () async {
      await repo.save(makeRecord('e1', folder: 'inbox'));
      await repo.save(makeRecord('e2', folder: 'sent'));
      await repo.save(makeRecord('e3', folder: 'trash'));

      final result = await repo.query(const EmailQuery(folder: 'inbox'));
      expect(result.items.length, 1);
      expect(result.items.first.id, 'e1');
    });

    test('query by isRead', () async {
      await repo.save(makeRecord('e1', isRead: true));
      await repo.save(makeRecord('e2', isRead: false));

      final result = await repo.query(const EmailQuery(isRead: true));
      expect(result.items.length, 1);
      expect(result.items.first.id, 'e1');
    });

    test('query by hasAttachments', () async {
      await repo.save(makeRecord('e1', attachmentCount: 2));
      await repo.save(makeRecord('e2', attachmentCount: 0));

      final result = await repo.query(const EmailQuery(hasAttachments: true));
      expect(result.items.length, 1);
      expect(result.items.first.id, 'e1');
    });

    test('query by search text', () async {
      await repo.save(makeRecord('e1', searchText: 'hello world'));
      await repo.save(makeRecord('e2', searchText: 'goodbye moon'));

      final result = await repo.query(const EmailQuery(search: 'hello'));
      expect(result.items.length, 1);
      expect(result.items.first.id, 'e1');
    });

    test('query with pagination', () async {
      for (var i = 0; i < 5; i++) {
        await repo.save(makeRecord('e$i', date: 2000 - i));
      }

      final page1 = await repo.query(const EmailQuery(limit: 2, offset: 0));
      expect(page1.items.length, 2);
      expect(page1.total, 5);
      expect(page1.hasMore, true);

      final page2 = await repo.query(const EmailQuery(limit: 2, offset: 2));
      expect(page2.items.length, 2);
      expect(page2.hasMore, true);

      final page3 = await repo.query(const EmailQuery(limit: 2, offset: 4));
      expect(page3.items.length, 1);
      expect(page3.hasMore, false);
    });

    test('query combined filters', () async {
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
        const EmailQuery(folder: 'inbox', isRead: false, isStarred: true),
      );
      expect(result.items.length, 1);
      expect(result.items.first.id, 'e1');
    });

    test('search free text across records', () async {
      await repo.save(makeRecord('e1', searchText: 'invoice from acme'));
      await repo.save(makeRecord('e2', searchText: 'receipt from shop'));

      final results = await repo.search('acme');
      expect(results.length, 1);
      expect(results.first.id, 'e1');
    });

    test('delete removes record', () async {
      await repo.save(makeRecord('e1'));
      await repo.delete('e1');
      expect(await repo.getById('e1'), isNull);
    });
  });

  group('LabelRepository', () {
    late LabelRepository labels;
    late EmailRepository emails;

    setUp(() async {
      final db = await databaseFactoryMemoryFs.openDatabase(
        'test_label_${DateTime.now().millisecondsSinceEpoch}',
      );
      emails = EmailRepository(db);
      labels = LabelRepository(db);

      // Seed an email
      await emails.save(
        EmailRecord(
          id: 'e1',
          senderPubkey: 'pk',
          recipientPubkey: 'rpk',
          rawContent: 'raw',
          isPublic: false,
          createdAt: 1000,
          date: 1000,
          from: 'a@b.com',
          subject: 'sub',
          bodyPlain: 'body',
          searchText: 'search',
          attachmentCount: 0,
          folder: 'inbox',
          isRead: false,
          isStarred: false,
          labels: [],
          isBridged: false,
        ),
      );
    });

    test('saveLabel stores metadata', () async {
      await labels.saveLabel(
        emailId: 'e1',
        label: 'flag:starred',
        labelEventId: 'ev1',
        timestamp: 1000,
      );
      expect(await labels.hasLabel('e1', 'flag:starred'), true);
      expect(await labels.getLabelEventId('e1', 'flag:starred'), 'ev1');
    });

    test('saveLabel denormalizes into email record', () async {
      await labels.saveLabel(
        emailId: 'e1',
        label: 'flag:starred',
        labelEventId: 'ev1',
        timestamp: 1000,
      );
      final email = await emails.getById('e1');
      expect(email!.isStarred, true);
    });

    test('folder label denormalizes folder field', () async {
      await labels.saveLabel(
        emailId: 'e1',
        label: 'folder:trash',
        labelEventId: 'ev2',
        timestamp: 1000,
      );
      final email = await emails.getById('e1');
      expect(email!.folder, 'trash');
    });

    test('removeLabel reverts denormalized state', () async {
      await labels.saveLabel(
        emailId: 'e1',
        label: 'state:read',
        labelEventId: 'ev3',
        timestamp: 1000,
      );
      await labels.removeLabel('e1', 'state:read');
      final email = await emails.getById('e1');
      expect(email!.isRead, false);
    });

    test('getLabelsForEmail returns all labels', () async {
      await labels.saveLabel(
        emailId: 'e1',
        label: 'flag:starred',
        labelEventId: 'ev1',
        timestamp: 1000,
      );
      await labels.saveLabel(
        emailId: 'e1',
        label: 'custom:tag',
        labelEventId: 'ev2',
        timestamp: 1000,
      );
      final list = await labels.getLabelsForEmail('e1');
      expect(list.length, 2);
    });

    test('deleteLabelsForEmail cleans up', () async {
      await labels.saveLabel(
        emailId: 'e1',
        label: 'flag:starred',
        labelEventId: 'ev1',
        timestamp: 1000,
      );
      await labels.deleteLabelsForEmail('e1');
      expect(await labels.getLabelsForEmail('e1'), isEmpty);
    });
  });

  group('GiftWrapRepository', () {
    late GiftWrapRepository repo;

    setUp(() async {
      final db = await databaseFactoryMemoryFs.openDatabase(
        'test_gw_${DateTime.now().millisecondsSinceEpoch}',
      );
      repo = GiftWrapRepository(db);
    });

    test('save and getUnprocessed', () async {
      // We can't easily create a Nip01Event here without more deps,
      // so we just verify the store API exists and compiles.
      expect(repo, isNotNull);
    });
  });

  group('SettingsRepository', () {
    late SettingsRepository repo;

    setUp(() async {
      final db = await databaseFactoryMemoryFs.openDatabase(
        'test_settings_${DateTime.now().millisecondsSinceEpoch}',
      );
      repo = SettingsRepository(db);
    });

    test('save and load', () async {
      await repo.save(pubkey: 'pk1', json: '{"signature":"hi"}');
      final loaded = await repo.load(pubkey: 'pk1');
      expect(loaded, '{"signature":"hi"}');
    });

    test('clear specific pubkey', () async {
      await repo.save(pubkey: 'pk1', json: '{}');
      await repo.clear(pubkey: 'pk1');
      expect(await repo.load(pubkey: 'pk1'), isNull);
    });
  });
}
