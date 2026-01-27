import 'package:enough_mail/enough_mail.dart';

import '../exceptions.dart';
import '../models/email.dart';
import '../utils/html_utils.dart';

class EmailParser {
  Email parse({
    required String rawContent,
    required String eventId,
    required String senderPubkey,
    required String recipientPubkey,
  }) {
    try {
      // Unfold headers: remove CRLF/LF followed by whitespace
      final unfolded = rawContent.replaceAll(RegExp(r'\r?\n[ \t]+'), '');
      final mimeMessage = MimeMessage.parseFromText(unfolded);

      final from = mimeMessage.fromEmail ?? '';
      final to = mimeMessage.to?.isNotEmpty == true
          ? mimeMessage.to!.first.email
          : '';
      final subject = mimeMessage.decodeSubject() ?? '';
      var body = mimeMessage.decodeTextPlainPart() ?? '';

      // Fallback to HTML content (stripped of tags) if text/plain is empty
      if (body.isEmpty) {
        final html = mimeMessage.decodeTextHtmlPart();
        if (html != null && html.isNotEmpty) {
          body = stripHtmlTags(html);
        }
      }

      final date = mimeMessage.decodeDate() ?? DateTime.now();

      return Email(
        id: eventId,
        from: from,
        to: to,
        subject: subject,
        body: body,
        date: date,
        senderPubkey: senderPubkey,
        recipientPubkey: recipientPubkey,
        rawContent: unfolded,
      );
    } catch (e) {
      throw EmailParseException(e.toString());
    }
  }

  String build({
    required String from,
    required String to,
    required String subject,
    required String body,
    String? htmlBody,
  }) {
    final builder = MessageBuilder.prepareMultipartAlternativeMessage();
    builder.from = [MailAddress(null, from)];
    builder.to = [MailAddress(null, to)];
    builder.subject = subject;
    builder.addTextPlain(body);
    if (htmlBody != null) {
      builder.addTextHtml(htmlBody);
    }

    final message = builder.buildMimeMessage();
    return message.renderMessage();
  }
}
