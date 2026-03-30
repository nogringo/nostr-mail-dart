import 'package:enough_mail_plus/enough_mail.dart';

import '../exceptions.dart';
import '../models/email.dart';

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
    required DateTime createdAt,
  }) async {
    try {
      // Unfold headers
      final unfolded = rawContent.replaceAll(RegExp(r'\r?\n[ \t]+'), '');

      return Email(
        id: eventId,
        senderPubkey: senderPubkey,
        recipientPubkey: recipientPubkey,
        rawContent: unfolded,
        createdAt: createdAt,
      );
    } catch (e) {
      throw EmailParseException(e.toString());
    }
  }
}
