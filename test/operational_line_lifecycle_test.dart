import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/operations/operational_line_lifecycle.dart';

void main() {
  group('OperationalLineLifecycle', () {
    test('normalizes commercial operational aliases', () {
      final line = OperationalLineLifecycle.fromMap(<String, Object?>{
        'lineId': 'sale-1',
        'requestedQuantity': 10,
        'operationalQuantity': 4,
        'remainingOperational': 6,
        'invoicedQuantity': 2,
      });

      expect(line.hasAuthoritativeReconciliation, isTrue);
      expect(line.logisticsQuantity, 4);
      expect(line.remainingLogisticsQuantity, 6);
      expect(line.invoiceableQuantity, 4);
      expect(line.remainingInvoiceQuantity, 2);
    });

    test('derives execution from remainingOperational when needed', () {
      final line = OperationalLineLifecycle.fromMap(<String, Object?>{
        'requestedQuantity': 10,
        'remainingOperational': 6,
      });

      expect(line.hasAuthoritativeReconciliation, isTrue);
      expect(line.logisticsQuantity, 4);
      expect(line.remainingLogisticsQuantity, 6);
    });

    test('tracks partial execution centrally', () {
      final line = OperationalLineLifecycle.fromMap(<String, Object?>{
        'requestedQuantity': 10,
        'executedQuantity': 6,
      });

      expect(line.remainingLogisticsQuantity, 4);
      expect(line.invoiceableQuantity, 6);
      expect(line.remainingInvoiceQuantity, 6);
      expect(line.progress, OperationalLineProgress.partialLogistics);
    });

    test('tracks partial invoicing against executed stock quantity', () {
      final line = OperationalLineLifecycle.fromMap(<String, Object?>{
        'requestedQuantity': 10,
        'executedQuantity': 6,
        'invoicedQuantity': 4,
      });

      expect(line.remainingLogisticsQuantity, 4);
      expect(line.remainingInvoiceQuantity, 2);
      expect(line.hasOverInvoice, isFalse);
      expect(line.progress, OperationalLineProgress.partiallyInvoiced);
    });

    test('detects over execution', () {
      final line = OperationalLineLifecycle.fromMap(<String, Object?>{
        'requestedQuantity': 10,
        'executedQuantity': 11,
      });

      expect(line.hasOverLogistics, isTrue);
      expect(line.hasIntegrityViolation, isTrue);
      expect(line.progress, OperationalLineProgress.invalid);
    });

    test('detects over invoicing against authoritative execution', () {
      final line = OperationalLineLifecycle.fromMap(<String, Object?>{
        'requestedQuantity': 10,
        'executedQuantity': 6,
        'invoicedQuantity': 7,
      });

      expect(line.invoiceableQuantity, 6);
      expect(line.hasOverInvoice, isTrue);
      expect(line.remainingInvoiceQuantity, 0);
      expect(line.progress, OperationalLineProgress.invalid);
    });

    test('authoritative zero execution still blocks stock invoicing', () {
      final line = OperationalLineLifecycle.fromMap(<String, Object?>{
        'requestedQuantity': 10,
        'operationalQuantity': 0,
        'invoicedQuantity': 1,
      });

      expect(line.hasAuthoritativeReconciliation, isTrue);
      expect(line.invoiceableQuantity, 0);
      expect(line.hasOverInvoice, isTrue);
      expect(line.remainingInvoiceQuantity, 0);
    });

    test('maintenance service line never requires warehouse logistics', () {
      final line = OperationalLineLifecycle.fromMap(<String, Object?>{
        'lineType': 'service',
        'requestedQuantity': 3,
        'operationalQuantity': 0,
        'invoicedQuantity': 2,
      });

      expect(line.requiresLogistics, isFalse);
      expect(line.hasAuthoritativeReconciliation, isFalse);
      expect(line.logisticsQuantity, 0);
      expect(line.remainingLogisticsQuantity, 0);
      expect(line.invoiceableQuantity, 3);
      expect(line.remainingInvoiceQuantity, 1);
      expect(line.hasOverInvoice, isFalse);
    });

    test('draft row without reconciliation falls back to requested quantity', () {
      final line = OperationalLineLifecycle.fromMap(<String, Object?>{
        'requestedQuantity': 10,
        'invoicedQuantity': 4,
      });

      expect(line.hasAuthoritativeReconciliation, isFalse);
      expect(line.logisticsQuantity, 0);
      expect(line.invoiceableQuantity, 10);
      expect(line.remainingLogisticsQuantity, 10);
      expect(line.remainingInvoiceQuantity, 6);
      expect(line.hasOverInvoice, isFalse);
    });
  });
}
