/// Lightweight query abstraction for the email repository.
///
/// Covers the 80 % use-case: folder or tag + read/starred state +
/// attachments + sender + free-text search, with pagination.
///
/// Every query is scoped to a single account via [recipientPubkey], which
/// prevents emails from one logged-in account leaking into another.
class EmailQuery {
  final String recipientPubkey;

  /// A reserved folder (`inbox`, `sent`, `archive`, `trash`, `spam`) or the
  /// id of a user folder.
  final String? folder;

  /// The id of a user tag: the emails it holds by label or by match, outside
  /// trash and spam.
  final String? tag;
  final bool? isRead;
  final bool? isStarred;
  final bool? hasAttachments;
  final String? senderPubkey;

  /// Matched case-insensitively.
  final String? fromAddress;
  final String? search;
  final int? limit;
  final int? offset;
  final EmailSort sort;

  const EmailQuery({
    required this.recipientPubkey,
    this.folder,
    this.tag,
    this.isRead,
    this.isStarred,
    this.hasAttachments,
    this.senderPubkey,
    this.fromAddress,
    this.search,
    this.limit,
    this.offset,
    this.sort = EmailSort.dateDesc,
  });

  /// Preset for the inbox (received, not sent).
  const EmailQuery.inbox({
    required this.recipientPubkey,
    this.isRead,
    this.isStarred,
    this.hasAttachments,
    this.senderPubkey,
    this.fromAddress,
    this.search,
    this.limit,
    this.offset,
  }) : folder = 'inbox',
       tag = null,
       sort = EmailSort.dateDesc;

  /// Preset for sent items.
  const EmailQuery.sent({
    required this.recipientPubkey,
    this.isRead,
    this.isStarred,
    this.hasAttachments,
    this.senderPubkey,
    this.fromAddress,
    this.search,
    this.limit,
    this.offset,
  }) : folder = 'sent',
       tag = null,
       sort = EmailSort.dateDesc;

  /// Preset for trash.
  const EmailQuery.trash({
    required this.recipientPubkey,
    this.isRead,
    this.isStarred,
    this.hasAttachments,
    this.senderPubkey,
    this.fromAddress,
    this.search,
    this.limit,
    this.offset,
  }) : folder = 'trash',
       tag = null,
       sort = EmailSort.dateDesc;

  /// Preset for archive.
  const EmailQuery.archive({
    required this.recipientPubkey,
    this.isRead,
    this.isStarred,
    this.hasAttachments,
    this.senderPubkey,
    this.fromAddress,
    this.search,
    this.limit,
    this.offset,
  }) : folder = 'archive',
       tag = null,
       sort = EmailSort.dateDesc;

  EmailQuery copyWith({
    String? recipientPubkey,
    String? folder,
    String? tag,
    bool? isRead,
    bool? isStarred,
    bool? hasAttachments,
    String? senderPubkey,
    String? fromAddress,
    String? search,
    int? limit,
    int? offset,
    EmailSort? sort,
  }) {
    return EmailQuery(
      recipientPubkey: recipientPubkey ?? this.recipientPubkey,
      folder: folder ?? this.folder,
      tag: tag ?? this.tag,
      isRead: isRead ?? this.isRead,
      isStarred: isStarred ?? this.isStarred,
      hasAttachments: hasAttachments ?? this.hasAttachments,
      senderPubkey: senderPubkey ?? this.senderPubkey,
      fromAddress: fromAddress ?? this.fromAddress,
      search: search ?? this.search,
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
      sort: sort ?? this.sort,
    );
  }
}

enum EmailSort { dateDesc, dateAsc }
