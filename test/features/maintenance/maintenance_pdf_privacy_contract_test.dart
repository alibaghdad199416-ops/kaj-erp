import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final pdfSource = File(
    'lib/core/printing/maintenance_document_pdf_service.dart',
  ).readAsStringSync();
  final uiSource = File(
    'lib/features/maintenance/pages/maintenance_order_details_dialog.dart',
  ).readAsStringSync();

  test('maintenance PDF has no internal cost input or rendered field', () {
    for (final forbidden in const <String>[
      'MaintenanceCostReconciliation',
      'reconciliation:',
      '.unitCost',
      '.laborCost',
      '.partsCost',
      '.totalCost',
      '.profit',
      '.carCostAdded',
      'issuedActualCost',
      'Requested materials cost',
      'Issued materials actual cost',
      'Total operational cost',
      'Warehouse cost contribution',
      'Maintenance expense account',
    ]) {
      expect(
        pdfSource,
        isNot(contains(forbidden)),
        reason: 'Internal-only PDF token leaked: $forbidden',
      );
    }
  });

  test('maintenance UI retains authoritative internal reconciliation', () {
    for (final required in const <String>[
      'getOrderSnapshot',
      'Issued materials actual cost',
      'Total operational cost',
      'Materials invoiced',
      'Outstanding',
      'Quantity reconciliation',
      'issuedActualCost',
    ]) {
      expect(uiSource, contains(required));
    }
  });

  test('maintenance work-order PDF retains customer-facing contract', () {
    for (final required in const <String>[
      'Maintenance order number',
      'Status',
      'Vehicle',
      'Customer',
      'Work description and notes',
      'Requested services, materials, and work',
      'Warehouse materials',
      'Invoice amount',
      'Paid amount',
      'Remaining balance',
      'Customer approval',
    ]) {
      expect(pdfSource, contains(required));
    }
  });
}
