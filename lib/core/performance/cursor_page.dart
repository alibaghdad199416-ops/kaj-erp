class CursorPage<T> {
  const CursorPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
    this.totalCount,
  });

  final List<T> items;
  final bool hasMore;
  final String? nextCursor;
  final int? totalCount;
}

class PageRequest {
  const PageRequest({this.cursor, this.limit = 50})
    : assert(limit > 0 && limit <= 500);

  final String? cursor;
  final int limit;
}
