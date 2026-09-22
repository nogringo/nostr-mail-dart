import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:nostr_mail/src/storage/database.dart';
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
