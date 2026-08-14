import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('real maintenance dialog exposes persisted partial issue lifecycle', () {
    final dialog = File(
      'lib/features/maintenance/pages/maintenance_order_details_dialog.dart',
    ).readAsStringSync();
    final repository = File(
      'lib/features/maintenance/data/maintenance_repository.dart',
    ).readAsStringSync();

    for (final contract in <String>[
      "'remainingQuantity'",
      "'Partially issued'",
      "'Issue maintenance material'",
      "'Execute issue'",
      "'Material issue events'",
      "'Reverse material issue'",
      '_repository.getIssueWarehouseOptions(partId)',
      '_repository.issueMaterial(',
      'await _loadDetails()',
      '_repository.reverseMaterialIssue(',
    ]) {
      expect(dialog, contains(contract), reason: contract);
    }

    for (final contract in <String>[
      "'erp_r57_execute_maintenance_material_issue'",
      "'p_issue_id': issueId ?? const Uuid().v4()",
      "'p_part_id': partId",
      "'p_warehouse_id': warehouseId",
      "'p_quantity': quantity",
      "'erp_r57_reverse_maintenance_material_issue'",
      "'erp_r57_maintenance_material_issue_state'",
    ]) {
      expect(repository, contains(contract), reason: contract);
    }

    expect(dialog, contains("'صرف جزئي'"));
    expect(dialog, contains("'صرف مواد الصيانة'"));
    expect(dialog, contains("'عكس عملية الصرف'"));
    expect(dialog, isNot(contains('_stageIndex >= 3 ? line.quantity : 0')));
  });
}
