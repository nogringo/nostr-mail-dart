import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:nostr_mail/src/storage/database.dart';
import 'package:test/test.dart';

/// An in-memory mail store closed with the current test.
NostrMailDatabase testDatabase() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final database = NostrMailDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  return database;
}
