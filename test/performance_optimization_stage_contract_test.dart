import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/performance/cursor_page.dart';
import 'package:quality_line_erp/core/performance/ttl_memory_cache.dart';

void main() {
  test('TTL cache stores and invalidates values', () {
    final cache = TtlMemoryCache(maximumEntries: 2);
    cache.put('company:1:sales', 10);
    expect(cache.get<int>('company:1:sales'), 10);
    cache.invalidatePrefix('company:1:');
    expect(cache.get<int>('company:1:sales'), isNull);
  });

  test('page request enforces safe page size', () {
    const request = PageRequest(limit: 100);
    expect(request.limit, 100);
  });

  test('cursor page exposes continuation state', () {
    const page = CursorPage<int>(items: [1, 2], hasMore: true, nextCursor: '2');
    expect(page.hasMore, isTrue);
    expect(page.nextCursor, '2');
  });
}
