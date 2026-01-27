import 'package:html/parser.dart' as html_parser;

/// Extract plain text from HTML content
String stripHtmlTags(String html) {
  final document = html_parser.parse(html);
  return document.body?.text ?? '';
}
