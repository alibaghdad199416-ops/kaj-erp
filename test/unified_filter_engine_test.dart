import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';
import 'package:quality_line_erp/core/filtering/unified_query.dart';

void main() {
  test('all populated conditions are combined with logical AND', () {
    final rows = <Map<String, Object?>>[
      {
        'name': 'Toyota Camry',
        'warehouse': 'w1',
        'status': 'available',
        'currency': 'USD',
      },
      {
        'name': 'Toyota Corolla',
        'warehouse': 'w2',
        'status': 'available',
        'currency': 'USD',
      },
      {
        'name': 'Toyota Camry',
        'warehouse': 'w1',
        'status': 'sold',
        'currency': 'USD',
      },
    ];

    final result = UnifiedFilterEngine.apply(
      rows,
      criteria: const UnifiedFilterCriteria(
        searchText: 'camry',
        warehouseIds: {'w1'},
        statuses: {'available'},
        currencies: {'USD'},
      ),
      adapter: UnifiedFilterAdapter<Map<String, Object?>>(
        searchableText: (row) => [row['name']],
        warehouseId: (row) => row['warehouse'],
        status: (row) => row['status'],
        currency: (row) => row['currency'],
      ),
    );

    expect(result, hasLength(1));
    expect(result.single['name'], 'Toyota Camry');
  });

  test('Arabic diacritics and alef forms do not break search', () {
    expect(
      UnifiedFilterEngine.normalize('إدارةُ السّيّارات'),
      UnifiedFilterEngine.normalize('ادارة السيارات'),
    );
  });

  test('compound sorting keeps each criterion independently removable', () {
    final rows = <Map<String, Object?>>[
      {'name': 'B', 'status': 'open', 'score': 10},
      {'name': 'A', 'status': 'open', 'score': 20},
      {'name': 'C', 'status': 'closed', 'score': 20},
    ];
    final adapter = UnifiedFilterAdapter<Map<String, Object?>>(
      searchableText: (row) => [row['name']],
      status: (row) => row['status'],
    );

    final sorted = UnifiedFilterEngine.apply(
      rows,
      criteria: const UnifiedFilterCriteria(),
      adapter: adapter,
      sorts: [
        UnifiedSortCriterion<Map<String, Object?>>(
          key: 'score',
          value: (row) => row['score']! as int,
          direction: UnifiedSortDirection.descending,
        ),
        UnifiedSortCriterion<Map<String, Object?>>(
          key: 'name',
          value: (row) => row['name']! as String,
        ),
      ],
    );

    expect(sorted.map((row) => row['name']).toList(), ['A', 'C', 'B']);

    final query = UnifiedQuery<Map<String, Object?>>(
      criteria: const UnifiedFilterCriteria(searchText: 'a'),
      sorts: [
        UnifiedSortCriterion<Map<String, Object?>>(
          key: 'score',
          value: (row) => row['score']! as int,
          direction: UnifiedSortDirection.descending,
        ),
        UnifiedSortCriterion<Map<String, Object?>>(
          key: 'name',
          value: (row) => row['name']! as String,
        ),
      ],
    );
    final withoutScore = query.removeSort('score');
    expect(withoutScore.criteria.searchText, 'a');
    expect(withoutScore.sorts.map((sort) => sort.key), ['name']);
    expect(query.sorts.map((sort) => sort.key), ['score', 'name']);
  });
}
