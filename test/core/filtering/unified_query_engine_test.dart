import 'package:flutter_test/flutter_test.dart';

import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';
import 'package:quality_line_erp/core/filtering/unified_query.dart';

void main() {
  group('UnifiedFilterEngine', () {
    final rows = <Map<String, Object>>[
      {
        'name': 'أحمد بغداد',
        'status': 'active',
        'currency': 'IQD',
        'date': DateTime(2026, 8, 20),
        'total': 100.0,
      },
      {
        'name': 'محمد بغداد',
        'status': 'inactive',
        'currency': 'USD',
        'date': DateTime(2026, 8, 21),
        'total': 300.0,
      },
      {
        'name': 'أحمد علي',
        'status': 'active',
        'currency': 'USD',
        'date': DateTime(2026, 8, 22),
        'total': 200.0,
      },
    ];

    UnifiedFilterAdapter<Map<String, Object>> adapter() =>
        UnifiedFilterAdapter<Map<String, Object>>(
          searchableText: (row) => [row['name']],
          status: (row) => row['status'],
          currency: (row) => row['currency'],
          date: (row) => row['date'] as DateTime,
        );

    test('combines search and filters with AND semantics', () {
      final result = UnifiedFilterEngine.apply(
        rows,
        criteria: const UnifiedFilterCriteria(
          searchText: 'احمد',
          statuses: {'active'},
          currencies: {'USD'},
        ),
        adapter: adapter(),
      );

      expect(result, hasLength(1));
      expect(result.single['name'], 'أحمد علي');
    });

    test('normalizes common Arabic variants during search', () {
      final result = UnifiedFilterEngine.apply(
        rows,
        criteria: const UnifiedFilterCriteria(searchText: 'إحمد'),
        adapter: adapter(),
      );

      expect(result, hasLength(2));
    });

    test('supports compound sorting without mutating the source list', () {
      final original = List<Map<String, Object>>.from(rows);
      final result = UnifiedFilterEngine.apply(
        rows,
        criteria: const UnifiedFilterCriteria(),
        adapter: adapter(),
        sorts: [
          UnifiedSortCriterion<Map<String, Object>>(
            key: 'status',
            value: (row) => row['status'].toString(),
          ),
          UnifiedSortCriterion<Map<String, Object>>(
            key: 'total',
            direction: UnifiedSortDirection.descending,
            value: (row) => row['total'] as double,
          ),
        ],
      );

      expect(result.map((row) => row['total']).toList(), [200.0, 100.0, 300.0]);
      expect(rows, original);
    });
  });

  group('UnifiedQueryController', () {
    test('removes one filter while retaining search and other filters', () {
      final controller = UnifiedQueryController();
      addTearDown(controller.dispose);

      controller.setSearch('أحمد');
      final status = const UnifiedFilterToken(
        key: 'status',
        label: 'الحالة',
        value: 'active',
        valueLabel: 'نشط',
      );
      final currency = const UnifiedFilterToken(
        key: 'currency',
        label: 'العملة',
        value: 'IQD',
        valueLabel: 'IQD',
      );
      controller.addFilter(status);
      controller.addFilter(currency);

      controller.removeFilter(status);

      expect(controller.state.search, 'أحمد');
      expect(controller.state.filters, [currency]);
    });

    test('supports multiple sort rules and removing only one', () {
      final controller = UnifiedQueryController();
      addTearDown(controller.dispose);

      controller.addSort(const UnifiedSortRule(field: 'date', label: 'التاريخ'));
      controller.addSort(const UnifiedSortRule(field: 'total', label: 'الإجمالي'));
      controller.removeSort('date');

      expect(controller.state.sorts, [
        const UnifiedSortRule(field: 'total', label: 'الإجمالي'),
      ]);
    });
  });
}
