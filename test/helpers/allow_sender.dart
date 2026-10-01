import 'package:nostr_mail/src/storage/database.dart';
import 'package:nostr_mail/src/storage/sender_repository.dart';

/// Allows [senderKey] for [recipientPubkey] in the store alone, so its mail
/// lands in the inbox rather than in requests.
Future<void> allowSender(
  NostrMailDatabase database, {
  required String recipientPubkey,
  required String senderKey,
}) => SenderRepository(database).saveEntries(
  eventId: 'allow-$recipientPubkey-$senderKey',
  recipientPubkey: recipientPubkey,
  isAdd: true,
  createdAt: 0,
  entries: [(key: senderKey, verdict: 'allow')],
);
