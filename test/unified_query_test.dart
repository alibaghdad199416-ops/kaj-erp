import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/filtering/unified_query.dart';

void main() {
  test('removes one filter while preserving search and other filters', () {
    final controller = UnifiedQueryController();
    final status = const UnifiedFilterToken(
      key: 'status',
      label: 'الحالة',
      value: 'active',
      valueLabel: 'نشط',
    );
    final warehouse = const UnifiedFilterToken(
      key: 'warehouse',
      label: 'المخزن',
      value: 'baghdad',
      valueLabel: 'بغداد',
    );

    controller.setSearch('أحمد');
    controller.addFilter(status);
    controller.addFilter(warehouse);
    controller.addSort(
      const UnifiedSortRule(field: 'created_at', label: 'التاريخ', descending: true),
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
      const UnifiedSortRule(field: 'created_at', label: 'التاريخ', descending: true),
      const UnifiedSortRule(field: 'name', label: 'الاسم'),
    ]);

    controller.removeSort('created_at');

    expect(controller.state.sorts, [
      const UnifiedSortRule(field: 'name', label: 'الاسم'),
    ]);
  });
}
