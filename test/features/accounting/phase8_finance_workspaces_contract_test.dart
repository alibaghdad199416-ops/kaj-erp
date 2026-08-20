import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Phase 8 expenses use a horizontal toolbar and full-height result viewport',
    () {
      final source = File(
        'lib/features/accounting/expenses/pages/expenses_page.dart',
      ).readAsStringSync();

      expect(source, contains("ValueKey('expenses-horizontal-toolbar')"));
      expect(source, contains('constraints.maxWidth >= 1040'));
      expect(source, contains("ValueKey('expenses-compact-metrics')"));
      expect(source, contains("ValueKey('expenses-full-height-column')"));
      expect(source, contains("ValueKey('expenses-full-height-list')"));
      expect(source, contains('CurrencyTotalsFormatter.format(visibleTotals)'));
      expect(
        source,
        contains('PermissionAction.require(context, \'accounting.delete\')'),
      );
    },
  );

  test(
    'Phase 8 expense records switch between desktop rows and compact columns',
    () {
      final source = File(
        'lib/features/accounting/expenses/widgets/expense_card.dart',
      ).readAsStringSync();

      expect(source, contains('final desktop = constraints.maxWidth >= 900'));
      expect(source, contains("'expense-desktop-row'"));
      expect(source, contains("'expense-compact-column'"));
      expect(source, contains("'postingStatus'"));
      expect(source, contains("'approvalStatus'"));
      expect(source, contains("'convertedAmounts'"));
      expect(source, contains('Icons.delete_outline_rounded'));
    },
  );

  test(
    'Phase 8 installments keep accounting permissions and use full-height responsive rows',
    () {
      final source = File(
        'lib/features/accounting/installments/pages/installments_page.dart',
      ).readAsStringSync();

      expect(
        source,
        contains("ValueKey('installments-responsive-metric-strip')"),
      );
      expect(source, contains("ValueKey('installments-full-height-column')"));
      expect(source, contains("ValueKey('installments-full-height-list')"));
      expect(source, contains('final desktop = constraints.maxWidth >= 900'));
      expect(source, contains("'installment-desktop-row'"));
      expect(source, contains("'installment-compact-column'"));
      expect(source, contains("access.canViewField(\n      'installments'"));
      expect(source, contains('controller.totalRemainingByCurrency'));
    },
  );

  test(
    'Phase 8 account statement filters, summary and data table fill the active workspace',
    () {
      final source = File(
        'lib/features/accounting/pages/account_statement_page.dart',
      ).readAsStringSync();

      expect(
        source,
        contains("ValueKey('account-statement-horizontal-filterbar')"),
      );
      expect(source, contains('constraints.maxWidth >= 880'));
      expect(
        source,
        contains("ValueKey('account-statement-result-full-height-column')"),
      );
      expect(
        source,
        contains("ValueKey('account-statement-responsive-summary-grid')"),
      );
      expect(
        source,
        contains("ValueKey('account-statement-full-height-scroll')"),
      );
      expect(source, contains('dataRowMaxHeight: 44'));
      expect(source, contains('loadAccountStatement('));
    },
  );

  test(
    'Phase 8 trial balance uses compact controls, currency summaries and one dense table',
    () {
      final source = File(
        'lib/features/accounting/pages/accounting_center_page.dart',
      ).readAsStringSync();

      expect(
        source,
        contains("ValueKey('\${widget.type.name}-horizontal-report-toolbar')"),
      );
      expect(source, contains('constraints.maxWidth >= 980'));
      expect(
        source,
        contains("ValueKey('trial-balance-compact-table-horizontal-scroll')"),
      );
      expect(
        source,
        contains("ValueKey('\${widget.type.name}-responsive-summary-grid')"),
      );
      expect(source, contains('const minWidth = 190.0'));
      expect(source, contains('dataRowMaxHeight: 44'));
      expect(
        source,
        contains("widget.type == _AccountingReportType.trialBalance"),
      );
      expect(source, contains("'periodDebit'"));
      expect(source, contains("'periodCredit'"));
      expect(source, contains("'closingDebit'"));
      expect(source, contains("'closingCredit'"));
      expect(
        source,
        contains('ProfessionalAccountingRepository().loadReport('),
      );
    },
  );
}
