import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:ndk/ndk.dart' show Nip01Event, Nip01EventModel;

import '../models/gift_wrap_state.dart';
import '../models/unwrapped_gift_wrap.dart';
import 'database.dart';

/// Repository for raw NIP-59 gift-wrap events.
class GiftWrapRepository {
  final NostrMailDatabase _db;

  GiftWrapRepository(this._db);

  static final _stored = GiftWrapStage.stored.name;

  /// Save a gift wrap event if new, and report where it stands.
  Future<GiftWrapProgress> save(
    Nip01Event event, {
    required String recipientPubkey,
  }) async {
    final existing = await _row(event.id);
    if (existing != null) return _progressOf(existing);
    await _db
        .into(_db.giftWraps)
        .insert(
          GiftWrapsCompanion.insert(
            id: event.id,
            recipientPubkey: recipientPubkey,
            event: _encode(event),
            stage: GiftWrapStage.saved.name,
          ),
        );
    return const GiftWrapProgress(stage: GiftWrapStage.saved);
  }

  /// Get a gift wrap record by its globally unique outer event ID.
  Future<Map<String, dynamic>?> getById(String giftWrapId) async {
    final row = await _row(giftWrapId);
    return row == null ? null : _toMap(row);
  }

  /// Get a gift wrap by ID only if it belongs to [recipientPubkey].
  Future<Map<String, dynamic>?> getByIdForRecipient(
    String giftWrapId, {
    required String recipientPubkey,
  }) async {
    final row = await _row(giftWrapId, recipientPubkey: recipientPubkey);
    return row == null ? null : _toMap(row);
  }

  /// Record the seal and rumor a gift wrap yielded, before the email itself
  /// is built.
  ///
  /// Written as soon as they are in hand so a later failure resumes at the
  /// Blossom fetch: reaching this point cost the signer its approvals, and a
  /// remote signer would have to ask its user for them again.
  Future<void> updateUnsealed({
    required String giftWrapId,
    required Nip01Event seal,
    required Nip01Event rumor,
  }) async {
    await (_db.update(
      _db.giftWraps,
    )..where((w) => w.id.equals(giftWrapId))).write(
      GiftWrapsCompanion(
        seal: Value(_encode(seal)),
        rumor: Value(_encode(rumor)),
        rumorId: Value(rumor.id),
        stage: Value(GiftWrapStage.unsealed.name),
        failure: const Value(null),
      ),
    );
  }

