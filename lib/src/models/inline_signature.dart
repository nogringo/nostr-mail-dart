import 'dart:typed_data';

import 'package:enough_mail_plus/enough_mail.dart';

/// A signature ready to send: its [html] points each image at a `cid:` URL,
/// and [images] are the inline MIME parts carrying them.
class InlineSignature {
  final String html;
  final List<InlineImage> images;

  const InlineSignature({required this.html, required this.images});

  /// Adds every image to [builder] as an inline part with its `Content-ID`.
  /// Images belong next to the HTML body, in a `multipart/related` part.
  void addImagesTo(PartBuilder builder) {
    for (final image in images) {
      builder
          .addBinary(
            image.bytes,
            MediaType.fromText(image.mimeType),
            disposition: ContentDispositionHeader.inline(),
          )
          .setHeader('Content-ID', '<${image.contentId}>');
    }
  }
}

class InlineImage {
  /// Without the angle brackets, as the `cid:` URL names it.
  final String contentId;
  final String mimeType;
  final Uint8List bytes;

  const InlineImage({
    required this.contentId,
    required this.mimeType,
    required this.bytes,
  });
}
