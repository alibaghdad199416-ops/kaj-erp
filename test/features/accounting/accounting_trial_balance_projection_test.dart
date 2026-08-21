import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Trial Balance renders all six lifecycle balance columns', () {
    final source = File(
      'lib/features/accounting/pages/accounting_center_page.dart',
    ).readAsStringSync();

    for (final key in <String>[
      'openingDebit',
      'openingCredit',
      'periodDebit',
      'periodCredit',
      'closingDebit',
      'closingCredit',
    ]) {
      expect(
        source,
        contains("DataCell(amountCell(row, '$key'))"),
        reason: 'Trial Balance must render $key from the server row.',
      );
    }

    expect(source, contains("'runningBalance'"));
    expect(source, contains("'Running balance'"));
    expect(source, contains("'الرصيد التراكمي'"));
    expect(source, contains('trialBalanceRowIsConsistent('));
  });

  test('accounting report repository uses the guarded detailed-report RPC', () {
    final source = File(
      'lib/features/accounting/repositories/professional_accounting_repository.dart',
    ).readAsStringSync();

    expect(source, contains("'erp_r22_cloud_detailed_accounting_report'"));
    expect(source, contains("'p_from_date'"));
    expect(source, contains("'p_to_date'"));
    expect(source, contains("'p_branch_id'"));
    expect(source, contains("'p_cost_center_id'"));
  });
}
