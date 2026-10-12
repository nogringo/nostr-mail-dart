import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:enough_mail_plus/enough_mail.dart';

import '../models/draft.dart';
import '../models/gift_wrap_state.dart';
import '../utils/attachment_names.dart';
import '../utils/body_preview.dart';
import 'database.dart';
import 'mail_address_codec.dart';

/// Repository for drafts: the current version of each one, and what the
/// signer made of every draft wrap.
class DraftRepository {
  final NostrMailDatabase _db;

  DraftRepository(this._db);

  Future<DraftDecryptionRow?> getDecryption(
    String eventId, {
    required String recipientPubkey,
  }) {
    return (_db.select(_db.draftDecryptions)..where(
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
        .into(_db.draftDecryptions)
        .insert(
          DraftDecryptionsCompanion.insert(
            eventId: eventId,
            recipientPubkey: recipientPubkey,
            plaintext: Value(plaintext),
          ),
          onConflict: DoUpdate(
            (_) => DraftDecryptionsCompanion(
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
        .into(_db.draftDecryptions)
        .insert(
          DraftDecryptionsCompanion.insert(
            eventId: eventId,
            recipientPubkey: recipientPubkey,
            failure: Value(failure.name),
            attempts: const Value(1),
          ),
          onConflict: DoUpdate(
            (old) => DraftDecryptionsCompanion.custom(
              failure: Constant(failure.name),
              attempts: old.attempts + const Constant(1),
            ),
          ),
        );
  }

  /// The current version of [draftId], deleted or not.
  Future<DraftRow?> get(String draftId, {required String recipientPubkey}) {
    return (_db.select(_db.drafts)..where(
          (d) =>
              d.draftId.equals(draftId) &
              d.recipientPubkey.equals(recipientPubkey),
        ))
        .getSingleOrNull();
  }

  /// Make the draft wrap [eventId] the current version of [draftId]. A null
  /// [message] is a blank wrap: the draft is deleted.
  Future<void> saveVersion({
    required String draftId,
    required String recipientPubkey,
    required String eventId,
    required int createdAt,
    MimeMessage? message,
  }) async {
    await _db
        .into(_db.drafts)
        .insertOnConflictUpdate(
          DraftRow(
            recipientPubkey: recipientPubkey,
            draftId: draftId,
            eventId: eventId,
            createdAt: createdAt,
            deleted: message == null,
            fromAddress: message?.fromEmail,
            toAddresses: encodeAddresses(message?.to ?? const []),
            ccAddresses: encodeAddresses(message?.cc ?? const []),
            bccAddresses: encodeAddresses(message?.bcc ?? const []),
            subject: message?.decodeSubject() ?? '',
            preview: message == null ? '' : bodyPreview(message),
            attachmentNames: jsonEncode(
              message == null ? const <String>[] : attachmentNames(message),
            ),
          ),
        );
  }

  /// [draftId], unless it is unknown or deleted.
  Future<Draft?> find(String draftId, {required String recipientPubkey}) {
    return (_db.select(_db.drafts)..where(
          (d) =>
              d.draftId.equals(draftId) &
              d.recipientPubkey.equals(recipientPubkey) &
              d.deleted.not(),
        ))
        .map(_toDraft)
        .getSingleOrNull();
  }

  /// The drafts of [recipientPubkey], most recently saved first.
  Future<List<Draft>> list({required String recipientPubkey}) =>
      _listQuery(recipientPubkey).get();

  /// Reactive [list].
  Stream<List<Draft>> watch({required String recipientPubkey}) =>
      _listQuery(recipientPubkey).watch();

  Selectable<Draft> _listQuery(String recipientPubkey) {
    return (_db.select(_db.drafts)
          ..where(
            (d) => d.recipientPubkey.equals(recipientPubkey) & d.deleted.not(),
          )
          ..orderBy([(d) => OrderingTerm.desc(d.createdAt)]))
        .map(_toDraft);
  }

  static Draft _toDraft(DraftRow row) {
    List<String> emails(String json) =>
        decodeAddresses(json).map((a) => a.email).toList();
    return Draft(
      draftId: row.draftId,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt * 1000),
      from: row.fromAddress,
      to: emails(row.toAddresses),
      cc: emails(row.ccAddresses),
      bcc: emails(row.bccAddresses),
      subject: row.subject,
      bodyPreview: row.preview,
      attachmentNames: (jsonDecode(row.attachmentNames) as List).cast<String>(),
    );
  }

  /// Wipes the drafts and their decryptions. Asked for by the user, unlike the
  /// drop a schema change performs, so the decryptions go too.
  Future<void> clearAll({String? recipientPubkey}) async {
    await _db.transaction(() async {
      final drafts = _db.delete(_db.drafts);
      final decryptions = _db.delete(_db.draftDecryptions);
      if (recipientPubkey != null) {
        drafts.where((d) => d.recipientPubkey.equals(recipientPubkey));
        decryptions.where((d) => d.recipientPubkey.equals(recipientPubkey));
      }
      await drafts.go();
      await decryptions.go();
    });
  }
}
