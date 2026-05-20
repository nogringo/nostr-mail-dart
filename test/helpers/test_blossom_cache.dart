import 'package:blossom_cache/blossom_cache.dart';
import 'package:idb_shim/idb_client_memory.dart';

/// In-memory BlossomCache for tests. The shim requires one but the bytes do
/// not need to survive across test cases.
Future<BlossomCache> openTestBlossomCache([String? dbName]) {
  return IdbBlossomCache.open(
    factory: newIdbFactoryMemory(),
    dbName: dbName ?? 'blossom_cache_test',
  );
}
