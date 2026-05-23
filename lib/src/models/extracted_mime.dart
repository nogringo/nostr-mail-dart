import 'attachment_ref.dart';

/// Result of stripping attachments from a parsed MIME message.
class ExtractedMime {
  /// The original MIME re-rendered with every attachment body emptied. Still
  /// a valid RFC 2822 message: every part keeps its headers, only the body
  /// payload is gone. Small enough to live in Sembast.
  final String lightMimeText;

  /// One ref per attachment that was extracted, in original MIME tree order.
  final List<AttachmentRef> refs;

  const ExtractedMime({required this.lightMimeText, required this.refs});
}
