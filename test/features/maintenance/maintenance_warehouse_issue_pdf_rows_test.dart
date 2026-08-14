import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/printing/maintenance_document_pdf_service.dart';
import 'package:quality_line_erp/features/maintenance/models/maintenance_order_model.dart';
import 'package:quality_line_erp/features/maintenance/models/maintenance_cost_reconciliation.dart';

void main() {
  const line = MaintenanceLineModel(
    id: 'line-a',
    productId: 'product-a',
    productName: 'Product A',
    quantity: 10,
    unitCost: 70,
    unitPrice: 180,
    lineType: 'stock',
    warehouseId: 'requested-warehouse',
    warehouseName: 'Requested warehouse',
  );

  Map<String, Object?> event({
    required String id,
    required String warehouseId,
    required String warehouseName,
    required num quantity,
    String status = 'executed',
  }) => <String, Object?>{
    'issueId': id,
    'status': status,
    'lineId': line.id,
    'productId': line.productId,
    'warehouseId': warehouseId,
    'warehouseName': warehouseName,
    'quantity': quantity,
  };

  List<MaintenanceWarehouseIssueRow> rows(List<Map<String, Object?>> events) =>
      maintenanceWarehouseIssueRows(lines: const [line], issueEvents: events);

  test('one warehouse uses the executed issue quantity', () {
    final result = rows([
      event(id: 'ISS-1', warehouseId: 'a', warehouseName: 'A', quantity: 6),
    ]);
    expect(result.single.warehouseName, 'A');
    expect(result.single.quantity, 6);
  });

  test('two warehouses remain separate', () {
    final result = rows([
      event(id: 'ISS-1', warehouseId: 'a', warehouseName: 'A', quantity: 7),
      event(id: 'ISS-2', warehouseId: 'b', warehouseName: 'B', quantity: 3),
    ]);
    expect(result.map((row) => row.quantity), [7, 3]);
    expect(result.map((row) => row.warehouseName), ['A', 'B']);
  });

  test('multiple issue events in the same warehouse aggregate safely', () {
    final result = rows([
      event(id: 'ISS-1', warehouseId: 'a', warehouseName: 'A', quantity: 4),
      event(id: 'ISS-2', warehouseId: 'a', warehouseName: 'A', quantity: 6),
    ]);
    expect(result.single.quantity, 10);
    expect(result.single.issueReferences, ['ISS-1', 'ISS-2']);
  });

  test('reversed issue does not appear', () {
    final result = rows([
      event(
        id: 'ISS-1',
        warehouseId: 'a',
        warehouseName: 'A',
        quantity: 10,
        status: 'reversed',
      ),
    ]);
    expect(result, isEmpty);
  });

  test('partial issue prints only actual cumulative quantity', () {
    expect(
      rows([
        event(id: 'ISS-1', warehouseId: 'a', warehouseName: 'A', quantity: 4),
      ]).single.quantity,
      4,
    );
  });

  test('final issue produces the requested full quantity', () {
    final result = rows([
      event(id: 'ISS-1', warehouseId: 'a', warehouseName: 'A', quantity: 4),
      event(id: 'ISS-2', warehouseId: 'b', warehouseName: 'B', quantity: 6),
    ]);
    expect(result.fold<double>(0, (total, row) => total + row.quantity), 10);
  });

  test('warehouse PDF row total equals active issue-event total', () {
    final events = [
      event(id: 'ISS-1', warehouseId: 'a', warehouseName: 'A', quantity: 7),
      event(id: 'ISS-2', warehouseId: 'b', warehouseName: 'B', quantity: 3),
      event(
        id: 'ISS-3',
        warehouseId: 'a',
        warehouseName: 'A',
        quantity: 2,
        status: 'reversed',
      ),
    ];
    final activeTotal = events
        .where((row) => row['status'] == 'executed')
        .fold<double>(0, (total, row) => total + (row['quantity']! as num));
    final pdfTotal = rows(
      events,
    ).fold<double>(0, (total, row) => total + row.quantity);
    expect(pdfTotal, activeTotal);
  });

  test('RPC JSON maps through Dart reconciliation into PDF rows', () {
    final reconciliation = mergeMaintenanceReconciliationPayloads(
      reconciliation: <String, Object?>{
        'currency': 'USD',
        'lines': <Map<String, Object?>>[
          <String, Object?>{
            'lineId': line.id,
            'lineType': 'stock',
            'issuedQuantity': 0,
          },
        ],
      },
      issueState: <String, Object?>{
        'issuedMaterialsActualCost': 35,
        'lines': <Map<String, Object?>>[
          <String, Object?>{'lineId': line.id, 'issuedQuantity': 7},
        ],
        'warehouses': const <Map<String, Object?>>[],
        'events': <Map<String, Object?>>[
          event(
            id: 'issue-1',
            warehouseId: 'warehouse-main',
            warehouseName: 'BGW',
            quantity: 7,
          ),
        ],
      },
    );
    final result = maintenanceWarehouseIssueRows(
      lines: const [line],
      issueEvents: reconciliation.issueEvents,
      fallbackIssueReference: 'MIS0004',
    );
    expect(reconciliation.issueEvents, hasLength(1));
    expect(reconciliation.lines.single['issuedQuantity'], 7);
    expect(result.single.productName, 'Product A');
    expect(result.single.warehouseName, 'BGW');
    expect(result.single.quantity, 7);
    expect(result.single.issueReferences, ['MIS0004']);
  });

  test('two-warehouse raw RPC events survive runtime mapping', () {
    final result = maintenanceWarehouseIssueRows(
      lines: const [line],
      issueEvents: [
        event(id: '1', warehouseId: 'a', warehouseName: 'BGW', quantity: 4),
        event(id: '2', warehouseId: 'b', warehouseName: 'EBL', quantity: 3),
      ],
      fallbackIssueReference: 'MIS0004',
    );
    expect(result.map((row) => row.quantity), [4, 3]);
    expect(
      result.every((row) => row.issueReferences.single == 'MIS0004'),
      isTrue,
    );
  });

  test('valid event survives missing warehouse display enrichment', () {
    final result = maintenanceWarehouseIssueRows(
      lines: const [line],
      issueEvents: [
        event(
          id: '1',
          warehouseId: 'warehouse-main',
          warehouseName: '',
          quantity: 7,
        ),
      ],
    );
    expect(result, hasLength(1));
    expect(result.single.warehouseId, 'warehouse-main');
    expect(result.single.quantity, 7);
  });

  test(
    'issued stock document with no printable rows fails integrity',
    () async {
      const order = MaintenanceOrderModel(
        id: 'order-1',
        orderNumber: 'MO00006',
        carId: 'car-1',
        carName: 'Car',
        warehouseId: 'warehouse-main',
        isSoldCar: true,
        pricingType: 'paid',
        status: 'approved',
        laborCost: 0,
        partsCost: 35,
        totalCost: 35,
        salePrice: 140,
        profit: 105,
        carCostAdded: 0,
        maintenanceDate: '2026-08-13',
        stockIssueNumber: 'MIS0004',
      );
      expect(
        () => const MaintenanceDocumentPdfService().build(
          order: order,
          lines: const [line],
          issueEvents: const <Map<String, Object?>>[],
          authoritativeIssuedQuantity: 7,
          arabic: false,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'maintenance_issue_document_rows_missing',
          ),
        ),
      );
    },
  );

  test('maintenance page external print callback passes reconciliation', () {
    final source = File(
      'lib/features/maintenance/pages/maintenance_page.dart',
    ).readAsStringSync();
    expect(source, contains('controller.getCostReconciliation(order.id)'));
    expect(source, contains('issueEvents: reconciliation.issueEvents'));
    expect(
      source,
      contains('authoritativeIssuedQuantity: reconciliation.lines'),
    );
  });

  test('order page prints all persisted requested lines', () {
    final source = File(
      'lib/core/printing/maintenance_document_pdf_service.dart',
    ).readAsStringSync();
    expect(source, contains('final requestedLineChunks = chunksOf(lines)'));
    expect(source, contains('linesTable(requestedLineChunks[index])'));
    expect(source, isNot(contains('chunksOf(serviceLines)')));
  });

  test('order and issue tables share readable header cells', () {
    final source = File(
      'lib/core/printing/maintenance_document_pdf_service.dart',
    ).readAsStringSync();
    expect(source, contains('pw.Widget tableHeaderCell(String value)'));
    expect(source, contains('color: PdfColors.white'));
    expect(
      RegExp(
        r'children: \[for \(final value in headers\) tableHeaderCell\(value\)\]',
      ).allMatches(source).length,
      2,
    );
  });

  test('dialog reloads persisted lines when initial lines are empty', () {
    final source = File(
      'lib/features/maintenance/pages/maintenance_order_details_dialog.dart',
    ).readAsStringSync();
    expect(source, contains('var exportLines = _lines'));
    expect(source, contains('await _repository.getOrderSnapshot(_order.id)'));
    expect(source, contains('lines: exportLines'));
  });
}
