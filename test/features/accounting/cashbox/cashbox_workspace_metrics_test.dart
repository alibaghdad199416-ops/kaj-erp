import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/features/accounting/cashbox/models/cash_account_model.dart';
import 'package:quality_line_erp/features/accounting/cashbox/models/cash_transaction_model.dart';
import 'package:quality_line_erp/features/accounting/cashbox/models/cashbox_workspace_metrics.dart';

CashTransactionModel tx({
  required String id,
  required String type,
  required double amount,
  required DateTime date,
}) => CashTransactionModel(
  id: id,
  voucherNumber: 'V-$id',
  type: type,
  category: 'manual',
  amount: amount,
  currency: 'USD',
  transactionDate: date,
  partyType: 'other',
  paymentMethod: 'cash',
  createdAt: date,
  cashAccountId: 'cash-1',
);

void main() {
  final account = CashAccountModel(
    id: 'cash-1',
    name: 'Main cashbox',
    type: 'cash',
    currency: 'USD',
    openingBalance: 100,
    isActive: true,
    accountId: 'ledger-1',
    createdAt: DateTime.utc(2026, 8, 1),
  );

  test('cashbox metrics derive all five values from one transaction dataset', () {
    final transactions = <CashTransactionModel>[
      tx(
        id: '1',
        type: 'receipt',
        amount: 75,
        date: DateTime.utc(2026, 8, 20, 8),
      ),
      tx(
        id: '2',
        type: 'payment',
        amount: 20,
        date: DateTime.utc(2026, 8, 20, 10),
      ),
      tx(
        id: '3',
        type: 'receipt',
        amount: 5,
        date: DateTime.utc(2026, 8, 21, 9),
      ),
    ];

    final metrics = CashboxWorkspaceMetrics.fromTransactions(
      account,
      transactions,
    );

    expect(metrics.openingBalance, 100);
    expect(metrics.cashIn, 80);
    expect(metrics.cashOut, 20);
    expect(metrics.netMovement, 60);
    expect(metrics.currentBalance, 160);
  });

  test('daily movement buckets include every filtered transaction once', () {
    final transactions = <CashTransactionModel>[
      tx(
        id: '1',
        type: 'receipt',
        amount: 75,
        date: DateTime(2026, 8, 20, 8),
      ),
      tx(
        id: '2',
        type: 'payment',
        amount: 20,
        date: DateTime(2026, 8, 20, 10),
      ),
      tx(
        id: '3',
        type: 'payment',
        amount: 5,
        date: DateTime(2026, 8, 21, 9),
      ),
    ];

    final days = CashboxDailyMovement.fromTransactions(transactions);

    expect(days, hasLength(2));
    expect(days.first.cashIn, 75);
    expect(days.first.cashOut, 20);
    expect(days.first.netMovement, 55);
    expect(days.last.cashIn, 0);
    expect(days.last.cashOut, 5);
  });

  test('cashbox workspace keeps query, metrics, chart, table and export aligned', () {
    final source = File(
      'lib/features/accounting/cashbox/pages/cashbox_page.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('controller.transactionsForCashbox(widget.account.id)'),
    );
    expect(source, contains('CashboxWorkspaceMetrics.fromTransactions('));
    expect(source, contains('_CashboxMovementChart('));
    expect(source, contains('transactions: transactions'));
    expect(source, contains('_transactionTable(controller, transactions)'));
    expect(source, contains('_export(controller, transactions)'));
    expect(source, contains('controller.setTransactionFilter('));
    expect(source, contains('criteria.activeFilterKeys'));
    expect(source, contains("'sourceModule'"));
    expect(source, contains("'paymentType'"));
    expect(source, contains("'amount'"));
    expect(source, contains('decimalDigits: 20'));
    expect(source, isNot(contains('controller.transactions\n            .where')));
  });
}
