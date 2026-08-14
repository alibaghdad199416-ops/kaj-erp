import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/features/customer_service/models/opportunity_model.dart';
import 'package:quality_line_erp/features/sales/workflow/models/commercial_order_details.dart';

void main() {
  test('OpportunityModel preserves canonical Sales and Maintenance projection', () {
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

  test('Commercial snapshot carries Sales to Opportunity context coherently', () {
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
}
