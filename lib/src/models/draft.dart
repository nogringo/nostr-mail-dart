/// An email being written, saved as a NIP-37 draft wrap.
///
/// A listing entry: [NostrMailClient.getDraftMime] restores the complete
/// email, body and attachments included.
class Draft {
  /// The `d` tag of the draft wrap. Pass it back to save over this draft.
  final String draftId;

  /// When this version was saved.
  final DateTime updatedAt;

  final String? from;
  final List<String> to;
  final List<String> cc;
  final List<String> bcc;
  final String subject;

  /// Short one-line preview of the body.
  final String bodyPreview;

  final List<String> attachmentNames;

  Draft({
    required this.draftId,
    required this.updatedAt,
    required this.from,
    required this.to,
    required this.cc,
    required this.bcc,
    required this.subject,
    required this.bodyPreview,
    required this.attachmentNames,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Draft && draftId == other.draftId;

  @override
  int get hashCode => draftId.hashCode;
}