  /// Get gift wrap record by its decrypted rumor ID (email ID).
  Future<Map<String, dynamic>?> getByRumorId(String rumorId) async {
    final row =
        await (_db.select(_db.giftWraps)
              ..where((w) => w.rumorId.equals(rumorId))
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _toMap(row);
  }

  /// Get a gift wrap by rumor ID only if it belongs to [recipientPubkey].
  Future<Map<String, dynamic>?> getByRumorIdForRecipient(
    String rumorId, {
    required String recipientPubkey,
  }) async {
    final row =
        await (_db.select(_db.giftWraps)
              ..where(
                (w) =>
                    w.rumorId.equals(rumorId) &
                    w.recipientPubkey.equals(recipientPubkey),
              )
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _toMap(row);
  }

  /// The seal and rumor already recorded for [giftWrapId], if it got that far.
  ///
  /// Reading them back is what makes a retry cheap: the approvals a remote
  /// signer needed to produce them are not asked for a second time.
  Future<UnwrappedGiftWrap?> getUnsealed(String giftWrapId) async {
    final row = await _row(giftWrapId);
    final seal = row?.seal;
    final rumor = row?.rumor;
    if (seal == null || rumor == null) return null;
    return UnwrappedGiftWrap(seal: _decode(seal), rumor: _decode(rumor));
  }

  /// Record why the last attempt on [giftWrapId] stopped, and count it.
  ///
  /// The stage is left alone: a failure never undoes what was already opened.
  Future<void> recordFailure({
    required String giftWrapId,
    required GiftWrapFailure failure,
  }) async {
    await (_db.update(
      _db.giftWraps,
    )..where((w) => w.id.equals(giftWrapId))).write(
      GiftWrapsCompanion.custom(
        failure: Constant(failure.name),
        attempts: _db.giftWraps.attempts + const Constant(1),
      ),
    );
  }

  /// Mark a gift wrap as fully processed. Terminal: nothing reopens it.
  Future<void> markStored(String eventId) async {
    await (_db.update(_db.giftWraps)..where((w) => w.id.equals(eventId))).write(
      GiftWrapsCompanion(stage: Value(_stored), failure: const Value(null)),
    );
  }

  /// Remove a gift wrap record.
  Future<void> remove(String eventId) async {
    await (_db.delete(_db.giftWraps)..where((w) => w.id.equals(eventId))).go();
  }

  /// Remove gift wrap records by their decrypted rumor ids.
  Future<void> removeByRumorIds(Iterable<String> rumorIds) async {
    final uniqueIds = rumorIds.toSet().toList();
    if (uniqueIds.isEmpty) return;

    await (_db.delete(
      _db.giftWraps,
    )..where((w) => w.id.isIn(uniqueIds) | w.rumorId.isIn(uniqueIds))).go();
  }

  /// Outer event ids of [recipientPubkey]'s wraps carrying [rumorIds].
  ///
  /// Deletions target the rumor id, which is only readable after decryption;
  /// callers use this to tombstone the wraps themselves.
  Future<List<String>> getIdsByRumorIdsForRecipient(
    Iterable<String> rumorIds, {
    required String recipientPubkey,
  }) async {
    final uniqueIds = rumorIds.toSet().toList();
    if (uniqueIds.isEmpty) return [];

    final rows =
        await (_db.selectOnly(_db.giftWraps)
              ..addColumns([_db.giftWraps.id])
              ..where(
                _db.giftWraps.rumorId.isIn(uniqueIds) &
                    _db.giftWraps.recipientPubkey.equals(recipientPubkey),
              ))
            .get();
    return rows.map((r) => r.read(_db.giftWraps.id)!).toList();
  }

  /// Remove gift wrap records by rumor id only if they belong to [recipientPubkey].
  Future<void> removeByRumorIdsForRecipient(
    Iterable<String> rumorIds, {
    required String recipientPubkey,
  }) async {
    final uniqueIds = rumorIds.toSet().toList();
    if (uniqueIds.isEmpty) return;

    await (_db.delete(_db.giftWraps)..where(
          (w) =>
              w.rumorId.isIn(uniqueIds) &
              w.recipientPubkey.equals(recipientPubkey),
        ))
        .go();
  }

  /// Get a single unprocessed gift wrap event by ID.
  Future<Nip01Event?> getUnprocessed(
    String eventId, {
    String? recipientPubkey,
  }) async {
    final row = await _row(eventId, recipientPubkey: recipientPubkey);
    if (row == null || row.stage == _stored) return null;
    return _decode(row.event);
  }

  /// Every gift wrap still owed work, with what stopped it.
  Future<List<FailedGiftWrap>> getUnfinished({
    String? recipientPubkey,
    int? limit,
  }) async {
    final statement = _db.select(_db.giftWraps)
      ..where((w) => _unfinishedFor(w, recipientPubkey));
    if (limit != null) statement.limit(limit);
    final rows = await statement.get();
    return rows
        .map(
          (r) =>
              FailedGiftWrap(event: _decode(r.event), progress: _progressOf(r)),
        )
        .toList();
  }

  /// How many gift wraps are still owed work and can still succeed.
  ///
  /// Permanent failures are left out: anyone can address a malformed wrap to
  /// an account, so a count a stranger inflates is not worth showing.
  Future<int> getFailedCount({String? recipientPubkey}) async {
    final w = _db.giftWraps;
    final total = countAll();
    final row =
        await (_db.selectOnly(w)
              ..addColumns([total])
              ..where(
                _unfinishedFor(w, recipientPubkey) &
                    (w.failure.isNull() |
                        w.failure.isNotValue(GiftWrapFailure.permanent.name)),
              ))
            .getSingle();
    return row.read(total)!;
  }

  Future<void> clearAll({String? recipientPubkey}) async {
    final statement = _db.delete(_db.giftWraps);
    if (recipientPubkey != null) {
      statement.where((w) => w.recipientPubkey.equals(recipientPubkey));
    }
    await statement.go();
  }

  /// Anything short of [GiftWrapStage.stored] is still owed work.
  Expression<bool> _unfinishedFor(GiftWraps w, String? recipientPubkey) {
    final unfinished = w.stage.isNotValue(_stored);
    if (recipientPubkey == null) return unfinished;
    return unfinished & w.recipientPubkey.equals(recipientPubkey);
  }

  Future<GiftWrapRow?> _row(String giftWrapId, {String? recipientPubkey}) {
    return (_db.select(_db.giftWraps)..where((w) {
          final byId = w.id.equals(giftWrapId);
          if (recipientPubkey == null) return byId;
          return byId & w.recipientPubkey.equals(recipientPubkey);
        }))
        .getSingleOrNull();
  }

  GiftWrapProgress _progressOf(GiftWrapRow row) {
    final failure = row.failure;
    return GiftWrapProgress(
      stage: GiftWrapStage.values.firstWhere(
        (stage) => stage.name == row.stage,
        orElse: () => GiftWrapStage.saved,
      ),
      failure: failure == null
          ? null
          : GiftWrapFailure.values.firstWhere(
              (candidate) => candidate.name == failure,
            ),
      attempts: row.attempts,
    );
  }

  static Map<String, dynamic> _toMap(GiftWrapRow row) => {
    'recipientPubkey': row.recipientPubkey,
    'event': jsonDecode(row.event),
    if (row.seal != null) 'seal': jsonDecode(row.seal!),
    if (row.rumor != null) 'rumor': jsonDecode(row.rumor!),
    if (row.rumorId != null) 'rumorId': row.rumorId,
    'stage': row.stage,
    'attempts': row.attempts,
    if (row.failure != null) 'failure': row.failure,
  };

  static String _encode(Nip01Event event) =>
      jsonEncode(Nip01EventModel.fromEntity(event).toJson());

  static Nip01Event _decode(String json) =>
      Nip01EventModel.fromJson(jsonDecode(json) as Map);
}
