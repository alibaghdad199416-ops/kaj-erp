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

    test('setState replaces the complete canonical query atomically', () {
      final controller = UnifiedQueryController();
      addTearDown(controller.dispose);

      const next = UnifiedQueryState(
        search: 'customer',
        filters: [
          UnifiedFilterToken(
            key: 'status',
            label: 'Status',
            value: 'open',
            valueLabel: 'Open',
          ),
        ],
        sorts: [UnifiedSortRule(field: 'date', label: 'Date')],
      );

      controller.setState(next);

      expect(controller.state, next);
    });

    test('UnifiedQueryState copyWith canonicalizes duplicate keys and fields', () {
      const initial = UnifiedQueryState(
        filters: [
          UnifiedFilterToken(
            key: 'status',
            label: 'Status',
            value: 'open',
            valueLabel: 'Open',
          ),
          UnifiedFilterToken(
            key: 'status',
            label: 'Status',
            value: 'closed',
            valueLabel: 'Closed',
          ),
        ],
        sorts: [
          UnifiedSortRule(field: 'date', label: 'Date'),
          UnifiedSortRule(field: 'date', label: 'Date', descending: true),
        ],
      );

      final next = initial.copyWith(search: '  customer  ');

      expect(next.search, 'customer');
      expect(next.filters, hasLength(1));
      expect(next.filters.single.value, 'closed');
      expect(next.sorts, hasLength(1));
      expect(next.sorts.single.descending, isTrue);
    });

    test('setFilters canonicalizes duplicate keys using the latest token', () {
      final controller = UnifiedQueryController();
      addTearDown(controller.dispose);

      controller.setFilters([
        const UnifiedFilterToken(
          key: 'currency',
          label: 'Currency',
          value: 'USD',
          valueLabel: 'USD',
        ),
        const UnifiedFilterToken(
          key: 'status',
          label: 'Status',
          value: 'open',
          valueLabel: 'Open',
        ),
        const UnifiedFilterToken(
          key: 'currency',
          label: 'Currency',
          value: 'IQD',
          valueLabel: 'IQD',
        ),
      ]);

      expect(controller.state.filters, hasLength(2));
      expect(
        controller.state.filters.firstWhere((item) => item.key == 'currency').value,
        'IQD',
      );
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

    test('setSorts canonicalizes duplicate fields using the latest rule', () {
      final controller = UnifiedQueryController();
      addTearDown(controller.dispose);

      controller.setSorts([
        const UnifiedSortRule(field: 'date', label: 'Date'),
        const UnifiedSortRule(field: 'customer', label: 'Customer'),
        const UnifiedSortRule(field: 'date', label: 'Date', descending: true),
      ]);

      expect(controller.state.sorts, hasLength(2));
      expect(
        controller.state.sorts.firstWhere((item) => item.field == 'date').descending,
        isTrue,
      );
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

    test('removing an invalid sort index leaves state unchanged', () {
      final controller = UnifiedQueryController();
      addTearDown(controller.dispose);

      controller.addSort(
        const UnifiedSortRule(field: 'date', label: 'Date'),
      );
      final before = controller.state;
      controller.removeSortAt(99);

      expect(controller.state, before);
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
