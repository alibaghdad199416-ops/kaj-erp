import 'package:flutter_test/flutter_test.dart';
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

  test(
    'controller replaces one filter without disturbing search or other filters',
    () {
      final controller = UnifiedQueryController();
      addTearDown(controller.dispose);

      controller.setSearch('أحمد');
      controller.addFilter(
        const UnifiedFilterToken(
          key: 'status',
          label: 'الحالة',
          value: 'active',
          valueLabel: 'نشط',
        ),
      );
      controller.addFilter(
        const UnifiedFilterToken(
          key: 'warehouse',
          label: 'المخزن',
          value: 'w1',
          valueLabel: 'المخزن الرئيسي',
        ),
      );
      controller.addFilter(
        const UnifiedFilterToken(
          key: 'status',
          label: 'الحالة',
          value: 'inactive',
          valueLabel: 'غير نشط',
        ),
      );

      expect(controller.state.search, 'أحمد');
      expect(controller.state.filters, hasLength(2));
      expect(
        controller.state.filters.any((f) => f.value == 'inactive'),
        isTrue,
      );
      expect(controller.state.filters.any((f) => f.value == 'active'), isFalse);
      expect(controller.state.filters.any((f) => f.value == 'w1'), isTrue);
    },
  );

  test('controller supports compound sorts and toggles direction safely', () {
    final controller = UnifiedQueryController();
    addTearDown(controller.dispose);

    controller.setSearch('Toyota');
    controller.addSort(
      const UnifiedSortRule(field: 'date', label: 'التاريخ', descending: true),
    );
    controller.addSort(const UnifiedSortRule(field: 'name', label: 'الاسم'));

    expect(controller.state.search, 'Toyota');
    expect(controller.state.sorts.map((s) => s.field), ['date', 'name']);
    expect(controller.state.sorts.first.descending, isTrue);

    controller.addSort(
      const UnifiedSortRule(field: 'date', label: 'التاريخ', descending: true),
    );
    expect(controller.state.sorts.map((s) => s.field), ['date', 'name']);
    expect(controller.state.sorts.first.descending, isFalse);

    controller.removeSort('date');
    expect(controller.state.search, 'Toyota');
    expect(controller.state.sorts.map((s) => s.field), ['name']);
  });

  test(
    'controller removes one filter while retaining the remaining query state',
    () {
      final controller = UnifiedQueryController();
      addTearDown(controller.dispose);

      const status = UnifiedFilterToken(
        key: 'status',
        label: 'الحالة',
        value: 'active',
        valueLabel: 'نشط',
      );
      const warehouse = UnifiedFilterToken(
        key: 'warehouse',
        label: 'المخزن',
        value: 'w1',
        valueLabel: 'المخزن الرئيسي',
      );

      controller.setSearch('أحمد');
      controller.setFilters([status, warehouse]);
      controller.addSort(
        const UnifiedSortRule(
          field: 'date',
          label: 'التاريخ',
          descending: true,
        ),
      );
      controller.removeFilter(status);

      expect(controller.state.search, 'أحمد');
      expect(controller.state.filters, [warehouse]);
      expect(controller.state.sorts, hasLength(1));
    },
  );
}
