import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:test/test.dart';

import '../../helpers/test_blossom_cache.dart';
import '../../helpers/test_database.dart';
import '../../helpers/test_sync_engine.dart';
import '../../helpers/wait_for_broadcasts.dart';
import '../../mocks/mock_relay.dart';

void main() {
  group('User folders and tags', () {
    late Ndk ndk;
    late NostrMailClient client;
    late MockRelay relay;

    setUp(() async {
      relay = MockRelay(name: 'relay', explicitPort: 19036);
      await relay.startServer();

      final db = await databaseFactoryMemory.openDatabase(
        'test_db_${DateTime.now().microsecondsSinceEpoch}',
      );
      ndk = Ndk(
        NdkConfig(
          bootstrapRelays: [relay.url],
          eventVerifier: Bip340EventVerifier(),
          cache: MemCacheManager(),
        ),
      );

      final keyPair = Bip340.generatePrivateKey();
      ndk.accounts.loginPrivateKey(
        pubkey: keyPair.publicKey,
        privkey: keyPair.privateKey!,
      );

      client = await NostrMailClient.create(
        ndk: ndk,
        database: testDatabase(),
        db: db,
        syncEngine: testSyncEngine(ndk, db),
        blossomCache: await openTestBlossomCache('user_folders_test'),
        defaultDmRelays: [relay.url],
      );
    });

    tearDown(() async {
      await ndk.destroy();
      await relay.stopServer();
    });

    test('creates entries with a fresh id, a trimmed name and the next '
        'position', () async {
      final first = await client.createFolder('  Invoices ');
      final second = await client.createFolder('GitHub', color: '#C86432');
      final tag = await client.createTag('Invoices');

      expect(first.id, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(first.name, 'Invoices');
      expect(first.position, 0);
      expect(second.position, 1);
      expect({first.id, second.id, tag.id}, hasLength(3));

      final settings = client.cachedPrivateSettings()!;
      expect(settings.folders!.map((f) => f.name), ['Invoices', 'GitHub']);
      expect(settings.tags!.single.name, 'Invoices');
    });

    test('rejects a taken, empty or too long name and a bad color', () async {
      final folder = await client.createFolder('Invoices');

      expect(
        () => client.createFolder('invoices'),
        throwsA(isA<NostrMailException>()),
      );
      expect(
        () => client.createFolder('   '),
        throwsA(isA<NostrMailException>()),
      );
      expect(
        () => client.createFolder('x' * 65),
        throwsA(isA<NostrMailException>()),
      );
      expect(
        () => client.createFolder('Red', color: 'red'),
        throwsA(isA<NostrMailException>()),
      );

      final renamed = await client.updateFolder(folder.id, name: 'INVOICES');
      expect(renamed.name, 'INVOICES');
    });

    test('trash remembers the user folder and restore goes back', () async {
      await client.send(
        to: [NostrRecipient.fromPubkey(Bip340.generatePrivateKey().publicKey)],
        subject: 'Invoice 42',
        body: 'Due next week.',
      );
      await waitForBroadcasts(client.broadcastQueue);
      final emailId = (await client.getSentEmails()).single.id;
      final folder = await client.createFolder('Invoices');

      Future<List<String>> listed(String folder) async =>
          (await client.getSummaries(
            folder: folder,
          )).items.map((e) => e.id).toList();

      await client.moveToFolder(emailId, folder.id);
      expect(await listed(folder.id), [emailId]);
      expect(await listed('sent'), isEmpty);

      await client.moveToTrash(emailId);
      expect(await listed('trash'), [emailId]);

      await client.restoreFromTrash(emailId);
      expect(await listed(folder.id), [emailId]);
      expect(await client.getLabels(emailId), ['folder:${folder.id}']);
    });

    test('a folder condition holds an email until a label moves it', () async {
      final folder = await client.createFolder(
        'Invoices',
        match: const MailMatch(subject: ['invoice']),
      );
      await client.send(
        to: [NostrRecipient.fromPubkey(Bip340.generatePrivateKey().publicKey)],
        subject: 'Invoice 42',
        body: 'Due next week.',
      );
      await waitForBroadcasts(client.broadcastQueue);

      final summary = (await client.getSummaries(folder: folder.id)).items;
      expect(summary.single.subject, 'Invoice 42');

      await client.moveToFolder(summary.single.id, 'inbox');
      expect((await client.getSummaries(folder: folder.id)).items, isEmpty);

      await client.updateFolder(folder.id, clearMatch: true);
      await client.removeLabel(summary.single.id, 'folder:inbox');
      expect((await client.getSummaries(folder: 'sent')).items, hasLength(1));
    });

    test(
      'getSummary carries the folder, labels and tags of one email',
      () async {
        await client.send(
          to: [
            NostrRecipient.fromPubkey(Bip340.generatePrivateKey().publicKey),
          ],
          subject: 'Invoice 42',
          body: 'Due next week.',
        );
        await waitForBroadcasts(client.broadcastQueue);
        final emailId = (await client.getSentEmails()).single.id;
        final folder = await client.createFolder('Invoices');
        final labelled = await client.createTag('Urgent');
        final matched = await client.createTag(
          'Billing',
          match: const MailMatch(subject: ['invoice']),
        );

        await client.moveToFolder(emailId, folder.id);
        await client.addTag(emailId, labelled.id);

        final summary = (await client.getSummary(emailId))!;
        expect(summary.folder, folder.id);
        expect(summary.tags, unorderedEquals([labelled.id, matched.id]));
        expect(summary.labels, contains('tag:${labelled.id}'));
        expect(summary.labels, isNot(contains('tag:${matched.id}')));
        expect(await client.getSummary('missing'), isNull);
      },
    );

    test('restoring without a previous folder removes the label', () async {
      const emailId = 'email-1';

      await client.moveToArchive(emailId);
      await client.restoreFromArchive(emailId);

      expect(await client.getLabels(emailId), isEmpty);
    });

    test('deleting a folder or a tag keeps the labels', () async {
      const emailId = 'email-1';
      final folder = await client.createFolder('Invoices');
      final tag = await client.createTag('Urgent');
      await client.moveToFolder(emailId, folder.id);
      await client.addTag(emailId, tag.id);

      await client.deleteFolder(folder.id);
      await client.deleteTag(tag.id);

      final settings = client.cachedPrivateSettings()!;
      expect(settings.folders, isEmpty);
      expect(settings.tags, isEmpty);
      expect(
        await client.getLabels(emailId),
        unorderedEquals(['folder:${folder.id}', 'tag:${tag.id}']),
      );

      await client.removeTag(emailId, tag.id);
      expect(await client.getLabels(emailId), ['folder:${folder.id}']);
    });
  });
}
