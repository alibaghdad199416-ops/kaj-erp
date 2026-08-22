import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/printing/maintenance_document_pdf_service.dart';
import 'package:quality_line_erp/features/maintenance/models/maintenance_cost_reconciliation.dart';
import 'package:quality_line_erp/features/maintenance/models/maintenance_order_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('partial requested issued and invoiced quantities remain distinct', () {
    final value = MaintenanceCostReconciliation.fromMap(
      _payload(currency: 'USD', paid: 40, outstanding: 60),
    );

    expect(value.currency, 'USD');
    expect(value.requestedMaterialsCost, 150);
    expect(value.requestedCostAvailable, isTrue);
    expect(value.issuedMaterialsActualCost, 90);
    expect(value.materialsInvoiced, 60);
    expect(value.paid, 40);
    expect(value.outstanding, 60);
    expect(value.lines.single['requestedQuantity'], 10);
    expect(value.lines.single['issuedQuantity'], 6);
    expect(value.lines.single['invoicedQuantity'], 4);
    expect(value.lines.single['remainingQuantity'], 4);
    expect(value.issueEvents.single['issueId'], 'issue-1');
    expect(value.materialDiscrepancy, isTrue);
  });

  for (final currency in const ['USD', 'IQD']) {
    test(
      '$currency labor-only, materials, payment and warehouse totals parse',
      () {
        final value = MaintenanceCostReconciliation.fromMap(
          _payload(currency: currency, paid: 100, outstanding: 0),
        );
        expect(value.currency, currency);
        expect(value.totalOperationalCost, 140);
        expect(value.totalInvoiced, 100);
        expect(value.paid + value.outstanding, value.totalInvoiced);
        expect(value.warehouses.single['issuedActualCost'], 90);
        expect(value.discount, isNull);
        expect(value.tax, isNull);
      },
    );
  }

  test('unrecoverable historical requested cost remains unavailable', () {
    final payload = _payload(currency: 'USD', paid: 0, outstanding: 100)
      ..['requestedCostAvailable'] = false
      ..['requestedMaterialsCost'] = null;
    final value = MaintenanceCostReconciliation.fromMap(payload);
    expect(value.requestedCostAvailable, isFalse);
    expect(value.requestedMaterialsCost, isNull);
  });

  for (final arabic in const [false, true]) {
    test(
      'maintenance PDF stays valid without internal costs in ${arabic ? 'AR' : 'EN'}',
      () async {
        final reconciliation = MaintenanceCostReconciliation.fromMap(
          _payload(currency: arabic ? 'IQD' : 'USD', paid: 40, outstanding: 60),
        );
        final bytes = await const MaintenanceDocumentPdfService().build(
          order: _order(currency: reconciliation.currency),
          lines: const <MaintenanceLineModel>[
            MaintenanceLineModel(
              id: 'line-1',
              productId: 'product-1',
              productName: 'Brake pads',
              warehouseId: 'warehouse-1',
              warehouseName: 'Main warehouse',
              quantity: 10,
              unitCost: 15,
              unitPrice: 15,
              lineType: 'stock',
            ),
          ],
          arabic: arabic,
        );
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        expect(bytes.length, greaterThan(10000));
      },
    );
  }
}

Map<String, Object?> _payload({
  required String currency,
  required double paid,
  required double outstanding,
}) => <String, Object?>{
  'currency': currency,
  'workflowStage': 'invoice_approved',
  'hasApprovedInvoice': true,
  'requestedCostAvailable': true,
  'requestedMaterialsCost': 150,
  'issuedMaterialsActualCost': 90,
  'laborCost': 50,
  'additionalServicesCost': 0,
  'totalOperationalCost': 140,
  'materialsInvoiced': 60,
  'laborInvoiced': 40,
  'servicesInvoiced': 0,
  'discount': null,
  'tax': null,
  'totalInvoiced': 100,
  'paid': paid,
  'outstanding': outstanding,
  'issuedNotInvoicedCost': 30,
  'invoicedNotIssuedValue': 0,
  'materialDiscrepancy': true,
  'laborDiscrepancy': true,
  'lines': <Map<String, Object?>>[
    <String, Object?>{
      'description': 'Brake pads',
      'requestedQuantity': 10,
      'issuedQuantity': 6,
      'invoicedQuantity': 4,
      'remainingQuantity': 4,
    },
  ],
  'warehouses': <Map<String, Object?>>[
    <String, Object?>{
      'warehouseName': 'Main warehouse',
      'issuedQuantity': 6,
      'issuedActualCost': 90,
    },
  ],
  'issueEvents': <Map<String, Object?>>[
    <String, Object?>{
      'issueId': 'issue-1',
      'status': 'executed',
      'warehouseName': 'Main warehouse',
      'quantity': 6,
    },
  ],
};

MaintenanceOrderModel _order({required String currency}) =>
    MaintenanceOrderModel(
      id: 'order-1',
      orderNumber: 'MO-R57-001',
      carId: 'car-1',
      carName: 'Test vehicle',
      customerId: 'customer-1',
      customerName: 'Test customer',
      warehouseId: 'warehouse-1',
      isSoldCar: true,
      pricingType: 'paid',
      status: 'approved',
      laborCost: 50,
      partsCost: 90,
      totalCost: 140,
      salePrice: 100,
      profit: -40,
      carCostAdded: 0,
      maintenanceDate: '2026-08-12',
      currencyCode: currency,
      workflowStage: 'invoice_approved',
      paidAmount: 40,
      invoiceNumber: 'MINV-R57-001',
      stockIssueNumber: 'MSI-R57-001',
    );
