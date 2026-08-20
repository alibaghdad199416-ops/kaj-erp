import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'R61 invoices from approved logistics without rechecking current car warehouse',
    () {
      final sql = File(
        'supabase/migrations/20260814024507_r61_unified_commercial_lifecycle_cancellation.sql',
      ).readAsStringSync();

      expect(sql, contains('erp_r61_validate_approved_logistics'));
      expect(
        sql,
        contains("perform public.erp_r61_validate_approved_logistics("),
      );
      expect(
        sql,
        isNot(
          contains(
            "perform public.erp_validate_commercial_warehouse_allocations(p_company_id,p_order_id,p_module,v_result->'allocations',false)",
          ),
        ),
      );
      expect(sql, contains('approved_logistics_item_mismatch'));
      expect(sql, contains('approved_logistics_car_identity_mismatch'));
    },
  );

  test('R61 cancellation is atomic, idempotent, and preserves the order', () {
    final sql = File(
      'supabase/migrations/20260814024507_r61_unified_commercial_lifecycle_cancellation.sql',
    ).readAsStringSync();

    expect(sql, contains('erp_r61_cancel_commercial_order'));
    expect(sql, contains("if v_status='cancelled'"));
    expect(sql, contains("set status='cancelled',is_deleted=false"));
    expect(sql, contains("'paymentsPreserved',true"));
    expect(sql, contains('erp_delete_cloud_sales_order_v3'));
    expect(sql, contains('erp_delete_cloud_purchase_order_v3'));
  });

  test('R62 separates cancel from delete and supplies one details snapshot', () {
    final sql = File(
      'supabase/migrations/20260814035608_r62_cancel_delete_permission_separation.sql',
    ).readAsStringSync();
    final salesRepository = File(
      'lib/features/sales/workflow/repositories/sales_workflow_repository.dart',
    ).readAsStringSync();
    final purchaseRepository = File(
      'lib/features/purchases/repositories/purchase_workflow_repository.dart',
    ).readAsStringSync();
    final detailsRepository = File(
      'lib/features/sales/workflow/repositories/commercial_order_details_repository.dart',
    ).readAsStringSync();

    expect(sql, contains("v_permission:=p_module||'.cancel'"));
    expect(sql, isNot(contains("p_module||'.delete'")));
    expect(sql, contains('erp_r62_get_commercial_order_snapshot'));
    expect(sql, contains("'{reconciliation}'"));
    expect(salesRepository, contains("'erp_r62_cancel_commercial_order'"));
    expect(purchaseRepository, contains("'erp_r62_cancel_commercial_order'"));
    expect(
      detailsRepository,
      contains("'erp_r89_get_commercial_order_snapshot'"),
    );
    expect(detailsRepository, isNot(contains('Future.wait')));
  });
}
