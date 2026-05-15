import 'package:ndk/ndk.dart';
import 'package:sembast/sembast.dart';

/// Current on-disk schema version expected by this build.
///
/// Bump this whenever the shape of any record stored locally changes in a way
/// that cannot be read by the previous code path. On startup, if the on-disk
/// version differs, every computed store is wiped and the client re-syncs
/// from the relays and Blossom servers.
const int kSchemaVersion = 1;

/// Stores that hold data derived from the network. Wiped on schema bumps.
/// Exposed for tests; not part of the supported public surface.
const migratableAppStores = <String>[
  'emails',
  'labels',
  'gift_wraps',
  'private_settings',
];

/// Sembast key holding the on-disk schema version.
/// Exposed for tests; not part of the supported public surface.
const schemaVersionKey = 'schema_version';

final _metaStore = StoreRef<String, int>('_meta');

/// Drops every local store and clears ndk's fetched-range cache when the
/// on-disk schema version differs from [kSchemaVersion].
///
/// Returns `true` if a migration ran, `false` if the schema was already
/// current. Callers can use the return value for logging or analytics.
///
/// The library assumes the user pays for retention on their relays and
/// Blossom servers, so a full resync is acceptable on every schema bump.
Future<bool> migrateSchemaIfNeeded({
  required Database db,
  required Ndk ndk,
}) async {
  final current = await _metaStore.record(schemaVersionKey).get(db);
  if (current == kSchemaVersion) return false;

  // Clear ndk fetched ranges first. It is idempotent, so if the sembast
  // transaction below fails the next run can safely repeat it. Writing the
  // version is the *last* observable step so a crash anywhere before the
  // commit leaves the on-disk version stale and the migration replays.
  await ndk.fetchedRanges.clearAll();

  await db.transaction((txn) async {
    for (final name in migratableAppStores) {
      await stringMapStoreFactory.store(name).delete(txn);
    }
    await _metaStore.record(schemaVersionKey).put(txn, kSchemaVersion);
  });

  return true;
}
