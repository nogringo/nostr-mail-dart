import 'package:drift/drift.dart';

part 'database.g.dart';

/// The local mail store. Open it with `NativeDatabase` on native and
/// `WasmDatabase.open(...).resolvedExecutor` on web, and close it yourself
/// once the client is disposed.
@DriftDatabase(include: {'schema.drift'})
class NostrMailDatabase extends _$NostrMailDatabase {
  NostrMailDatabase(super.e);

  /// The tables holding what no rebuild can recompute: NIP-44 output, whose
  /// only other source is the signer, and every approval it asks its user for.
  /// A schema change leaves them alone; only [clearAll] on the repositories
  /// empties them.
  static const _rawTables = {'unsealed', 'settings'};

  /// Bump on any schema change. Everything outside [_rawTables] is a
  /// projection of the NDK cache and of those tables, so a mismatch drops and
  /// recreates it instead of migrating. Indexes are dropped either way: they
  /// hold nothing of their own, and `createAll` would trip over one it finds.
  @override
  int get schemaVersion => 2;

  bool _droppedProjection = false;

  /// Opens the store, running any pending migration, and reports whether that
  /// migration dropped the projection. A `true` owes a full replay: nothing
  /// else asks for the pass that fills the dropped tables again.
  Future<bool> openAndReportDrop() async {
    await customSelect('SELECT 1').get();
    return _droppedProjection;
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
    onUpgrade: (m, from, to) async {
      for (final entity in allSchemaEntities) {
        if (entity is TableInfo &&
            _rawTables.contains(entity.actualTableName)) {
          continue;
        }
        await m.drop(entity);
      }
      await m.createAll();
      _droppedProjection = true;
    },
  );
}
