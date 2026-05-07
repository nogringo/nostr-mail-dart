import '../models/email.dart';
import '../storage/models/email_record.dart';
import 'attachment_counter.dart';

/// Build a denormalized [EmailRecord] from a public [Email] model.
///
/// [folder] must be provided by the caller ('inbox', 'sent', etc.).
EmailRecord buildEmailRecord({
  required Email email,
  required String folder,
  List<String> labels = const [],
  bool isRead = false,
  bool isStarred = false,
}) {
  final attachmentCount = countAttachments(email.mime);
  final from = email.sender?.email ?? email.mime.fromEmail ?? '';
  final subject = email.subject ?? '';
  final bodyPlain = email.textBody ?? email.body;
  final searchText =
      '${from.toLowerCase()} ${subject.toLowerCase()} ${bodyPlain.toLowerCase()}';

  return EmailRecord.fromEmail(
    email,
    folder: folder,
    searchText: searchText,
    attachmentCount: attachmentCount,
    labels: labels,
    isRead: isRead,
    isStarred: isStarred,
  );
}
