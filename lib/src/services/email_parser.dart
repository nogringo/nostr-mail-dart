import 'package:enough_mail_plus/enough_mail.dart';

/// Email parser for building RFC 2822 MIME messages.
///
/// For parsing Nostr events (kind 1301), use `parseEmailEvent` instead.
class EmailParser {
  /// Build a RFC 2822 MIME email from fields.
  ///
  /// Used for creating emails to send.
  String build({
    required MailAddress from,
    required List<MailAddress> to,
    List<MailAddress>? cc,
    List<MailAddress>? bcc,
    required String subject,
    required String body,
    String? htmlBody,
    DateTime? date,
  }) {
    final builder = MessageBuilder.prepareMultipartAlternativeMessage();
    builder.from = [from];
    builder.to = to;
    if (cc != null) builder.cc = cc;
    if (bcc != null) builder.bcc = bcc;
    builder.subject = subject;
    if (date != null) builder.date = date;
    builder.addTextPlain(body);
    if (htmlBody != null) {
      builder.addTextHtml(htmlBody, transferEncoding: TransferEncoding.base64);
    }

    final message = builder.buildMimeMessage();
    return message.renderMessage();
  }
}
