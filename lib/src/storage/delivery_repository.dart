import 'dart:convert';

import 'package:drift/drift.dart';

import 'database.dart';

/// What a send queued for one recipient of an email.
class DeliveryTarget {
  /// A Nostr recipient, the sender for its own copy, or a bridge.
  final String recipientPubkey;

  /// The addresses a bridge relays to, empty for any other recipient.
  final List<String> smtpAddresses;

  /// The gift wrap, or the public event the recipient reads.
  final String eventId;

  /// The relays the recipient reads [eventId] from.
  final List<String> relays;

  /// The blob holding the email, when it is too large to travel inline.
  final String? blobSha256;

  const DeliveryTarget({
    required this.recipientPubkey,
    this.smtpAddresses = const [],
    required this.eventId,
    required this.relays,
    this.blobSha256,
  });
}

/// The [DeliveryTarget]s of each email sent from this device.
class DeliveryRepository {
  final NostrMailDatabase _db;

  DeliveryRepository(this._db);

  Future<void> saveAll(
    String emailId, {
    required String senderPubkey,
    required Iterable<DeliveryTarget> targets,
  }) async {
    await _db.batch(
      (b) => b.insertAllOnConflictUpdate(_db.deliveries, [
        for (final target in targets)
          DeliveryRow(
            emailId: emailId,
            senderPubkey: senderPubkey,
            recipientPubkey: target.recipientPubkey,
            smtpAddresses: jsonEncode(target.smtpAddresses),
            eventId: target.eventId,
            relays: jsonEncode(target.relays),
            blobSha256: target.blobSha256,
          ),
      ]),
    );
  }

  Future<List<DeliveryTarget>> getAll(
    String emailId, {
    required String senderPubkey,
  }) async {
    final rows =
        await (_db.select(_db.deliveries)..where(
              (d) =>
                  d.emailId.equals(emailId) &
                  d.senderPubkey.equals(senderPubkey),
            ))
            .get();
    return [
      for (final row in rows)
        DeliveryTarget(
          recipientPubkey: row.recipientPubkey,
          smtpAddresses: (jsonDecode(row.smtpAddresses) as List).cast<String>(),
          eventId: row.eventId,
          relays: (jsonDecode(row.relays) as List).cast<String>(),
          blobSha256: row.blobSha256,
        ),
    ];
  }

  /// Delete the deliveries sent by [senderPubkey], or pass `null` to wipe
  /// the entire store across all accounts.
  Future<void> clearAll({String? senderPubkey}) async {
    final statement = _db.delete(_db.deliveries);
    if (senderPubkey != null) {
      statement.where((d) => d.senderPubkey.equals(senderPubkey));
    }
    await statement.go();
  }
}
