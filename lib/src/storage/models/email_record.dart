import '../../models/attachment_ref.dart';
import '../../models/email.dart';

/// An email as the local store sees it.
///
/// Heavy attachment payloads live in [BlossomCache], not here. This record
/// only carries [attachmentRefs] (filename, size, sha256) and a light MIME
/// envelope whose attachment parts have empty bodies, so list queries never
/// pull megabytes off disk.
///
/// [folder], [isRead], [isStarred] and [labels] are derived from the labels
/// table: filled when a record is read, ignored when one is saved.
class EmailRecord {
  final String id;
  final String senderPubkey;
  final String recipientPubkey;
  final bool isPublic;

  /// MIME with attachment bodies emptied. Parsable by
  /// `MimeMessage.parseFromText`. Typically a few KB even for emails that
  /// originally carried large attachments.
  final String lightMimeText;

  /// One ref per attachment that was extracted, in original MIME tree order.
  final List<AttachmentRef> attachmentRefs;

  // ── Blossom routing (only for emails stored as encrypted Blossom blobs) ──

  /// sha256 of the encrypted Blossom blob. `null` for inline emails.
  final String? blossomHash;

  /// AES-GCM key used to encrypt the blob. `null` for inline emails.
  final String? decryptionKey;

  /// AES-GCM nonce used to encrypt the blob. `null` for inline emails.
  final String? decryptionNonce;

  /// Nostr event createdAt (epoch seconds).
  final int createdAt;

  /// MIME date or fallback to createdAt (epoch seconds).
  final int date;

  // ── Extracted from MIME, indexed for search ─────────────────────────────

  final String from;
  final String subject;

  /// Plain-text body (HTML stripped if needed).
  final String bodyPlain;

  // ── Derived from the labels table ───────────────────────────────────────

  /// Current folder. Mutually exclusive: inbox, sent, trash, archive, spam.
  final String folder;

  final bool isRead;
  final bool isStarred;

  /// Non-folder labels (custom tags).
  final List<String> labels;

  final bool isBridged;

  const EmailRecord({
    required this.id,
    required this.senderPubkey,
    required this.recipientPubkey,
    required this.lightMimeText,
    required this.attachmentRefs,
    required this.isPublic,
    required this.createdAt,
    required this.date,
    required this.from,
    required this.subject,
    required this.bodyPlain,
    required this.folder,
    required this.isBridged,
    this.isRead = false,
    this.isStarred = false,
    this.labels = const [],
    this.blossomHash,
    this.decryptionKey,
    this.decryptionNonce,
  });

  /// The mailbox an email lands in before any folder label: sent for a
  /// self-copy, inbox otherwise.
  static String naturalFolder({
    required String senderPubkey,
    required String recipientPubkey,
  }) => senderPubkey == recipientPubkey ? 'sent' : 'inbox';

  /// Build an [EmailRecord] from a public [Email] model that has already
  /// gone through attachment extraction.
  factory EmailRecord.fromEmail(Email email) {
    return EmailRecord(
      id: email.id,
      senderPubkey: email.senderPubkey,
      recipientPubkey: email.recipientPubkey,
      lightMimeText: email.lightMimeText,
      attachmentRefs: email.attachmentRefs,
      blossomHash: email.blossomHash,
      decryptionKey: email.decryptionKey,
      decryptionNonce: email.decryptionNonce,
      isPublic: email.isPublic,
      createdAt: email.createdAt.millisecondsSinceEpoch ~/ 1000,
      date: email.date.millisecondsSinceEpoch ~/ 1000,
      from: email.sender?.email ?? email.mime.fromEmail ?? '',
      subject: email.subject ?? '',
      bodyPlain: email.textBody ?? email.body,
      folder: naturalFolder(
        senderPubkey: email.senderPubkey,
        recipientPubkey: email.recipientPubkey,
      ),
      isBridged: email.isBridged,
    );
  }

  Email toEmail() => Email(
    id: id,
    senderPubkey: senderPubkey,
    recipientPubkey: recipientPubkey,
    lightMimeText: lightMimeText,
    attachmentRefs: attachmentRefs,
    blossomHash: blossomHash,
    decryptionKey: decryptionKey,
    decryptionNonce: decryptionNonce,
    createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt * 1000),
    isPublic: isPublic,
    isBridged: isBridged,
  );
}
