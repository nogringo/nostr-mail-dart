import 'package:enough_mail_plus/enough_mail.dart';

/// File names of the attachments of [message], in MIME order.
List<String> attachmentNames(MimeMessage message) {
  final names = <String>[];
  void walk(MimePart part) {
    final children = part.parts;
    if (children != null && children.isNotEmpty) {
      for (final child in children) {
        walk(child);
      }
      return;
    }
    final disposition = part.getHeaderContentDisposition()?.disposition;
    final filename = part.decodeFileName();
    final isAttachment =
        disposition == ContentDisposition.attachment ||
        (filename != null && filename.isNotEmpty);
    if (isAttachment && filename != null && filename.isNotEmpty) {
      names.add(filename);
    }
  }

  walk(message);
  return names;
}
