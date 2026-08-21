import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/operations/operational_line_lifecycle.dart';

void main() {
  test('commercial operational aliases map into canonical lifecycle', () {
    final line = OperationalLineLifecycle.fromMap(<String, Object?>{
      'itemId': 'p-1',
      'description': 'Brake pads',
      'orderedQuantity': 10,
      'operationalQuantity': 6,
      'invoicedQuantity': 4,
      'remainingOperational': 4,
      'remainingInvoice': 2,
    });

    expect(line.requestedQuantity, 10);
    expect(line.logisticsQuantity, 6);
    expect(line.invoicedQuantity, 4);
    expect(line.remainingLogisticsQuantity, 4);
    expect(line.remainingInvoiceQuantity, 2);
    expect(line.progress, OperationalLineProgress.partiallyInvoiced);
  });

  test('maintenance remainingQuantity derives authoritative issued quantity', () {
    final line = OperationalLineLifecycle.fromMap(<String, Object?>{
      'lineId': 'part-1',
      'lineType': 'stock',
      'requestedQuantity': 8,
      'remainingQuantity': 3,
      'invoicedQuantity': 4,
    });

    expect(line.hasAuthoritativeReconciliation, isTrue);
    expect(line.logisticsQuantity, 5);
    expect(line.remainingLogisticsQuantity, 3);
    expect(line.invoiceableQuantity, 5);
    expect(line.remainingInvoiceQuantity, 1);
    expect(line.hasOverInvoice, isFalse);
  });

  test('service line is invoiceable without warehouse logistics', () {
    final line = OperationalLineLifecycle.fromMap(<String, Object?>{
      'lineId': 'svc-1',
      'lineType': 'service',
      'description': 'Labor',
      'requestedQuantity': 3,
      'issuedQuantity': 0,
      'invoicedQuantity': 2,
    });

    expect(line.requiresLogistics, isFalse);
    expect(line.logisticsQuantity, 0);
    expect(line.remainingLogisticsQuantity, 0);
    expect(line.invoiceableQuantity, 3);
    expect(line.remainingInvoiceQuantity, 1);
    expect(line.hasOverInvoice, isFalse);
    expect(line.progress, OperationalLineProgress.partiallyInvoiced);
  });

  test('service over-invoice is compared with requested quantity', () {
    final line = OperationalLineLifecycle.fromMap(<String, Object?>{
      'lineType': 'service',
      'requestedQuantity': 1,
      'invoicedQuantity': 2,
    });

    expect(line.hasOverLogistics, isFalse);
    expect(line.hasOverInvoice, isTrue);
    expect(line.progress, OperationalLineProgress.invalid);
  });

  test('stock invoice remains bounded by approved logistics', () {
    final line = OperationalLineLifecycle.fromMap(<String, Object?>{
      'lineType': 'stock',
      'requestedQuantity': 10,
      'issuedQuantity': 4,
      'invoicedQuantity': 5,
    });

    expect(line.requiresLogistics, isTrue);
    expect(line.invoiceableQuantity, 4);
    expect(line.hasOverInvoice, isTrue);
  });
}
