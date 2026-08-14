import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('R67 separates cancellation, order purge, and payment deletion', () {
    final sql = File(
      'supabase/migrations/20260814143000_r67_cancelled_order_atomic_purge.sql',
    ).readAsStringSync();

    expect(sql, contains('erp_r67_cancel_maintenance_order'));
    expect(sql, contains("'maintenance.cancel'"));
    expect(sql, contains('erp_r67_delete_commercial_order'));
    expect(sql, contains('erp_r67_delete_maintenance_order'));
    expect(sql, contains("'maintenance.delete'"));
    expect(sql, contains("v_status<>'cancelled'"));
    expect(sql, contains("v_stage<>'cancelled'"));
    expect(sql, contains('cancel_required_before_delete'));
    expect(sql, contains('erp_delete_cloud_sales_order_v3'));
    expect(sql, contains('erp_delete_cloud_purchase_order_v3'));
    expect(sql, contains('erp_delete_cloud_maintenance_order_v3'));
    expect(sql, isNot(contains('delete from public.erp_cash_transactions')));
  });

  test('all three modules expose Delete for draft or cancelled only', () {
    final sales = File(
      'lib/features/sales/workflow/pages/sales_workflow_page.dart',
    ).readAsStringSync();
    final purchases = File(
      'lib/features/purchases/pages/purchase_workflow_page.dart',
    ).readAsStringSync();
    final maintenance = File(
      'lib/features/maintenance/pages/maintenance_page.dart',
    ).readAsStringSync();
    final details = File(
      'lib/features/sales/workflow/pages/order_details_dialog.dart',
    ).readAsStringSync();

    expect(sales, contains("status == 'draft' || status == 'cancelled'"));
    expect(purchases, contains("status == 'draft' || status == 'cancelled'"));
    expect(maintenance, contains("'order_draft',"));
    expect(maintenance, contains("'draft',"));
    expect(maintenance, contains("'cancelled',"));
    expect(details, contains("'draft',"));
    expect(details, contains("'cancelled',"));
    expect(sales, contains("'sales.cancel'"));
    expect(sales, contains("'sales.delete'"));
    expect(purchases, contains("'purchases.cancel'"));
    expect(purchases, contains("'purchases.delete'"));
  });

  test('Flutter repositories use the atomic R67 commands', () {
    final sales = File(
      'lib/features/sales/workflow/repositories/sales_workflow_repository.dart',
    ).readAsStringSync();
    final purchases = File(
      'lib/features/purchases/repositories/purchase_workflow_repository.dart',
    ).readAsStringSync();
    final maintenance = File(
      'lib/features/maintenance/data/maintenance_repository.dart',
    ).readAsStringSync();

    expect(sales, contains("'erp_r67_delete_commercial_order'"));
    expect(purchases, contains("'erp_r67_delete_commercial_order'"));
    expect(maintenance, contains("'erp_r67_cancel_maintenance_order'"));
    expect(maintenance, contains("'erp_r67_delete_maintenance_order'"));
  });
}
