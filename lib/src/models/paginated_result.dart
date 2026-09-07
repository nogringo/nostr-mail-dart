/// One page of a larger result, with what it takes to ask for the next.
class PaginatedResult<T> {
  final List<T> items;

  /// How many rows match the query, beyond this page.
  final int total;

  /// Where this page starts in that count.
  final int offset;

  const PaginatedResult({
    required this.items,
    required this.total,
    this.offset = 0,
  });

  bool get hasMore => items.isNotEmpty && offset + items.length < total;
}
