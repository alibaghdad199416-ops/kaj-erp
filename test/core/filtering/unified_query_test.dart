import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/filtering/unified_query.dart';

void main() {
  group('UnifiedQueryController', () {
    test('keeps search, filters and sorts in one immutable state', () {
      final controller = UnifiedQueryController();
      final filter = UnifiedFilterToken(
        key: 'status',
        label: 'الحالة',
        value: 'open',
        valueLabel: 'مفتوح',
      );

      controller.setSearch('  invoice-10  ');
      controller.addFilter(filter);
      controller.addSort(const UnifiedSortRule(
        field: 'created_at',
        label: 'تاريخ الإنشاء',
      ));

      expect(controller.state.search, '  invoice-10  ');
      expect(controller.state.filters, contains(filter));
      expect(controller.state.sorts.single.field, 'created_at');
      expect(controller.state.sorts.single.descending, isFalse);
    });

    test('reselecting a sort field toggles its direction', () {
      final controller = UnifiedQueryController();
      const rule = UnifiedSortRule(field: 'name', label: 'الاسم');

      controller.addSort(rule);
      expect(controller.state.sorts.single.descending, isFalse);

      controller.addSort(rule);
      expect(controller.state.sorts.single.descending, isTrue);
    });

    test('adding a filter replaces the previous value for the same key', () {
      final controller = UnifiedQueryController();
      final first = UnifiedFilterToken(
        key: 'warehouse',
        label: 'المخزن',
        value: '1',
        valueLabel: 'المخزن الرئيسي',
      );
      final second = UnifiedFilterToken(
        key: 'warehouse',
        label: 'المخزن',
        value: '2',
        valueLabel: 'المخزن الفرعي',
      );

      controller.addFilter(first);
      controller.addFilter(second);

      expect(controller.state.filters, hasLength(1));
      expect(controller.state.filters.single.value, '2');
    });

    test('clear returns the canonical empty state', () {
      final controller = UnifiedQueryController();
      controller.setSearch('abc');
      controller.clear();

      expect(controller.state.isEmpty, isTrue);
      expect(controller.state.search, isEmpty);
      expect(controller.state.filters, isEmpty);
      expect(controller.state.sorts, isEmpty);
    });
  });
}
