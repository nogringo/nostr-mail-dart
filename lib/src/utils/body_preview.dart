import 'package:enough_mail_plus/enough_mail.dart';

import 'html_to_text.dart';

/// The snippet a mailbox listing shows for [message]: the body as the reader
/// sees it, on one line, without quoted replies or the signature.
///
/// Empty when nothing is left, so the listing shows the subject alone.
String bodyPreview(MimeMessage message, {int maxLength = 200}) {
  final html = message.decodeTextHtmlPart();
  final text = html != null && html.trim().isNotEmpty
      ? htmlToText(html)
      : message.decodeTextPlainPart() ?? '';
  return textPreview(text, maxLength: maxLength);
}

/// [bodyPreview] for a body already rendered as plain text.
String textPreview(String text, {int maxLength = 200}) {
  final kept = <String>[];
  var inQuote = false;
  for (final line in text.split(RegExp(r'\r?\n'))) {
    // RFC 3676 section 4.3, also accepting the delimiter without its space.
    if (line.trimRight() == '--') break;
    if (line.startsWith('>')) {
      if (!inQuote) _dropAttribution(kept);
      inQuote = true;
      continue;
    }
    inQuote = false;
    kept.add(line);
  }

  final preview = kept.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (preview.length <= maxLength) return preview;
  var end = maxLength;
  if (_isLowSurrogate(preview.codeUnitAt(end))) end--;
  return preview.substring(0, end).trimRight();
}

/// Removes the `On <date>, <name> wrote:` line that introduces a quote.
void _dropAttribution(List<String> kept) {
  while (kept.isNotEmpty && kept.last.trim().isEmpty) {
    kept.removeLast();
  }
  if (kept.isNotEmpty && kept.last.trimRight().endsWith(':')) {
    kept.removeLast();
  }
}

bool _isLowSurrogate(int codeUnit) => codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;
