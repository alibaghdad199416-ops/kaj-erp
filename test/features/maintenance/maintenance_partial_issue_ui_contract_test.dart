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
      "'Add material to issue draft'",
      "'Approve stock issue'",
      "'Maintenance material issue document'",
      "'Material issue events'",
      "'Reverse issue'",
      '_repository.getIssueWarehouseOptions(partId)',
      '_repository.saveMaterialIssueDraftLine(',
      'await _reloadDetails()',
      '_repository.reverseMaterialIssue(',
    ]) {
      expect(dialog, contains(contract), reason: contract);
    }

    for (final contract in <String>[
      "'erp_r90_save_maintenance_issue_draft_line'",
      "'p_order_id': orderId",
      "'p_part_id': partId",
      "'p_warehouse_id': warehouseId",
      "'p_quantity': quantity",
      "'erp_r57_reverse_maintenance_material_issue'",
      "'erp_r90_maintenance_material_issue_state'",
    ]) {
      expect(repository, contains(contract), reason: contract);
    }

    expect(dialog, contains("'إضافة مادة لمسودة الصرف'"));
    expect(dialog, contains("'مستند صرف مواد الصيانة'"));
    expect(dialog, contains("'عكس عملية الصرف'"));
    expect(dialog, isNot(contains('_stageIndex >= 3 ? line.quantity : 0')));
  });
}
