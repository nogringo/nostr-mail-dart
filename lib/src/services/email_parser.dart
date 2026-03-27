import 'package:enough_mail_plus/enough_mail.dart';

import '../exceptions.dart';
import '../models/email.dart';
import '../utils/html_utils.dart';

/// Email parser for building and parsing RFC 2822 MIME messages.
///
/// For parsing Nostr events (kind 1301), use [parseEmailEvent] instead.
class EmailParser {
  /// Build a RFC 2822 MIME email from fields.
  ///
  /// Used for creating emails to send.
  String build({
    required String from,
    required String to,
    required String subject,
    required String body,
    String? htmlBody,
  }) {
    final builder = MessageBuilder.prepareMultipartAlternativeMessage();
    builder.from = [MailAddress.parse(from)];
    builder.to = [MailAddress.parse(to)];
    builder.subject = subject;
    builder.addTextPlain(body);
    if (htmlBody != null) {
      builder.addTextHtml(htmlBody, transferEncoding: TransferEncoding.base64);
    }

    final message = builder.buildMimeMessage();
    return message.renderMessage();
  }

  /// Parse a MIME string into an [Email] object.
  ///
  /// Use this for parsing inline MIME content.
  /// For parsing Nostr events (kind 1301), use [parseEmailEvent].
  Future<Email> parseMime({
    required String rawContent,
    required String eventId,
    required String senderPubkey,
    required String recipientPubkey,
  }) async {
    try {
      // Unfold headers
      final unfolded = rawContent.replaceAll(RegExp(r'\r?\n[ \t]+'), '');
      final mimeMessage = MimeMessage.parseFromText(unfolded);

      final from = mimeMessage.fromEmail ?? '';
      final to = mimeMessage.to?.isNotEmpty == true
          ? mimeMessage.to!.first.email
          : '';
      final subject = mimeMessage.decodeSubject() ?? '';
      var body = mimeMessage.decodeTextPlainPart() ?? '';

      // Fallback to HTML if text/plain is empty
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
}
