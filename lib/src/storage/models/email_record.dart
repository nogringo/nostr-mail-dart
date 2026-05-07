import '../../models/email.dart';

/// Internal denormalized record for fast local queries.
///
/// This is the shape stored in Sembast. It contains every field needed for
/// filtering, sorting and searching without joins.
class EmailRecord {
  final String id;
  final String senderPubkey;
  final String recipientPubkey;
  final String rawContent;
  final bool isPublic;

  /// Nostr event createdAt (epoch seconds).
  final int createdAt;

  /// MIME date or fallback to createdAt (epoch seconds).
  final int date;

  // ── Derived fields for querying ─────────────────────────────────────────

  /// Sender email address (extracted from MIME).
  final String from;

  /// Email subject (extracted from MIME).
  final String subject;

  /// Plain-text body (extracted from MIME, HTML stripped if needed).
  final String bodyPlain;

  /// Lower-case concatenation of from + subject + body for text search.
  final String searchText;

  /// Number of attachments extracted from MIME parts.
  final int attachmentCount;

  // ── Denormalized labels (source of truth for fast queries) ──────────────

  /// Current folder. Mutually exclusive: inbox, sent, trash, archive, spam.
  final String folder;

  final bool isRead;
  final bool isStarred;

  /// Non-folder labels (custom tags).
  final List<String> labels;

  final bool isBridged;

  const EmailRecord({
    required this.id,
    required this.senderPubkey,
    required this.recipientPubkey,
    required this.rawContent,
    required this.isPublic,
    required this.createdAt,
    required this.date,
    required this.from,
    required this.subject,
    required this.bodyPlain,
    required this.searchText,
    required this.attachmentCount,
    required this.folder,
    required this.isRead,
    required this.isStarred,
    required this.labels,
    required this.isBridged,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'senderPubkey': senderPubkey,
    'recipientPubkey': recipientPubkey,
    'rawContent': rawContent,
    'isPublic': isPublic,
    'createdAt': createdAt,
    'date': date,
    'from': from,
    'subject': subject,
    'bodyPlain': bodyPlain,
    'searchText': searchText,
    'attachmentCount': attachmentCount,
    'folder': folder,
    'isRead': isRead,
    'isStarred': isStarred,
    'labels': labels,
    'isBridged': isBridged,
  };

  factory EmailRecord.fromJson(Map<String, dynamic> json) => EmailRecord(
    id: json['id'] as String,
    senderPubkey: json['senderPubkey'] as String,
    recipientPubkey: json['recipientPubkey'] as String,
    rawContent: json['rawContent'] as String,
    isPublic: json['isPublic'] as bool? ?? false,
    createdAt: json['createdAt'] as int,
    date: json['date'] as int,
    from: json['from'] as String,
    subject: json['subject'] as String,
    bodyPlain: json['bodyPlain'] as String,
    searchText: json['searchText'] as String,
    attachmentCount: json['attachmentCount'] as int? ?? 0,
    folder: json['folder'] as String,
    isRead: json['isRead'] as bool? ?? false,
    isStarred: json['isStarred'] as bool? ?? false,
    labels: (json['labels'] as List<dynamic>?)?.cast<String>() ?? const [],
    isBridged: json['isBridged'] as bool? ?? false,
  );

  /// Build an [EmailRecord] from a public [Email] model.
  ///
  /// [folder] must be provided by the caller (inbox / sent).
  factory EmailRecord.fromEmail(
    Email email, {
    required String folder,
    required String searchText,
    required int attachmentCount,
    List<String> labels = const [],
    bool isRead = false,
    bool isStarred = false,
  }) {
    return EmailRecord(
      id: email.id,
      senderPubkey: email.senderPubkey,
      recipientPubkey: email.recipientPubkey,
      rawContent: email.rawContent,
      isPublic: email.isPublic,
      createdAt: email.createdAt.millisecondsSinceEpoch ~/ 1000,
      date: email.date.millisecondsSinceEpoch ~/ 1000,
      from: email.sender?.email ?? email.mime.fromEmail ?? '',
      subject: email.subject ?? '',
      bodyPlain: email.textBody ?? email.body,
      searchText: searchText,
      attachmentCount: attachmentCount,
      folder: folder,
      isRead: isRead,
      isStarred: isStarred,
      labels: labels,
      isBridged: email.isBridged,
    );
  }

  Email toEmail() => Email(
    id: id,
    senderPubkey: senderPubkey,
    recipientPubkey: recipientPubkey,
    rawContent: rawContent,
    createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt * 1000),
    isPublic: isPublic,
  );

  EmailRecord copyWith({
    String? folder,
    bool? isRead,
    bool? isStarred,
    List<String>? labels,
    int? attachmentCount,
  }) {
    return EmailRecord(
      id: id,
      senderPubkey: senderPubkey,
      recipientPubkey: recipientPubkey,
      rawContent: rawContent,
      isPublic: isPublic,
      createdAt: createdAt,
      date: date,
      from: from,
      subject: subject,
      bodyPlain: bodyPlain,
      searchText: searchText,
      attachmentCount: attachmentCount ?? this.attachmentCount,
      folder: folder ?? this.folder,
      isRead: isRead ?? this.isRead,
      isStarred: isStarred ?? this.isStarred,
      labels: labels ?? this.labels,
      isBridged: isBridged,
    );
  }
}
