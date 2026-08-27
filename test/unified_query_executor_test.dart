import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';
import 'package:quality_line_erp/core/filtering/unified_query.dart';
import 'package:quality_line_erp/core/filtering/unified_query_executor.dart';

class _Row {
  const _Row(this.name, this.status, this.createdAt);
  final String name;
  final String status;
  final DateTime createdAt;
}

void main() {
  test('combines search, filters and multiple sort rules', () {
    const rows = <_Row>[
      _Row('أحمد علي', 'active', DateTime(2026, 8, 1)),
      _Row('أحمد حسن', 'active', DateTime(2026, 8, 3)),
      _Row('محمد علي', 'active', DateTime(2026, 8, 4)),
      _Row('أحمد حسن', 'inactive', DateTime(2026, 8, 5)),
    ];

    const adapter = UnifiedFilterAdapter<_Row>(
      searchableText: (row) => [row.name],
      status: (row) => row.status,
    );
    const executor = UnifiedQueryExecutor<_Row>(
      criteriaBuilder: (state) => UnifiedFilterCriteria(
        searchText: state.search,
        statuses: {'active'},
      ),
      filterAdapter: adapter,
      sort: (left, right, field) {
        if (field == 'name') return left.name.compareTo(right.name);
        return left.createdAt.compareTo(right.createdAt);
      },
    );

    final state = UnifiedQueryState(
      search: 'أحمد',
      sorts: const [
        UnifiedSortRule(field: 'name', label: 'الاسم'),
        UnifiedSortRule(field: 'created_at', label: 'التاريخ', descending: true),
      ],
    );

    final result = executor.execute(rows, state);

    expect(result, hasLength(2));
    expect(result.map((row) => row.name), ['أحمد حسن', 'أحمد علي']);
  });
}
