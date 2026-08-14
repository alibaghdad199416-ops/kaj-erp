import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/features/customer_service/models/opportunity_model.dart';
import 'package:quality_line_erp/features/sales/workflow/models/commercial_order_details.dart';

void main() {
  test('OpportunityModel preserves CRM forecast and canonical Sales projection', () {
    final opportunity = OpportunityModel.fromMap(<String, Object?>{
      'id': 'opp-1',
      'opportunityNumber': 'OPP-000001',
      'customerId': 'customer-1',
      'customerName': 'Customer',
      'customerPhone': '000',
      'title': 'Vehicle opportunity',
      'source': 'test',
      'expectedValue': 25000,
      'currency': 'iqd',
      'stage': 'negotiation',
      'probability': 80,
      'status': 'pending',
      'salesOrderId': 'sales-order-1',
      'salesOrderNumber': 'SO-000001',
      'salesOrderStatus': 'approved',
      'deliveryNumber': 'SD-000001',
      'deliveryStatus': 'approved',
      'invoiceNumber': 'SI-000001',
      'invoiceStatus': 'approved',
      'paymentStatus': 'partial',
      'paidAmount': 10000,
      'remainingAmount': 15000,
      'maintenanceOrderId': 'maintenance-order-1',
      'maintenanceOrderNumber': 'MO-000001',
      'maintenanceOrderStatus': 'order_draft',
      'assignedUserId': 'user-1',
      'assignedUserName': 'Owner',
      'createdByUserId': 'user-1',
      'createdByUserName': 'Owner',
      'createdAt': '2026-08-14T10:00:00Z',
    });

    expect(opportunity.opportunityNumber, 'OPP-000001');
    expect(opportunity.currency, 'IQD');
    expect(opportunity.expectedValue, 25000);
    expect(opportunity.probability, 80);
    expect(opportunity.saleId, 'sales-order-1');
    expect(opportunity.salesOrderNumber, 'SO-000001');
    expect(opportunity.invoiceNumber, 'SI-000001');
    expect(opportunity.paymentStatus, 'partial');
    expect(opportunity.paidAmount, 10000);
    expect(opportunity.remainingAmount, 15000);
    expect(opportunity.maintenanceOrderId, 'maintenance-order-1');
    expect(opportunity.maintenanceOrderNumber, 'MO-000001');
    expect(opportunity.maintenanceOrderStatus, 'order_draft');
    expect(opportunity.hasMaintenanceOrder, isTrue);
  });

  test('OpportunityModel protects probability display boundary', () {
    OpportunityModel build(num probability) => OpportunityModel.fromMap(
      <String, Object?>{
        'id': 'opp-$probability',
        'opportunityNumber': 'OPP-$probability',
        'customerName': 'Customer',
        'customerPhone': '',
        'title': '',
        'source': '',
        'expectedValue': 0,
        'currency': 'USD',
        'probability': probability,
        'status': 'pending',
        'assignedUserId': '',
        'assignedUserName': '',
        'createdByUserId': 'user-1',
        'createdByUserName': 'Owner',
        'createdAt': '2026-08-14T10:00:00Z',
      },
    );

    expect(build(-5).probability, 0);
    expect(build(125).probability, 100);
  });

  test('Commercial snapshot carries Sales -> Opportunity context coherently', () {
    final details = CommercialOrderDetails.fromRpc(<String, Object?>{
      'order': <String, Object?>{
        'id': 'sales-order-1',
        'orderNumber': 'SO-000001',
        'opportunityId': 'opp-1',
        'opportunityNumber': 'OPP-000001',
      },
      'items': const <Object?>[],
      'logistics': const <Object?>[],
      'invoices': const <Object?>[],
      'payments': const <Object?>[],
      'movements': const <Object?>[],
      'journalEntries': const <Object?>[],
      'auditTrail': const <Object?>[],
      'reconciliation': const <Object?>[],
      'opportunity': <String, Object?>{
        'opportunityId': 'opp-1',
        'opportunityNumber': 'OPP-000001',
        'stage': 'proposal',
        'status': 'pending',
      },
    });

    expect(details.order?['opportunityId'], 'opp-1');
    expect(details.order?['opportunityNumber'], 'OPP-000001');
    expect(details.opportunity?['opportunityNumber'], 'OPP-000001');
    expect(details.opportunity?['stage'], 'proposal');
  });

  test('R70 removes the legacy direct CRM invoice shortcut', () {
    final repository = File(
      'lib/features/customer_service/repositories/opportunity_repository.dart',
    ).readAsStringSync();
    final controller = File(
      'lib/features/customer_service/controllers/opportunities_controller.dart',
    ).readAsStringSync();
    final customerServicePage = File(
      'lib/features/customer_service/pages/customer_service_page.dart',
    ).readAsStringSync();

    expect(repository, isNot(contains('markWonAndCreateInvoice')));
    expect(repository, isNot(contains("'mark_won'")));
    expect(controller, isNot(contains('markWonAndCreateInvoice')));
    expect(customerServicePage, contains('SalesOrderDraftPage('));
    expect(customerServicePage, contains('findOrderByOpportunity'));
    expect(customerServicePage, contains('OrderDetailsDialog('));
  });

  test('R70 server owns conversion, lifecycle projection and destructive guards', () {
    final migration = File(
      'supabase/migrations/20260814170000_r70_crm_opportunity_sales_authority.sql',
    ).readAsStringSync();
    final salesRepository = File(
      'lib/features/sales/workflow/repositories/sales_workflow_repository.dart',
    ).readAsStringSync();

    expect(migration, contains('erp_r70_list_opportunities'));
    expect(migration, contains('erp_r70_opportunity_command'));
    expect(migration, contains('opportunity_won_owned_by_sales_workflow'));
    expect(migration, contains('opportunity_has_sales_history'));
    expect(migration, contains('opportunity_sales_customer_locked'));
    expect(migration, contains('opportunity_sales_currency_locked'));
    expect(migration, contains('opportunity_probability_invalid'));
    expect(migration, contains('opportunity_responsible_user_invalid'));
    expect(migration, contains('for update'));
    expect(migration, contains('erp_v2300_create_sales_order'));
    expect(migration, contains('erp_sync_opportunity_sales_lifecycle'));

    expect(salesRepository, contains('erp_r49_create_sales_order'));
    expect(salesRepository, contains("'opportunityId': opportunityId"));
    expect(salesRepository, contains('erp_r9_find_sales_order_by_opportunity'));
  });

  test('R70 Sales readback exposes the human Opportunity identity', () {
    final migration = File(
      'supabase/migrations/20260814171000_r70_1_sales_opportunity_readback.sql',
    ).readAsStringSync();
    final model = File(
      'lib/features/customer_service/models/opportunity_model.dart',
    ).readAsStringSync();
    final card = File(
      'lib/features/customer_service/widgets/opportunity_card.dart',
    ).readAsStringSync();

    expect(migration, contains('erp_r70_get_sales_opportunity_context'));
    expect(migration, contains("'opportunityNumber'"));
    expect(migration, contains('erp_r62_get_commercial_order_snapshot'));
    expect(model, contains('salesOrderNumber'));
    expect(card, contains('opportunity.salesOrderNumber'));
  });

  test('R70 assigns short server-owned Opportunity business references', () {
    final migration = File(
      'supabase/migrations/20260814172000_r70_2_opportunity_business_reference.sql',
    ).readAsStringSync();
    expect(migration, contains('erp_opportunity_business_reference_seq'));
    expect(migration, contains("'OPP-'||lpad"));
    expect(migration, contains('erp_records_opportunity_reference_uq'));
  });

  test('R70 browser cannot invoke the historical direct Won authorities', () {
    final migration = File(
      'supabase/migrations/20260814173000_r70_3_legacy_crm_execution_closure.sql',
    ).readAsStringSync();
    expect(migration, contains('erp_r49_opportunity_command(text,jsonb)'));
    expect(
      migration,
      contains('erp_r9_phase26_cloud_command(text,text,jsonb)'),
    );
    expect(migration, contains('from public,anon,authenticated'));
  });

  test('R70 conversion does not collapse physical or accounting stages', () {
    final migration = File(
      'supabase/migrations/20260814170000_r70_crm_opportunity_sales_authority.sql',
    ).readAsStringSync();

    final createStart = migration.indexOf(
      'create or replace function public.erp_r49_create_sales_order',
    );
    expect(createStart, greaterThanOrEqualTo(0));
    final createBody = migration.substring(createStart);

    expect(createBody, isNot(contains('approve_sales')));
    expect(createBody, isNot(contains('create_sales_delivery')));
    expect(createBody, isNot(contains('create_cloud_sales_workflow_invoice')));
    expect(createBody, isNot(contains('pay_cloud_sales')));
    expect(createBody, isNot(contains('journal')));
    expect(createBody, isNot(contains('inventory_movement')));
  });

  test('R70.4 scopes Lost guard to new Sales links and exposes Maintenance', () {
    final migration = File(
      'supabase/migrations/20260814222000_r70_4_opportunity_sales_maintenance_runtime_repair.sql',
    ).readAsStringSync();
    final card = File(
      'lib/features/customer_service/widgets/opportunity_card.dart',
    ).readAsStringSync();

    expect(migration, contains('v_same_historical_link'));
    expect(migration, contains('v_cancel_restore'));
    expect(migration, contains('v_creates_or_relinks'));
    expect(migration, contains("raise exception 'opportunity_is_lost'"));
    expect(migration, contains("'maintenanceOrderId'"));
    expect(migration, contains("'maintenanceOrderNumber'"));
    expect(migration, contains("'maintenanceOrderStatus'"));
    expect(migration, contains('erp_r56_find_maintenance_by_opportunity'));
    expect(card, contains('AddMaintenanceOrderPage('));
    expect(card, contains('MaintenanceOrderDetailsDialog('));
    expect(card, contains("'maintenance.cancel'"));
    expect(card, contains("'maintenance.delete'"));
    expect(card, contains('opportunity.hasMaintenanceOrder'));
  });
}
