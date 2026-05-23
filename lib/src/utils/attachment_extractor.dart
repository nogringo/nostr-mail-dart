import 'package:blossom_cache/blossom_cache.dart';
import 'package:enough_mail_plus/enough_mail.dart';

import '../models/attachment_ref.dart';
import '../models/extracted_mime.dart';

/// Strip attachment payloads out of [mime] and store them in [cache].
///
/// The decoded bytes of each attachment part are written to [cache] keyed by
/// their sha256, then the part's body in [mime] is replaced with empty bytes.
/// Headers (Content-Type, Content-Disposition, filename, Content-ID, etc.)
/// are kept intact, so the rendered light MIME parses back identically apart
/// from missing payloads.
///
/// [mime] is mutated in place.
///
/// Attachments are stored unpinned: they participate in LRU eviction. They
/// can be regenerated from the original encrypted Blossom blob (which stays
/// pinned, separately) if the cache evicts them.
Future<ExtractedMime> extractAttachments({
  required MimeMessage mime,
  required BlossomCache cache,
}) async {
  final refs = <AttachmentRef>[];
  await _walk(mime, cache, refs);

  final buffer = StringBuffer();
  mime.render(buffer);
  return ExtractedMime(lightMimeText: buffer.toString(), refs: refs);
}

Future<void> _walk(
  MimePart part,
  BlossomCache cache,
  List<AttachmentRef> refs,
) async {
  // Force header parsing so they survive once we clear mimeData below.
  part.parse();

  final children = part.parts;
  if (children != null && children.isNotEmpty) {
    // Container part: drop the cached raw text so render() recurses through
    // the children list (which has already been parsed into MimePart nodes).
    part.mimeData = null;
    for (final child in children) {
      await _walk(child, cache, refs);
    }
    return;
  }

  if (!_isAttachment(part)) return;

  final bytes = part.decodeContentBinary();
  if (bytes == null || bytes.isEmpty) return;

  final contentType =
      part.getHeaderContentType()?.mediaType.text ?? 'application/octet-stream';
  final filename = part.decodeFileName();
  final contentId = _stripAngleBrackets(part.getHeaderValue('content-id'));

  final descriptor = await cache.put(bytes, type: contentType, pinned: false);

  refs.add(
    AttachmentRef(
      filename: filename,
      contentType: contentType,
      size: bytes.length,
      sha256: descriptor.sha256,
      contentId: contentId,
    ),
  );

  // Replace the body with an empty payload. containsHeader:false tells the
  // renderer to write the headers list itself before this empty body.
  part.mimeData = TextMimeData('', containsHeader: false);
}

String? _stripAngleBrackets(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.startsWith('<') && trimmed.endsWith('>')) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  return trimmed.isEmpty ? null : trimmed;
}

bool _isAttachment(MimePart part) {
  final disposition = part.getHeaderContentDisposition()?.disposition;
  if (disposition == ContentDisposition.attachment) return true;
  final filename = part.decodeFileName();
  return filename != null && filename.isNotEmpty;
}
