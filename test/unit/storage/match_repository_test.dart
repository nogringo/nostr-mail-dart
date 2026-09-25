import 'dart:convert';

import 'package:nostr_mail/src/models/attachment_ref.dart';
import 'package:nostr_mail/src/storage/email_repository.dart';
import 'package:nostr_mail/src/storage/label_repository.dart';
import 'package:nostr_mail/src/storage/models/email_query.dart';
import 'package:nostr_mail/src/storage/models/email_record.dart';
import 'package:nostr_mail/src/storage/settings_repository.dart';
import 'package:test/test.dart';

import '../../helpers/test_database.dart';

void main() {
  group('Folders and tags held by a match', () {
    const rpk = 'rpk';
    const github = 'e4d1907b23c6af58';
    const invoices = '9f2c1a7b4d3e5f60';
    const urgent = '4b81d0e7a5c39f12';

    late EmailRepository emails;
    late LabelRepository labels;
    late SettingsRepository settings;

    setUp(() {
      final database = testDatabase();
      emails = EmailRepository(database);
      labels = LabelRepository(database);
      settings = SettingsRepository(database);
    });

    Future<void> saveEmail(
      String id, {
      String from = 'someone@example.com',
      String subject = 'Hello',
      bool attachment = false,
    }) => emails.save(
      EmailRecord(
        id: id,
        senderPubkey: 'sender',
        recipientPubkey: rpk,
        lightMimeText: '',
        attachmentRefs: [
          if (attachment)
            const AttachmentRef(
              contentType: 'text/plain',
              size: 1,
              sha256: 's',
            ),
        ],
        isPublic: false,
        createdAt: 1000,
        date: 1000,
        from: from,
        subject: subject,
        bodyPlain: '',
        folder: 'inbox',
        isBridged: false,
      ),
    );

    Future<void> saveSettings({
      List<Map<String, dynamic>> folders = const [],
      List<Map<String, dynamic>> tags = const [],
    }) => settings.save(
      pubkey: rpk,
      json: jsonEncode({'folders': folders, 'tags': tags}),
    );

    Future<void> label(String id, String label, {int timestamp = 2000}) =>
        labels.saveLabel(
          emailId: id,
          label: label,
          labelEventId: '$id-$label-$timestamp',
          timestamp: timestamp,
          recipientPubkey: rpk,
        );

    Future<String?> folderOf(String id) =>
        emails.folderOf(id, recipientPubkey: rpk);

    Future<List<String>> ids(EmailQuery query) async =>
        (await emails.query(query)).items.map((e) => e.id).toList()..sort();

    test('an email falls to the first matching folder, by position', () async {
      await saveSettings(
        folders: [
          {
            'id': invoices,
            'name': 'Invoices',
            'position': 1,
            'match': {
              'subject': ['invoice'],
            },
          },
          {
            'id': github,
            'name': 'GitHub',
            'position': 0,
            'match': {
              'from': ['github.com'],
            },
          },
        ],
      );
      await saveEmail('both', from: 'billing@github.com', subject: 'Invoice');
      await saveEmail('invoice', subject: 'Your invoice');
      await saveEmail('plain');

      expect(await folderOf('both'), github);
      expect(await folderOf('invoice'), invoices);
      expect(await folderOf('plain'), 'inbox');
      expect(await ids(EmailQuery(recipientPubkey: rpk, folder: invoices)), [
        'invoice',
      ]);
    });

    test('a folder label wins over a match', () async {
      await saveSettings(
        folders: [
          {
            'id': github,
            'name': 'GitHub',
            'match': {
              'from': ['github.com'],
            },
          },
        ],
      );
      await saveEmail('a', from: 'noreply@github.com');
      await label('a', 'folder:inbox');

      expect(await folderOf('a'), 'inbox');
    });

    test('saving settings moves the emails already stored', () async {
      await saveEmail('a', from: 'noreply@github.com');
      await saveEmail('b', attachment: true);
      expect(await folderOf('a'), 'inbox');

      await saveSettings(
        folders: [
          {
            'id': github,
            'name': 'GitHub',
            'match': {
              'from': ['github.com'],
            },
          },
        ],
        tags: [
          {
            'id': urgent,
            'name': 'Files',
            'match': {'has_attachment': true},
          },
        ],
      );
      expect(await folderOf('a'), github);
      expect((await emails.getById('b', recipientPubkey: rpk))!.tags, [urgent]);

      await saveSettings();
      expect(await folderOf('a'), 'inbox');
      expect((await emails.getById('b', recipientPubkey: rpk))!.tags, isEmpty);
    });

    test('a tag holds its labelled and matched emails, outside trash and '
        'spam', () async {
      await saveSettings(
        tags: [
          {
            'id': urgent,
            'name': 'Urgent',
            'match': {
              'subject': ['urgent'],
            },
          },
        ],
      );
      await saveEmail('matched', subject: 'URGENT: read');
      await saveEmail('labelled');
      await label('labelled', 'tag:$urgent');
      await saveEmail('trashed', subject: 'urgent');
      await label('trashed', 'folder:trash');
      await saveEmail('spam');
      await label('spam', 'tag:$urgent');
      await label('spam', 'folder:spam');
      await saveEmail('other');

      final query = EmailQuery(recipientPubkey: rpk, tag: urgent);
      expect(await ids(query), ['labelled', 'matched']);
      expect(await emails.count(query), 2);

      final summaries = await emails.querySummaries(query);
      expect(summaries.items.map((s) => s.tags), [
        [urgent],
        [urgent],
      ]);
    });
  });
}
