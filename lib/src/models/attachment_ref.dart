/// Reference to an email attachment whose bytes live in [BlossomCache], not
/// in the email's stored MIME.
///
/// The bytes are addressable by [sha256] in the blob cache. To load them, use
/// `NostrMailClient.getAttachmentBytes(email, ref)`.
class AttachmentRef {
  /// Decoded filename, or `null` if the part has no name.
  final String? filename;

  /// MIME media type as written in the original part (e.g. `application/pdf`).
  final String contentType;

  /// Size of the decoded bytes in bytes.
  final int size;

  /// sha256 of the decoded bytes, used as the [BlossomCache] key.
  final String sha256;

  /// MIME Content-ID without angle brackets, or `null` if the part had none.
  /// Lets a HTML body resolve inline `cid:` references to this attachment.
  final String? contentId;

  const AttachmentRef({
    required this.contentType,
    required this.size,
    required this.sha256,
    this.filename,
    this.contentId,
  });

  Map<String, dynamic> toJson() => {
    if (filename != null) 'filename': filename,
    'contentType': contentType,
    'size': size,
    'sha256': sha256,
    if (contentId != null) 'contentId': contentId,
  };

  factory AttachmentRef.fromJson(Map<String, dynamic> json) => AttachmentRef(
    filename: json['filename'] as String?,
    contentType: json['contentType'] as String,
    size: json['size'] as int,
    sha256: json['sha256'] as String,
    contentId: json['contentId'] as String?,
  );
}
