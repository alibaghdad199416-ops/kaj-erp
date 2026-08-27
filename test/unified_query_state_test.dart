import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/filtering/unified_query.dart';

void main() {
  test('removing one filter preserves search, other filters and sorts', () {
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
      value: 'w1',
      valueLabel: 'مخزن بغداد',
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
  });

  test('same filter key replaces only that filter', () {
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

  test('sort replacement keeps priority and independent removal works', () {
    final controller = UnifiedQueryController();
    controller.setSorts(const [
      UnifiedSortRule(field: 'date', label: 'التاريخ', descending: true),
      UnifiedSortRule(field: 'name', label: 'الاسم'),
    ]);
    controller.addSort(
      const UnifiedSortRule(field: 'date', label: 'التاريخ', descending: false),
    );

    expect(controller.state.sorts.map((rule) => rule.field), ['date', 'name']);
    expect(controller.state.sorts.first.descending, isFalse);

    controller.removeSort('date');
    expect(controller.state.sorts.map((rule) => rule.field), ['name']);
  });
}
