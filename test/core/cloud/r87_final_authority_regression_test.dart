import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('R87 final authority and local runtime closure stays wired', () {
    final authorityMigration = File(
      'supabase/migrations/20260816235500_r87_final_authority_local_runtime_closure.sql',
    ).readAsStringSync();
    final inventoryMigration = File(
      'supabase/migrations/20260816235600_r87_inventory_car_scope_closure.sql',
    ).readAsStringSync();
    final config = File('lib/core/cloud/supabase_config.dart').readAsStringSync();
    final defines = File('dart_defines.json').readAsStringSync();
    final cashbox = File(
      'lib/features/accounting/cashbox/controllers/cashbox_controller.dart',
    ).readAsStringSync();

    for (final marker in <String>[
      'permission_grant_exceeds_authority',
      'permission_unknown:',
      "erp_r84_record_visible(p_company_id,'customer_service'",
      "erp_r84_record_visible(p_company_id,'maintenance'",
      "erp_r84_record_visible(p_company_id,'sales'",
      "erp_r84_record_visible(p_company_id,'purchases'",
      "erp_r84_record_visible(p_company_id,'cashbox'",
      "erp_r84_record_visible(p_company_id,'warehouses'",
      'erp_r56_vehicle_service_card',
      'erp_r56_business_partner_360',
      'erp_r49_business_partner_card_summary',
    ]) {
      expect(
        authorityMigration,
        contains(marker),
        reason: 'missing R87 authority marker: $marker',
      );
    }

    for (final marker in <String>[
      'erp_r49_list_inventory_warehouse_transfers',
      "erp_r84_record_visible(p_company_id,'inventory',t.created_by,null)",
      'erp_r49_list_cloud_cars_with_warehouse',
      "erp_r84_record_visible(p_company_id,'cars',c.created_by,null)",
    ]) {
      expect(
        inventoryMigration,
        contains(marker),
        reason: 'missing R87 inventory marker: $marker',
      );
    }

    expect(config, contains('http://127.0.0.1:54321'));
    expect(config, contains('quality_line_erp_local_dev'));
    expect(config, contains('Local Supabase فقط'));
    expect(config, isNot(contains('expectedProductionProjectRef')));
    expect(defines, contains('http://127.0.0.1:54321'));
    expect(defines, contains('SUPABASE_ANON_KEY'));
    expect(defines, isNot(contains('.supabase.co')));

    expect(cashbox, contains('_refreshRequested'));
    expect(cashbox, contains('_runRefreshLoop'));
    expect(cashbox, contains('_allTransactions'));
    expect(cashbox, isNot(contains('voucherNumberExists(')));
    expect(cashbox, isNot(contains('_repository.searchTransactions(')));
  });
}
