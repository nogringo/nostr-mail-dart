import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:ndk/ndk.dart' show Nip01Event;
import 'package:nostr_mail/src/storage/database.dart';
import 'package:nostr_mail/src/storage/gift_wrap_repository.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late File file;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    directory = Directory.systemTemp.createTempSync('nostr_mail_store');
    file = File('${directory.path}/mail.sqlite');
  });

  tearDown(() => directory.deleteSync(recursive: true));

  NostrMailDatabase open() => NostrMailDatabase(NativeDatabase(file));

  test('opens a store whose creation was cut short', () async {
    final partial = sqlite3.open(file.path);
    partial.execute('CREATE TABLE emails (id TEXT NOT NULL PRIMARY KEY)');
    partial.execute('CREATE INDEX emails_recipient_date ON emails (id)');
    expect(partial.userVersion, 0);
    partial.close();

    final database = open();
    addTearDown(database.close);
    await expectLater(database.openAndReportDrop(), completion(isTrue));
    await expectLater(database.emails.select().get(), completion(isEmpty));
  });

  test('a version 3 store keeps its decryptions and takes a wrap without a '
      'seal', () async {
    final v3 = sqlite3.open(file.path);
    v3.execute('''
      CREATE TABLE unsealed (
        wrap_id TEXT NOT NULL PRIMARY KEY,
        recipient_pubkey TEXT NOT NULL,
        seal TEXT NOT NULL,
        rumor TEXT NOT NULL,
        rumor_id TEXT NOT NULL
      )
    ''');
    v3.execute('CREATE INDEX unsealed_rumor_id ON unsealed (rumor_id)');
    v3.execute(
      "INSERT INTO unsealed VALUES ('wrap', 'pk', '{}', '{}', 'rumor')",
    );
    v3.userVersion = 3;
    v3.close();

    final database = open();
    addTearDown(database.close);
    await expectLater(database.openAndReportDrop(), completion(isTrue));
    await expectLater(
      database.unsealed.select().get(),
      completion([
        const UnsealedRow(
          wrapId: 'wrap',
          recipientPubkey: 'pk',
          seal: '{}',
          rumor: '{}',
          rumorId: 'rumor',
        ),
      ]),
    );

    final giftWraps = GiftWrapRepository(database);
    await giftWraps.saveOpened(
      Nip01Event(
        id: 'label-wrap',
        pubKey: 'ephemeral',
        createdAt: 1000,
        kind: 1059,
        tags: const [],
        content: '',
      ),
      recipientPubkey: 'pk',
      rumor: Nip01Event(
        id: 'label',
        pubKey: 'pk',
        createdAt: 1000,
        kind: 1985,
        tags: const [],
        content: '',
      ),
    );
    expect((await giftWraps.getUnsealed('label-wrap'))?.seal, isNull);
  });

  test('keeps the raw tables when creation is retried', () async {
    final first = open();
    await first.openAndReportDrop();
    await first
        .into(first.settings)
        .insert(SettingsCompanion.insert(pubkey: 'a', json: '{}'));
    await first.close();

    final reset = sqlite3.open(file.path);
    reset.userVersion = 0;
    reset.close();

    final database = open();
    addTearDown(database.close);
    await database.openAndReportDrop();
    await expectLater(
      database.settings.select().get(),
      completion(hasLength(1)),
    );
  });
}
