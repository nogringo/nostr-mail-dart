import 'package:nostr_mail/src/storage/email_repository.dart';
import 'package:nostr_mail/src/storage/label_repository.dart';
import 'package:nostr_mail/src/storage/models/email_record.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:test/test.dart';

void main() {
  group('LabelRepository', () {
    const rpk = 'rpk';
    late LabelRepository labels;
    late EmailRepository emails;

    int now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

    EmailRecord seedRecord(String id) => EmailRecord(
      id: id,
      senderPubkey: 'pk',
      recipientPubkey: rpk,
      lightMimeText: 'raw',
      attachmentRefs: const [],
      isPublic: false,
      createdAt: 1000,
      date: 1000,
      from: 'a@b.com',
      subject: 'sub',
      bodyPlain: 'body',
      searchText: 'a@b.com sub body',
      attachmentCount: 0,
      folder: 'inbox',
      isRead: false,
      isStarred: false,
      labels: const [],
      isBridged: false,
    );

    setUp(() async {
      final db = await databaseFactoryMemory.openDatabase(
        'test_label_${DateTime.now().microsecondsSinceEpoch}',
      );
      emails = EmailRepository(db);
      labels = LabelRepository(db);
    });

    Future<void> save(
      String emailId,
      String label, {
      String? eventId,
      int? timestamp,
    }) {
      return labels.saveLabel(
        emailId: emailId,
        label: label,
        labelEventId: eventId ?? 'ev-$emailId-$label',
        timestamp: timestamp ?? now(),
        recipientPubkey: rpk,
      );
    }

    group('saveLabel / getLabelEventId', () {
      test('stores and retrieves the event id', () async {
        await save('email-1', 'folder:trash', eventId: 'label-event-1');

        final eventId = await labels.getLabelEventId(
          'email-1',
          'folder:trash',
          recipientPubkey: rpk,
        );

        expect(eventId, 'label-event-1');
      });

      test('returns null for an unknown label', () async {
        expect(
          await labels.getLabelEventId(
            'email-1',
            'folder:trash',
            recipientPubkey: rpk,
          ),
          isNull,
        );
      });

      test('updates the event id when saving the same label twice', () async {
        await save('email-1', 'folder:trash', eventId: 'old-id');
        await save('email-1', 'folder:trash', eventId: 'new-id');

        expect(
          await labels.getLabelEventId(
            'email-1',
            'folder:trash',
            recipientPubkey: rpk,
          ),
          'new-id',
        );
        // The label is not duplicated.
        final list = await labels.getLabelsForEmail(
          'email-1',
          recipientPubkey: rpk,
        );
        expect(list.length, 1);
      });
    });

    group('denormalization onto EmailRecord', () {
      setUp(() async => emails.save(seedRecord('e1')));

      test('flag:starred sets isStarred', () async {
        await save('e1', 'flag:starred');
        final email = await emails.getById('e1', recipientPubkey: rpk);
        expect(email!.isStarred, true);
      });

      test('folder:trash sets folder', () async {
        await save('e1', 'folder:trash');
        final email = await emails.getById('e1', recipientPubkey: rpk);
        expect(email!.folder, 'trash');
      });

      test('removeLabel reverts the denormalized state', () async {
        await save('e1', 'state:read');
        await labels.removeLabel('e1', 'state:read', recipientPubkey: rpk);
        final email = await emails.getById('e1', recipientPubkey: rpk);
        expect(email!.isRead, false);
      });
    });

    group('queries', () {
      test('getLabelsForEmail returns all labels for an email', () async {
        await save('email-1', 'folder:trash');
        await save('email-1', 'state:read');
        await save('email-1', 'flag:starred');
        // Other email — must not appear.
        await save('email-2', 'folder:archive');

        final list = await labels.getLabelsForEmail(
          'email-1',
          recipientPubkey: rpk,
        );

        expect(list, hasLength(3));
        expect(
          list,
          containsAll(['folder:trash', 'state:read', 'flag:starred']),
        );
        expect(list, isNot(contains('folder:archive')));
      });

      test('getLabelsForEmail returns empty list when no labels', () async {
        expect(
          await labels.getLabelsForEmail('no-labels', recipientPubkey: rpk),
          isEmpty,
        );
      });

      test('getEmailIdsWithLabel returns matching email ids', () async {
        await save('email-1', 'folder:trash');
        await save('email-2', 'folder:trash');
        await save('email-3', 'folder:archive');

        final trashed = await labels.getEmailIdsWithLabel(
          'folder:trash',
          recipientPubkey: rpk,
        );

        expect(trashed, hasLength(2));
        expect(trashed, containsAll(['email-1', 'email-2']));
        expect(trashed, isNot(contains('email-3')));
      });

      test('getEmailIdsWithLabel returns empty when no matches', () async {
        expect(
          await labels.getEmailIdsWithLabel(
            'folder:trash',
            recipientPubkey: rpk,
          ),
          isEmpty,
        );
      });

      test('hasLabel reflects presence', () async {
        await save('email-1', 'folder:trash');

        expect(
          await labels.hasLabel(
            'email-1',
            'folder:trash',
            recipientPubkey: rpk,
          ),
          isTrue,
        );
        expect(
          await labels.hasLabel('email-1', 'state:read', recipientPubkey: rpk),
          isFalse,
        );
      });
    });

    group('cleanup', () {
      test('deleteLabelsForEmail removes only that email\'s labels', () async {
        await save('email-1', 'folder:trash');
        await save('email-1', 'state:read');
        await save('email-2', 'folder:trash');

        await labels.deleteLabelsForEmail('email-1', recipientPubkey: rpk);

        expect(
          await labels.getLabelsForEmail('email-1', recipientPubkey: rpk),
          isEmpty,
        );
        expect(
          await labels.getLabelsForEmail('email-2', recipientPubkey: rpk),
          ['folder:trash'],
        );
      });

      test('clearAll removes every label', () async {
        await save('email-1', 'folder:trash');
        await save('email-2', 'state:read');

        await labels.clearAll();

        expect(
          await labels.getLabelsForEmail('email-1', recipientPubkey: rpk),
          isEmpty,
        );
        expect(
          await labels.getLabelsForEmail('email-2', recipientPubkey: rpk),
          isEmpty,
        );
      });
    });
  });
}
