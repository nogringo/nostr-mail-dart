import 'package:enough_mail_plus/enough_mail.dart';

/// Utility functions for cleaning MIME messages.

/// Removes BCC headers from a MIME message string.
///
/// This removes both 'Bcc:' and 'Resent-Bcc:' headers by parsing
/// the message and calling removeHeader().
String removeBccHeaders(String mimeContent) {
  final message = MimeMessage.parseFromText(mimeContent);
  message.removeHeader('bcc');
  message.removeHeader('resent-bcc');
  return message.renderMessage();
}
