import 'package:drift/drift.dart';

import '../models/gift_wrap_state.dart';
import '../models/sender_verdict.dart';
import '../utils/senders_list.dart';
import 'database.dart';

/// Repository for the senders list: its Add and Remove events, entry by
/// entry, and what the signer made of their encrypted content.
///
/// The verdict of a sender is resolved by the `sender_verdicts` view, so the
/// events can land in any order.
class SenderRepository {
  final NostrMailDatabase _db;

  SenderRepository(this._db);

  Future<SenderListDecryptionRow?> getDecryption(
    String eventId, {
    required String recipientPubkey,
  }) {
    return (_db.select(_db.senderListDecryptions)..where(
          (d) =>
              d.eventId.equals(eventId) &
              d.recipientPubkey.equals(recipientPubkey),
        ))
        .getSingleOrNull();
  }

  Future<void> saveDecryption({
    required String eventId,
    required String recipientPubkey,
    required String plaintext,
  }) async {
    await _db
        .into(_db.senderListDecryptions)
        .insert(
          SenderListDecryptionsCompanion.insert(
            eventId: eventId,
            recipientPubkey: recipientPubkey,
            plaintext: Value(plaintext),
          ),
          onConflict: DoUpdate(
            (_) => SenderListDecryptionsCompanion(
              plaintext: Value(plaintext),
              failure: const Value(null),
            ),
          ),
        );
  }

  /// Record why decrypting [eventId] failed, and count it.
  Future<void> recordFailure({
    required String eventId,
    required String recipientPubkey,
    required GiftWrapFailure failure,
  }) async {
    await _db
        .into(_db.senderListDecryptions)
        .insert(
          SenderListDecryptionsCompanion.insert(
            eventId: eventId,
            recipientPubkey: recipientPubkey,
            failure: Value(failure.name),
            attempts: const Value(1),
          ),
          onConflict: DoUpdate(
            (old) => SenderListDecryptionsCompanion.custom(
              failure: Constant(failure.name),
              attempts: old.attempts + const Constant(1),
            ),
          ),
        );
  }

  /// Whether the entries of [eventId] are already applied.
  Future<bool> hasEvent(
    String eventId, {
    required String recipientPubkey,
  }) async {
    final row =
        await (_db.select(_db.senderOps)
              ..where(
                (o) =>
                    o.eventId.equals(eventId) &
                    o.recipientPubkey.equals(recipientPubkey),
              )
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  /// Apply the entries of a senders list event, and report the senders whose
  /// verdict changed, with the new one.
  Future<Map<String, SenderVerdict?>> saveEntries({
    required String eventId,
    required String recipientPubkey,
    required bool isAdd,
    required int createdAt,
    required List<SenderEntry> entries,
  }) {
    final keys = {for (final entry in entries) entry.key};
    return _tracking(keys, recipientPubkey, () async {
      await _db.batch(
        (b) => b.insertAll(_db.senderOps, [
          for (final entry in entries)
            SenderOpRow(
              eventId: eventId,
              recipientPubkey: recipientPubkey,
              senderKey: entry.key,
              isAdd: isAdd,
              verdict: isAdd ? entry.verdict : null,
              createdAt: createdAt,
            ),
        ], mode: InsertMode.insertOrIgnore),
      );
    });
  }

  /// Drop a deleted senders list event, and report the senders whose verdict
  /// changed, with the new one.
  Future<Map<String, SenderVerdict?>> removeEvent(
    String eventId, {
    required String recipientPubkey,
  }) async {
    final ops = _db.senderOps;
    final keys =
        await (_db.selectOnly(ops)
              ..addColumns([ops.senderKey])
              ..where(
                ops.eventId.equals(eventId) &
                    ops.recipientPubkey.equals(recipientPubkey),
              ))
            .map((row) => row.read(ops.senderKey)!)
            .get();
    return _tracking(keys.toSet(), recipientPubkey, () async {
      await (_db.delete(ops)..where(
            (o) =>
                o.eventId.equals(eventId) &
                o.recipientPubkey.equals(recipientPubkey),
          ))
          .go();
      await (_db.delete(_db.senderListDecryptions)..where(
            (d) =>
                d.eventId.equals(eventId) &
                d.recipientPubkey.equals(recipientPubkey),
          ))
          .go();
    });
  }

  Future<SenderVerdict?> verdictOf(
    String senderKey, {
    required String recipientPubkey,
  }) async {
    final verdicts = await _verdicts({senderKey}, recipientPubkey);
    return verdicts[senderKey];
  }

  /// The `created_at` of the latest event naming [senderKey], Add or Remove.
  Future<int?> latestCreatedAt(
    String senderKey, {
    required String recipientPubkey,
  }) {
    final ops = _db.senderOps;
    final latest = ops.createdAt.max();
    return (_db.selectOnly(ops)
          ..addColumns([latest])
          ..where(
            ops.senderKey.equals(senderKey) &
                ops.recipientPubkey.equals(recipientPubkey),
          ))
        .map((row) => row.read(latest))
        .getSingle();
  }

  /// Wipes the list and its decryptions. Asked for by the user, unlike the
  /// drop a schema change performs, so the decryptions go too.
  Future<void> clearAll({String? recipientPubkey}) async {
    await _db.transaction(() async {
      final ops = _db.delete(_db.senderOps);
      final decryptions = _db.delete(_db.senderListDecryptions);
      if (recipientPubkey != null) {
        ops.where((o) => o.recipientPubkey.equals(recipientPubkey));
        decryptions.where((d) => d.recipientPubkey.equals(recipientPubkey));
      }
      await ops.go();
      await decryptions.go();
    });
  }

  Future<Map<String, SenderVerdict?>> _tracking(
    Set<String> keys,
    String recipientPubkey,
    Future<void> Function() change,
  ) {
    if (keys.isEmpty) return Future.value(const {});
    return _db.transaction(() async {
      final before = await _verdicts(keys, recipientPubkey);
      await change();
      final after = await _verdicts(keys, recipientPubkey);
      return {
        for (final key in keys)
          if (before[key] != after[key]) key: after[key],
      };
    });
  }

  Future<Map<String, SenderVerdict>> _verdicts(
    Set<String> keys,
    String recipientPubkey,
  ) async {
    final rows =
        await (_db.select(_db.senderVerdicts)..where(
              (v) =>
                  v.recipientPubkey.equals(recipientPubkey) &
                  v.senderKey.isIn(keys),
            ))
            .get();
    return {
      for (final row in rows)
        row.senderKey: SenderVerdict.values.byName(row.verdict!),
    };
  }
}
