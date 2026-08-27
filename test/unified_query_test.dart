import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';
import 'package:quality_line_erp/core/filtering/unified_query.dart';
import 'package:quality_line_erp/core/filtering/unified_query_executor.dart';

class _Row {
  const _Row({required this.name, required this.status});

  final String name;
  final String status;
}

void main() {
  test('removes one filter while preserving search and other filters', () {
    final controller = UnifiedQueryController();
    const status = UnifiedFilterToken(
      key: 'status',
      label: 'الحالة',
      value: 'active',
      valueLabel: 'نشط',
    );
    const warehouse = UnifiedFilterToken(
      key: 'warehouse',
      label: 'المخزن',
      value: 'baghdad',
      valueLabel: 'بغداد',
    );

    controller.setSearch('أحمد');
    controller.addFilter(status);
    controller.addFilter(warehouse);
    controller.addSort(
      const UnifiedSortRule(
        field: 'created_at',
        label: 'التاريخ',
        descending: true,
      ),
    );

    controller.removeFilter(status);

    expect(controller.state.search, 'أحمد');
    expect(controller.state.filters, [warehouse]);
    expect(controller.state.sorts.single.field, 'created_at');
    expect(controller.state.sorts.single.descending, isTrue);
  });

  test('adding a filter with the same key replaces only that filter', () {
    final controller = UnifiedQueryController();
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
        key: 'status',
        label: 'الحالة',
        value: 'inactive',
        valueLabel: 'غير نشط',
      ),
    );

    expect(controller.state.filters, hasLength(1));
    expect(controller.state.filters.single.value, 'inactive');
  });

  test('supports multiple sort rules and independent removal', () {
    final controller = UnifiedQueryController();
    controller.setSorts([
      const UnifiedSortRule(
        field: 'created_at',
        label: 'التاريخ',
        descending: true,
      ),
      const UnifiedSortRule(field: 'name', label: 'الاسم'),
    ]);

    controller.removeSort('created_at');

    expect(controller.state.sorts, [
      const UnifiedSortRule(field: 'name', label: 'الاسم'),
    ]);
  });

  test('replacing a sort rule preserves its existing priority', () {
    final controller = UnifiedQueryController();
    controller.setSorts([
      const UnifiedSortRule(field: 'status', label: 'الحالة'),
      const UnifiedSortRule(field: 'name', label: 'الاسم'),
    ]);

    controller.addSort(
      const UnifiedSortRule(
        field: 'status',
        label: 'الحالة',
        descending: true,
      ),
    );

    expect(controller.state.sorts.map((rule) => rule.field), [
      'status',
      'name',
    ]);
    expect(controller.state.sorts.first.descending, isTrue);
  });

  test('unified executor applies filters before ordered multi-sort', () {
    const rows = <_Row>[
      _Row(name: 'Zaid', status: 'active'),
      _Row(name: 'Ali', status: 'active'),
      _Row(name: 'Omar', status: 'inactive'),
    ];
    const executor = UnifiedQueryExecutor<_Row>(
      criteriaBuilder: (state) => UnifiedFilterCriteria(
        searchText: state.search,
        statuses: state.filters
            .where((filter) => filter.key == 'status')
            .map((filter) => filter.value.toString())
            .toSet(),
      ),
      filterAdapter: UnifiedFilterAdapter<_Row>(
        searchableText: (row) => [row.name, row.status],
        status: (row) => row.status,
      ),
      sort: (left, right, field) {
        if (field == 'name') return left.name.compareTo(right.name);
        return left.status.compareTo(right.status);
      },
    );

    final result = executor.execute(
      rows,
      const UnifiedQueryState(
        filters: [
          UnifiedFilterToken(
            key: 'status',
            label: 'الحالة',
            value: 'active',
            valueLabel: 'نشط',
          ),
        ],
        sorts: [
          UnifiedSortRule(field: 'status', label: 'الحالة'),
          UnifiedSortRule(field: 'name', label: 'الاسم'),
        ],
      ),
    );

    expect(result.map((row) => row.name), ['Ali', 'Zaid']);
  });
}
