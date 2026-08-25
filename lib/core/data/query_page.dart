class QueryPage {
  const QueryPage({this.limit = 50, this.offset = 0})
    : assert(limit > 0 && limit <= 500),
      assert(offset >= 0);

  final int limit;
  final int offset;

  QueryPage next() => QueryPage(limit: limit, offset: offset + limit);
}
