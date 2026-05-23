import '../models/email.dart';
import '../storage/models/email_record.dart';

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
  final from = email.sender?.email ?? email.mime.fromEmail ?? '';
  final subject = email.subject ?? '';
  final bodyPlain = email.textBody ?? email.body;
  final searchText =
      '${from.toLowerCase()} ${subject.toLowerCase()} ${bodyPlain.toLowerCase()}';

  return EmailRecord.fromEmail(
    email,
    folder: folder,
    searchText: searchText,
    labels: labels,
    isRead: isRead,
    isStarred: isStarred,
  );
}
