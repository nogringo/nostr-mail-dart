import 'package:enough_mail_plus/enough_mail.dart';

import 'attachment_ref.dart';

/// One row of a mailbox listing.
///
/// Carries what a list draws and nothing more. Unlike `Email`, it never reads
/// `lightMimeText` and never parses MIME, so a page of rows costs a few
/// hundred bytes each instead of the whole message body twice over. Every
/// field comes from a column the store already indexes.
///
/// Load the full `Email` with `client.getEmail(summary.id)` when the user
/// opens a row.
class EmailSummary {
  final String id;
  final String senderPubkey;

  /// Sender address as indexed at sync time. For a native nostr sender this
  /// is `<npub>@nostr`, and their real name lives in the profile behind
  /// [senderPubkey]; resolve that first and fall back to these.
  final String from;

  /// Sender display name, when the MIME carried one. Usually present for a
  /// bridged sender, absent for a native nostr one.
  final String? fromName;

  final List<MailAddress> to;
  final List<MailAddress> cc;

  /// Only ever populated on the account's own sent copies.
  final List<MailAddress> bcc;

  final String subject;

  /// Leading characters of the plain-text body, for the list preview.
  final String preview;

  /// MIME date, falling back to the Nostr event date.
  final DateTime date;

  /// Mutually exclusive: inbox, sent, trash, archive, spam.
  final String folder;

  final bool isRead;
  final bool isStarred;

  /// Non-folder labels (custom tags).
  final List<String> labels;

  /// One ref per attachment, in original MIME tree order. Metadata only
  /// (filename, content type, size, sha256), so a row stays cheap even for a
  /// message carrying megabytes. Load the bytes of one with
  /// `client.getAttachmentBytes`.
  final List<AttachmentRef> attachmentRefs;

  final bool isPublic;
  final bool isBridged;

  const EmailSummary({
    required this.id,
    required this.senderPubkey,
    required this.from,
    required this.subject,
    required this.preview,
    required this.date,
    required this.folder,
    required this.isRead,
    required this.isStarred,
    required this.isPublic,
    required this.isBridged,
    this.fromName,
    this.to = const [],
    this.cc = const [],
    this.bcc = const [],
    this.attachmentRefs = const [],
    this.labels = const [],
  });

  bool get hasAttachments => attachmentRefs.isNotEmpty;
}
