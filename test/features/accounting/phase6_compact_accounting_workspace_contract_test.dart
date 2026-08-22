import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'accounting center uses one horizontal section strip and one active workspace',
    () {
      final source = File(
        'lib/features/accounting/pages/accounting_center_page.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('AppEntityPage(')));
      expect(source, contains("ValueKey('accounting-root-tight-viewport')"));
      expect(
        source,
        contains("ValueKey('accounting-root-full-height-column')"),
      );
      expect(source, contains("ValueKey('accounting-section-horizontal-nav')"));
      expect(source, contains('scrollDirection: Axis.horizontal'));
      expect(source, contains('late int _selected;'));
      expect(source, contains('switch (_selected)'));
      expect(
        source,
        contains('onSelected: (_) => setState(() => _selected = index)'),
      );
      expect(
        source,
        isNot(contains("ValueKey('accounting-continuous-workspace')")),
      );
      expect(source, isNot(contains('itemCount: _sections.length')));
    },
  );

  test('active accounting section fills the available width and height', () {
    final source = File(
      'lib/features/accounting/pages/accounting_center_page.dart',
    ).readAsStringSync();

    expect(
      source,
      contains("ValueKey('accounting-active-section-full-viewport')"),
    );
    expect(source, contains("ValueKey('accounting-active-section-expanded')"));
    expect(source, contains('child: SizedBox.expand('));
    expect(
      source,
      contains("ValueKey('accounting-active-section-\$_selected')"),
    );
    expect(
      source,
      contains('padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 12, 0)'),
    );
  });

  test(
    'selected accounting modules are embedded without stacking all modules vertically',
    () {
      final source = File(
        'lib/features/accounting/pages/accounting_center_page.dart',
      ).readAsStringSync();

      expect(source, contains('AccountingPage(embedded: true)'));
      expect(source, contains('return CashboxPage('));
      expect(source, contains('embedded: true,'));
      expect(source, contains('ExpensesPage(embedded: true)'));
      expect(source, contains('InstallmentsPage(embedded: true)'));
      expect(source, contains('AccountStatementPage(embedded: true)'));
      expect(source, contains('FixedAssetsPage(embedded: true)'));
      expect(source, isNot(contains('continuous: true')));
    },
  );

  test(
    'chart of accounts uses a connected compact command row and flat tree rows',
    () {
      final source = File(
        'lib/features/accounting/pages/accounting_center_page.dart',
      ).readAsStringSync();

      expect(source, contains('constraints.maxWidth < 760'));
      expect(source, contains("'Root accounts'"));
      expect(source, contains('return DecoratedBox('));
      expect(
        source,
        contains('visualDensity: const VisualDensity(vertical: -2)'),
      );
      expect(source, contains('shape: const Border()'));
    },
  );

  test(
    'journal workspace derives KPI columns from actual width and keeps controls horizontal',
    () {
      final source = File(
        'lib/features/accounting/pages/accounting_page.dart',
      ).readAsStringSync();

      expect(source, contains('minCardWidth = 190.0'));
      expect(source, contains('.clamp(1, 6)'));
      expect(source, contains('constraints.maxWidth < 860'));
      expect(source, contains('Expanded(child: search)'));
      expect(source, contains('MaterialTapTargetSize.shrinkWrap'));
    },
  );

  test(
    'journal entries and empty state stay compact without dropping edit/delete actions',
    () {
      final source = File(
        'lib/features/accounting/pages/accounting_page.dart',
      ).readAsStringSync();

      expect(source, contains('EdgeInsets.only(bottom: 7)'));
      expect(source, contains('EdgeInsetsDirectional.fromSTEB(11, 0, 5, 0)'));
      expect(source, contains("'No matching journal entries.'"));
      expect(source, contains("AppTranslation.translate('تعديل القيد')"));
      expect(source, contains("AppTranslation.translate('حذف القيد')"));
      expect(source, isNot(contains('padding: EdgeInsets.all(50)')));
      expect(source, isNot(contains('SizedBox(height: 80)')));
    },
  );

  test('embedded accounting sections suppress nested page shells', () {
    final cashbox = File(
      'lib/features/accounting/cashbox/pages/cashbox_page.dart',
    ).readAsStringSync();
    final installments = File(
      'lib/features/accounting/installments/pages/installments_page.dart',
    ).readAsStringSync();
    final statement = File(
      'lib/features/accounting/pages/account_statement_page.dart',
    ).readAsStringSync();
    final expenses = File(
      'lib/features/accounting/expenses/pages/expenses_page.dart',
    ).readAsStringSync();

    expect(cashbox, contains('this.embedded = false'));
    expect(cashbox, contains('child: widget.embedded'));
    expect(cashbox, contains('? content'));
    expect(cashbox, contains('final body = ListView('));
    expect(installments, contains('this.embedded = false'));
    expect(installments, contains('if (widget.embedded)'));
    expect(installments, contains('CompactMetricPill('));
    expect(statement, contains('this.embedded = false'));
    expect(statement, contains('if (widget.embedded && !widget.continuous)'));
    expect(expenses, contains('this.embedded = false'));
  });

  test(
    'every primary accounting section owns the remaining viewport height',
    () {
      final center = File(
        'lib/features/accounting/pages/accounting_center_page.dart',
      ).readAsStringSync();
      final journal = File(
        'lib/features/accounting/pages/accounting_page.dart',
      ).readAsStringSync();
      final cashbox = File(
        'lib/features/accounting/cashbox/pages/cashbox_page.dart',
      ).readAsStringSync();
      final installments = File(
        'lib/features/accounting/installments/pages/installments_page.dart',
      ).readAsStringSync();
      final statement = File(
        'lib/features/accounting/pages/account_statement_page.dart',
      ).readAsStringSync();

      expect(
        center,
        contains("ValueKey('accounting-chart-full-height-column')"),
      );
      expect(
        center,
        contains("ValueKey('\${widget.type.name}-full-height-report-column')"),
      );
      expect(
        center,
        contains("ValueKey('financial-dimensions-full-height-column')"),
      );
      expect(center, contains('class _AccountingDataViewport'));
      expect(center, contains('return SizedBox.expand('));

      expect(
        journal,
        contains("ValueKey('journal-entries-full-height-column')"),
      );
      expect(journal, contains("ValueKey('journal-entries-full-height-list')"));

      expect(cashbox, contains('final body = ListView('));
      expect(cashbox, contains('child: widget.embedded'));

      expect(
        installments,
        contains("ValueKey('installments-full-height-column')"),
      );
      expect(
        installments,
        contains("ValueKey('installments-full-height-list')"),
      );

      expect(
        statement,
        contains("ValueKey('account-statement-full-height-column')"),
      );
      expect(statement, contains('account-statement-full-height-scroll'));
    },
  );

  test(
    'accounting bypasses content-sized entity-page heuristics at the root',
    () {
      final center = File(
        'lib/features/accounting/pages/accounting_center_page.dart',
      ).readAsStringSync();
      final shell = File(
        'lib/core/widgets/app_module_shell.dart',
      ).readAsStringSync();
      final entityPage = File(
        'lib/core/widgets/app_entity_page.dart',
      ).readAsStringSync();

      expect(center, isNot(contains('AppEntityPage(')));
      expect(center, contains('return SizedBox.expand('));
      expect(
        center,
        contains("ValueKey('accounting-active-section-expanded')"),
      );
      expect(shell, contains('Expanded('));
      expect(shell, contains('_WorkspaceCanvas(child: moduleContent)'));
      expect(entityPage, contains('maxHeight: constraints.maxHeight * 0.38'));
      expect(entityPage, contains('Expanded(child: bodyPanel)'));
      expect(
        entityPage,
        isNot(contains('Expanded(flex: 3, child: bodyPanel)')),
      );
    },
  );
}
