import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/filtering/unified_query.dart';

void main() {
  group('UnifiedQueryController', () {
    test('normalizes search input and avoids redundant notifications', () {
      final controller = UnifiedQueryController();
      addTearDown(controller.dispose);

      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.setSearch('  invoice  ');
      controller.setSearch('invoice');

      expect(controller.state.search, 'invoice');
      expect(notifications, 1);
    });

    test('replacing a filter key removes the previous token', () {
      final controller = UnifiedQueryController();
      addTearDown(controller.dispose);

      controller.addFilter(
        const UnifiedFilterToken(
          key: 'currency',
          label: 'Currency',
          value: 'USD',
          valueLabel: 'USD',
        ),
      );
      controller.addFilter(
        const UnifiedFilterToken(
          key: 'currency',
          label: 'Currency',
          value: 'IQD',
          valueLabel: 'IQD',
        ),
      );

      expect(controller.state.filters, hasLength(1));
      expect(controller.state.filters.single.value, 'IQD');
    });

    test('adding the same sort field toggles direction', () {
      final controller = UnifiedQueryController();
      addTearDown(controller.dispose);

      const rule = UnifiedSortRule(field: 'date', label: 'Date');
      controller.addSort(rule);
      expect(controller.state.sorts.single.descending, isFalse);

      controller.addSort(rule);
      expect(controller.state.sorts.single.descending, isTrue);
    });

    test('clear restores an empty canonical query state', () {
      final controller = UnifiedQueryController();
      addTearDown(controller.dispose);

      controller.setSearch('customer');
      controller.addFilter(
        const UnifiedFilterToken(
          key: 'status',
          label: 'Status',
          value: 'open',
          valueLabel: 'Open',
        ),
      );
      controller.addSort(
        const UnifiedSortRule(field: 'date', label: 'Date', descending: true),
      );

      controller.clear();

      expect(controller.state.isEmpty, isTrue);
      expect(controller.state.search, isEmpty);
      expect(controller.state.filters, isEmpty);
      expect(controller.state.sorts, isEmpty);
    });
  });
}
