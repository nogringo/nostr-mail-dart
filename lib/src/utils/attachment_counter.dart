import 'package:enough_mail_plus/enough_mail.dart';

/// Count attachments in a MIME message.
///
/// Recursively walks all parts and counts those that have a disposition of
/// [ContentDisposition.attachment] or a non-empty filename.
int countAttachments(MimeMessage mime) {
  return _countParts(mime);
}

int _countParts(MimePart part) {
  var count = 0;

  // Check current part
  final header = part.getHeaderContentDisposition();
  final filename = part.decodeFileName();
  if (header?.disposition == ContentDisposition.attachment ||
      (filename != null && filename.isNotEmpty)) {
    count++;
  }

  // Recurse into children
  final children = part.parts;
  if (children != null) {
    for (final child in children) {
      count += _countParts(child);
    }
  }

  return count;
}
