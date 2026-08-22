import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'allocation UI uses persisted ordered fulfilled and remaining values',
    () {
      final source = File(
        'lib/core/widgets/warehouse_allocation_dialog.dart',
      ).readAsStringSync();

      expect(source, contains("item['orderedQuantity']"));
      expect(source, contains("item['fulfilledQuantity']"));
      expect(source, contains('batchQuantity > entry.value'));
      expect(source, isNot(contains('sums[entry.key] != entry.value')));
    },
  );

  test(
    'R59 enforces cumulative physical fulfilment and aggregates invoicing',
    () {
      final migrations = Directory('supabase/migrations')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.contains('_r59_'))
          .map((file) => file.readAsStringSync())
          .join('\n');

      expect(migrations, contains('commercial_over_fulfillment'));
      expect(migrations, contains('remainingQuantity'));
      expect(migrations, contains("document_type='receipt'"));
      expect(migrations, contains("document_type='delivery'"));
      expect(migrations, contains('logisticsDocumentIds'));
      expect(migrations, contains('delivery_id=any(v_delivery_ids)'));
    },
  );

  test('R60 preserves canonical individual-car delivery states', () {
    final migration = File(
      'supabase/migrations/20260813170051_r60_sales_car_delivery_status_compatibility.sql',
    ).readAsStringSync();

    expect(
      migration,
      contains('erp_validate_commercial_warehouse_allocations'),
    );
    expect(migration, contains('قيد البيع'));
    expect(migration, contains('متاحة'));
    expect(migration, contains('r60_expected_r59_car_status_guard_not_found'));
  });

  test(
    'commercial document details suppress identities and render allocations',
    () {
      final source = File(
        'lib/features/sales/workflow/pages/order_details_dialog.dart',
      ).readAsStringSync();

      expect(source, contains("'valuedByInvoiceId'"));
      expect(source, contains("key == 'allocations'"));
      expect(source, contains('DataTable('));
      expect(source, contains("movement?['warehouseName']"));
      expect(source, contains("item?['itemCode']"));
    },
  );
}
