import 'package:ndk/ndk.dart' show Nip01Event, Nip01EventModel;
import 'package:sembast/sembast.dart';

import '../models/gift_wrap_state.dart';
import '../models/unwrapped_gift_wrap.dart';

/// Repository for raw NIP-59 gift-wrap events.
class GiftWrapRepository {
  final Database _db;
  final _store = stringMapStoreFactory.store('gift_wraps');

  GiftWrapRepository(this._db);

  static final _stored = GiftWrapStage.stored.name;

  /// Anything short of [GiftWrapStage.stored] is still owed work.
  static final _unfinished = Filter.notEquals('stage', _stored);

  /// Save a gift wrap event if new. Returns true if it was inserted.
  Future<bool> save(Nip01Event event, {required String recipientPubkey}) async {
    final existing = await _store.record(event.id).get(_db);
    if (existing != null) return false;
    await _store.record(event.id).put(_db, {
      'recipientPubkey': recipientPubkey,
      'event': Nip01EventModel.fromEntity(event).toJson(),
      'stage': GiftWrapStage.saved.name,
      'attempts': 0,
    });
    return true;
  }

  /// Get a gift wrap record by its globally unique outer event ID.
  Future<Map<String, dynamic>?> getById(String giftWrapId) async {
    final record = await _store.record(giftWrapId).get(_db);
    if (record == null) return null;
    return record.cast<String, dynamic>();
  }

  /// Get a gift wrap by ID only if it belongs to [recipientPubkey].
  Future<Map<String, dynamic>?> getByIdForRecipient(
    String giftWrapId, {
    required String recipientPubkey,
  }) async {
    final record = await getById(giftWrapId);
    if (record == null) return null;
    if (record['recipientPubkey'] != recipientPubkey) return null;
    return record;
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
    final existing = await _store.record(giftWrapId).get(_db);
    if (existing == null) return;
    await _store
        .record(giftWrapId)
        .put(
          _db,
          {
            ...existing,
            'seal': Nip01EventModel.fromEntity(seal).toJson(),
            'rumor': Nip01EventModel.fromEntity(rumor).toJson(),
            'rumorId': rumor.id,
            'stage': GiftWrapStage.unsealed.name,
          }..remove('failure'),
        );
  }

  /// Get gift wrap record by its decrypted rumor ID (email ID).
  Future<Map<String, dynamic>?> getByRumorId(String rumorId) async {
    final finder = Finder(filter: Filter.equals('rumorId', rumorId));
    final record = await _store.findFirst(_db, finder: finder);
    return record?.value;
  }

  /// Get a gift wrap by rumor ID only if it belongs to [recipientPubkey].
  Future<Map<String, dynamic>?> getByRumorIdForRecipient(
    String rumorId, {
    required String recipientPubkey,
  }) async {
    final finder = Finder(
      filter: Filter.and([
        Filter.equals('rumorId', rumorId),
        Filter.equals('recipientPubkey', recipientPubkey),
      ]),
    );
    final record = await _store.findFirst(_db, finder: finder);
    return record?.value;
  }

  /// The seal and rumor already recorded for [giftWrapId], if it got that far.
  ///
  /// Reading them back is what makes a retry cheap: the approvals a remote
  /// signer needed to produce them are not asked for a second time.
  Future<UnwrappedGiftWrap?> getUnsealed(String giftWrapId) async {
    final record = await _store.record(giftWrapId).get(_db);
    final seal = record?['seal'];
    final rumor = record?['rumor'];
    if (seal == null || rumor == null) return null;
    return UnwrappedGiftWrap(
      seal: Nip01EventModel.fromJson(seal as Map),
      rumor: Nip01EventModel.fromJson(rumor as Map),
    );
  }

  /// Where [giftWrapId] stands, or null if it is unknown.
  Future<GiftWrapProgress?> progressOf(String giftWrapId) async {
    final record = await _store.record(giftWrapId).get(_db);
    if (record == null) return null;
    final failure = record['failure'];
    return GiftWrapProgress(
      stage: GiftWrapStage.values.firstWhere(
        (stage) => stage.name == record['stage'],
        orElse: () => GiftWrapStage.saved,
      ),
      failure: failure == null
          ? null
          : GiftWrapFailure.values.firstWhere(
              (candidate) => candidate.name == failure,
            ),
      attempts: record['attempts'] as int? ?? 0,
    );
  }

