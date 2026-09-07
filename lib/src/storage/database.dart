import 'package:drift/drift.dart';

part 'database.g.dart';

/// The local mail store. Open it with `NativeDatabase` on native and
/// `WasmDatabase.open(...).resolvedExecutor` on web, and close it yourself
/// once the client is disposed.
@DriftDatabase(include: {'schema.drift'})
class NostrMailDatabase extends _$NostrMailDatabase {
  NostrMailDatabase(super.e);

  /// Bump on any schema change. The tables are a projection of the NDK cache,
  /// so every mismatch drops and recreates them instead of migrating.
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
    onUpgrade: (m, from, to) async {
      for (final entity in allSchemaEntities) {
        await m.drop(entity);
      }
      await m.createAll();
    },
  );
}
