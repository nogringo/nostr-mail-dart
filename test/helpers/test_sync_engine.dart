import 'package:ndk/ndk.dart';
import 'package:sembast/sembast.dart' hide Filter;
import 'package:sync_engine_shim_for_ndk/sync_engine_shim_for_ndk.dart';
import 'package:test/test.dart';

/// A sync engine for [NostrMailClient.create], disposed with the current test
/// so a relay backoff timer never outlives it.
SyncEngine testSyncEngine(Ndk ndk, Database db) {
  final engine = SyncEngine(ndk, db: db);
  addTearDown(engine.dispose);
  return engine;
}
