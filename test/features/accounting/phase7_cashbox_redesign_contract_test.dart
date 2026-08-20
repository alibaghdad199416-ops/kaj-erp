import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/features/accounting/cashbox/widgets/cash_transaction_card.dart';

void main() {
  test('Phase 7 cashbox workspace is compact, horizontal and full-height', () {
    final source = File(
      'lib/features/accounting/cashbox/pages/cashbox_page.dart',
    ).readAsStringSync();

    expect(source, contains('final body = ListView('));
    expect(source, contains('child: widget.embedded'));
    expect(source, contains('Widget _cashAccounts('));
    expect(source, contains('final cashIn = accountTransactions'));
    expect(source, contains('final cashOut = accountTransactions'));
    expect(source, contains('onTap: () => _openCashboxDetail('));
    expect(source, contains("_openAdd('receipt', cashAccountId: account.id)"));
    expect(source, contains("_openAdd('payment', cashAccountId: account.id)"));
    expect(source, contains('onPressed: _openTransfer'));
  });

  test('Phase 7 preserves cashbox accounting and FX workflow boundaries', () {
    final source = File(
      'lib/features/accounting/cashbox/pages/cashbox_page.dart',
    ).readAsStringSync();

    expect(source, contains("legacyPermission: 'accounting.update'"));
    expect(source, contains("legacyPermission: 'accounting.delete'"));
    expect(source, contains('controller.transferBetweenAccounts('));
    expect(source, contains('ThousandsInputFormatter(decimalDigits: 20)'));
    expect(source, contains('linkedCashAccountId'));
    expect(source, contains('cashAccounts'));
    expect(source, contains('reconciliation'));
  });

  test(
    'Phase 7 transaction rows switch between desktop and compact layouts',
    () {
      expect(CashTransactionCard, isNotNull);
      final source = File(
        'lib/features/accounting/cashbox/widgets/cash_transaction_card.dart',
      ).readAsStringSync();

      expect(source, contains('final desktop = constraints.maxWidth >= 900'));
      expect(source, contains("ValueKey('cash-transaction-desktop-row')"));
      expect(source, contains("ValueKey('cash-transaction-compact-column')"));
      expect(source, contains('Icons.visibility_outlined'));
      expect(source, contains('Icons.print_outlined'));
      expect(source, contains('Icons.edit_outlined'));
      expect(source, contains('Icons.delete_outline'));
      expect(source, isNot(contains('PopupMenuButton<String>')));
    },
  );
}
