/// Lightweight query abstraction for the email repository.
///
/// Covers the 80 % use-case: folder + read/starred state + attachments +
/// free-text search, with native Sembast pagination.
class EmailQuery {
  final String? folder;
  final bool? isRead;
  final bool? isStarred;
  final bool? hasAttachments;
  final String? search;
  final int? limit;
  final int? offset;
  final EmailSort sort;

  const EmailQuery({
    this.folder,
    this.isRead,
    this.isStarred,
    this.hasAttachments,
    this.search,
    this.limit,
    this.offset,
    this.sort = EmailSort.dateDesc,
  });

  /// Preset for the inbox (received, not sent).
  const EmailQuery.inbox({
    this.isRead,
    this.isStarred,
    this.hasAttachments,
    this.search,
    this.limit,
    this.offset,
  }) : folder = 'inbox',
       sort = EmailSort.dateDesc;

  /// Preset for sent items.
  const EmailQuery.sent({
    this.isRead,
    this.isStarred,
    this.hasAttachments,
    this.search,
    this.limit,
    this.offset,
  }) : folder = 'sent',
       sort = EmailSort.dateDesc;

  /// Preset for trash.
  const EmailQuery.trash({
    this.isRead,
    this.isStarred,
    this.hasAttachments,
    this.search,
    this.limit,
    this.offset,
  }) : folder = 'trash',
       sort = EmailSort.dateDesc;

  /// Preset for archive.
  const EmailQuery.archive({
    this.isRead,
    this.isStarred,
    this.hasAttachments,
    this.search,
    this.limit,
    this.offset,
  }) : folder = 'archive',
       sort = EmailSort.dateDesc;

  EmailQuery copyWith({
    String? folder,
    bool? isRead,
    bool? isStarred,
    bool? hasAttachments,
    String? search,
    int? limit,
    int? offset,
    EmailSort? sort,
  }) {
    return EmailQuery(
      folder: folder ?? this.folder,
      isRead: isRead ?? this.isRead,
      isStarred: isStarred ?? this.isStarred,
      hasAttachments: hasAttachments ?? this.hasAttachments,
      search: search ?? this.search,
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
      sort: sort ?? this.sort,
    );
  }
}

enum EmailSort { dateDesc, dateAsc }

/// Generic paginated result.
class PaginatedResult<T> {
  final List<T> items;
  final int total;
  final int offset;

  const PaginatedResult({
    required this.items,
    required this.total,
    this.offset = 0,
  });

  bool get hasMore => items.isNotEmpty && offset + items.length < total;
}
