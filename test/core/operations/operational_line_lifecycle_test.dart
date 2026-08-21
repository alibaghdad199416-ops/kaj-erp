import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/operations/operational_line_lifecycle.dart';
import 'package:quality_line_erp/features/maintenance/models/maintenance_cost_reconciliation.dart';
import 'package:quality_line_erp/features/sales/workflow/models/commercial_order_details.dart';

void main() {
  group('OperationalLineLifecycle', () {
    test('normalizes sales/purchase lifecycle quantity aliases', () {
      final line = OperationalLineLifecycle.fromMap(<String, Object?>{
        'lineId': 'line-1',
        'itemId': 'item-1',
        'description': 'Brake pads',
        'orderedQuantity': 10,
        'executedQuantity': 6,
        'invoicedQuantity': 4,
      });

      expect(line.requestedQuantity, 10);
      expect(line.logisticsQuantity, 6);
      expect(line.invoicedQuantity, 4);
      expect(line.remainingLogisticsQuantity, 4);
      expect(line.remainingInvoiceQuantity, 2);
      expect(line.progress, OperationalLineProgress.partiallyInvoiced);
      expect(line.hasIntegrityViolation, isFalse);
    });

    test('normalizes maintenance issued quantity aliases', () {
      final line = OperationalLineLifecycle.fromMap(<String, Object?>{
        'lineId': 'part-line',
        'partId': 'part-1',
        'partName': 'Oil filter',
        'requestedQty': '3',
        'issuedQty': 3,
        'invoiceQty': 0,
      });

      expect(line.itemId, 'part-1');
      expect(line.description, 'Oil filter');
      expect(line.logisticsComplete, isTrue);
      expect(line.remainingLogisticsQuantity, 0);
      expect(line.remainingInvoiceQuantity, 3);
      expect(line.progress, OperationalLineProgress.readyToInvoice);
    });

    test('flags over-logistics and over-invoice payloads', () {
      final overLogistics = OperationalLineLifecycle.fromMap(
        <String, Object?>{
          'quantity': 2,
          'receivedQuantity': 3,
          'invoicedQuantity': 1,
        },
      );
      final overInvoice = OperationalLineLifecycle.fromMap(<String, Object?>{
        'quantity': 5,
        'deliveredQuantity': 3,
        'invoicedQuantity': 4,
      });

      expect(overLogistics.hasOverLogistics, isTrue);
      expect(overLogistics.progress, OperationalLineProgress.invalid);
      expect(overInvoice.hasOverInvoice, isTrue);
      expect(overInvoice.progress, OperationalLineProgress.invalid);
    });
  });

  test('commercial details expose authoritative reconciliation lifecycle', () {
    final details = CommercialOrderDetails.fromRpc(<String, Object?>{
      'items': <Object?>[
        <String, Object?>{'lineId': 'line-1', 'quantity': 10},
      ],
      'reconciliation': <Object?>[
        <String, Object?>{
          'lineId': 'line-1',
          'orderedQuantity': 10,
          'executedQuantity': 8,
          'invoicedQuantity': 5,
        },
      ],
    });

    expect(details.lifecycleLines, hasLength(1));
    expect(details.lifecycleLines.single.logisticsQuantity, 8);
    expect(details.lifecycleLines.single.remainingInvoiceQuantity, 3);
  });

  test('maintenance reconciliation uses the shared lifecycle contract', () {
    final reconciliation = MaintenanceCostReconciliation.fromMap(
      <String, Object?>{
        'currency': 'IQD',
        'lines': <Object?>[
          <String, Object?>{
            'lineId': 'part-line',
            'partId': 'part-1',
            'requestedQuantity': 4,
            'issuedQuantity': 2,
            'invoicedQuantity': 1,
          },
        ],
      },
    );

    expect(reconciliation.lifecycleLines, hasLength(1));
    final line = reconciliation.lifecycleLines.single;
    expect(line.requestedQuantity, 4);
    expect(line.logisticsQuantity, 2);
    expect(line.invoicedQuantity, 1);
    expect(line.remainingLogisticsQuantity, 2);
    expect(line.remainingInvoiceQuantity, 1);
  });
}
