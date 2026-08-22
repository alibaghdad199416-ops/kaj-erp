import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('R66 fixes post-delivery car validation without weakening delivery', () {
    final sql = File(
      'supabase/migrations/20260814124943_r66_authenticated_runtime_defect_repair.sql',
    ).readAsStringSync();
    final deliverySource = File(
      'supabase/migrations/20260813144626_r59_partial_commercial_fulfillment_integrity.sql',
    ).readAsStringSync();

    expect(sql, contains("if p_module='sales' and p_check_sales_stock then"));
    expect(sql, contains("raise exception 'car_warehouse_mismatch'"));
    expect(
      deliverySource,
      contains(
        "erp_validate_commercial_warehouse_allocations(p_company_id,p_order_id,'sales',p_allocations,true)",
      ),
    );
  });

  test('Delete and Cancel remain separate commands and permissions', () {
    final details = File(
      'lib/features/sales/workflow/pages/order_details_dialog.dart',
    ).readAsStringSync();
    final sales = File(
      'lib/features/sales/workflow/pages/sales_workflow_page.dart',
    ).readAsStringSync();
    final purchases = File(
      'lib/features/purchases/pages/purchase_workflow_page.dart',
    ).readAsStringSync();
    final maintenance = File(
      'lib/features/maintenance/pages/maintenance_page.dart',
    ).readAsStringSync();
    final salesRepository = File(
      'lib/features/sales/workflow/repositories/sales_workflow_repository.dart',
    ).readAsStringSync();
    final purchaseRepository = File(
      'lib/features/purchases/repositories/purchase_workflow_repository.dart',
    ).readAsStringSync();
    final maintenanceGuard = File(
      'supabase/migrations/20260814132822_r66_3_maintenance_material_issue_guard_lint_fix.sql',
    ).readAsStringSync();

    expect(details, contains('Delete draft'));
    expect(details, contains('Cancel order and reverse links'));
    expect(sales, contains("'sales.delete'"));
    expect(sales, contains("'sales.cancel'"));
    expect(purchases, contains("'purchases.delete'"));
    expect(purchases, contains("'purchases.cancel'"));
    expect(maintenance, contains("'maintenance.delete'"));
    expect(maintenance, contains("'maintenance.cancel'"));
    expect(salesRepository, contains("'erp_r67_delete_commercial_order'"));
    expect(purchaseRepository, contains("'erp_r67_delete_commercial_order'"));
    expect(maintenanceGuard, contains('erp_r66_delete_maintenance_draft'));
    expect(maintenanceGuard, contains('erp_maintenance_material_issues'));
    expect(maintenanceGuard, contains('erp_maintenance_payments'));
    expect(maintenanceGuard, isNot(contains('erp_maintenance_parts')));
  });

  test('notification delete is recipient-local and updates UI immediately', () {
    final sql = File(
      'supabase/migrations/20260814124943_r66_authenticated_runtime_defect_repair.sql',
    ).readAsStringSync();
    final repository = File(
      'lib/features/notifications/repositories/notification_center_repository.dart',
    ).readAsStringSync();
    final page = File(
      'lib/features/notifications/pages/notification_center_page.dart',
    ).readAsStringSync();

    expect(sql, contains('erp_r66_delete_cloud_notification'));
    expect(sql, contains('user_key=v_key'));
    expect(
      sql,
      isNot(contains('delete from public.erp_enterprise_notifications')),
    );
    expect(repository, contains("'erp_r66_delete_cloud_notification'"));
    expect(page, contains('Delete notification'));
    expect(
      page,
      contains('_persistentNotifications = _persistentNotifications'),
    );
  });

  test('commercial cards use truthful linked-document semantics', () {
    final card = File(
      'lib/core/widgets/commercial_workflow_order_card.dart',
    ).readAsStringSync();
    expect(card, contains("t('غير مرحّل', 'Not posted')"));
    expect(card, contains("t('إذن التجهيز', 'Delivery')"));
    expect(card, contains("t('إشعار الاستلام', 'Receipt')"));
    expect(card, isNot(contains("t('كمية فقط', 'Quantity only')")));
  });
}