  /// Record why the last attempt on [giftWrapId] stopped, and count it.
  ///
  /// The stage is left alone: a failure never undoes what was already opened.
  Future<void> recordFailure({
    required String giftWrapId,
    required GiftWrapFailure failure,
  }) async {
    final existing = await _store.record(giftWrapId).get(_db);
    if (existing == null) return;
    await _store.record(giftWrapId).put(_db, {
      ...existing,
      'failure': failure.name,
      'attempts': (existing['attempts'] as int? ?? 0) + 1,
    });
  }

  /// Mark a gift wrap as fully processed. Terminal: nothing reopens it.
  Future<void> markStored(String eventId) async {
    final existing = await _store.record(eventId).get(_db);
    if (existing == null) return;
    await _store
        .record(eventId)
        .put(_db, {...existing, 'stage': _stored}..remove('failure'));
  }

  /// Remove a gift wrap record.
  Future<void> remove(String eventId) async {
    await _store.record(eventId).delete(_db);
  }

  /// Remove gift wrap records by their decrypted rumor ids.
  Future<void> removeByRumorIds(Iterable<String> rumorIds) async {
    final uniqueIds = rumorIds.toSet().toList();
    if (uniqueIds.isEmpty) return;

    final finder = Finder(filter: Filter.inList('rumorId', uniqueIds));
    final keys = await _store.findKeys(_db, finder: finder);
    final recordsToDelete = {...keys, ...uniqueIds};
    for (final key in recordsToDelete) {
      await _store.record(key).delete(_db);
    }
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

    final finder = Finder(
      filter: Filter.and([
        Filter.inList('rumorId', uniqueIds),
        Filter.equals('recipientPubkey', recipientPubkey),
      ]),
    );
    final keys = await _store.findKeys(_db, finder: finder);
    return keys.cast<String>();
  }

  /// Remove gift wrap records by rumor id only if they belong to [recipientPubkey].
  Future<void> removeByRumorIdsForRecipient(
    Iterable<String> rumorIds, {
    required String recipientPubkey,
  }) async {
    final uniqueIds = rumorIds.toSet().toList();
    if (uniqueIds.isEmpty) return;

    final finder = Finder(
      filter: Filter.and([
        Filter.inList('rumorId', uniqueIds),
        Filter.equals('recipientPubkey', recipientPubkey),
      ]),
    );
    final recordsToDelete = await _store.findKeys(_db, finder: finder);
    for (final key in recordsToDelete) {
      await _store.record(key).delete(_db);
    }
  }

  /// Get a single unprocessed gift wrap event by ID.
  Future<Nip01Event?> getUnprocessed(
    String eventId, {
    String? recipientPubkey,
  }) async {
    final record = recipientPubkey == null
        ? await getById(eventId)
        : await getByIdForRecipient(eventId, recipientPubkey: recipientPubkey);
    if (record == null || record['stage'] == _stored) return null;
    return Nip01EventModel.fromJson(record['event'] as Map);
  }

  /// Get unprocessed gift wrap events.
  Future<List<Nip01Event>> getUnprocessedEvents({
    String? recipientPubkey,
    int? limit,
  }) async {
    final finder = Finder(
      filter: _unfinishedFor(recipientPubkey),
      limit: limit,
    );
    final records = await _store.find(_db, finder: finder);
    return records
        .map((r) => Nip01EventModel.fromJson(r.value['event'] as Map))
        .cast<Nip01Event>()
        .toList();
  }

  /// Get count of unprocessed (failed) events.
  Future<int> getFailedCount({String? recipientPubkey}) =>
      _store.count(_db, filter: _unfinishedFor(recipientPubkey));

  Filter _unfinishedFor(String? recipientPubkey) => recipientPubkey == null
      ? _unfinished
      : Filter.and([
          _unfinished,
          Filter.equals('recipientPubkey', recipientPubkey),
        ]);

  Future<void> clearAll({String? recipientPubkey}) async {
    if (recipientPubkey == null) {
      await _store.delete(_db);
      return;
    }
    await _store.delete(
      _db,
      finder: Finder(filter: Filter.equals('recipientPubkey', recipientPubkey)),
    );
  }
}
