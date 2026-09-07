import 'package:sembast/sembast.dart';

/// Stores this package kept in the caller's sembast database before its data
/// moved to drift. Sembast holds every store in memory, so they are dropped
/// rather than left behind.
const legacySembastStores = [
  'emails',
  'labels',
  'gift_wraps',
  'private_settings',
  'tombstones',
  '_meta',
];

/// Drops the stores earlier versions kept in [db]. Idempotent.
Future<void> dropLegacySembastStores(Database db) =>
    db.transaction((txn) async {
      for (final name in legacySembastStores) {
        await StoreRef<Object?, Object?>(name).drop(txn);
      }
    });
