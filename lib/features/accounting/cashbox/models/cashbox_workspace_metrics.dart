import 'package:quality_line_erp/features/accounting/cashbox/models/cash_account_model.dart';
import 'package:quality_line_erp/features/accounting/cashbox/models/cash_transaction_model.dart';

/// Financial summary derived from the exact transaction dataset rendered by a
/// cashbox workspace. Filtering therefore cannot make cards disagree with the
/// table or chart.
class CashboxWorkspaceMetrics {
  const CashboxWorkspaceMetrics({
    required this.openingBalance,
    required this.cashIn,
    required this.cashOut,
    required this.netMovement,
    required this.currentBalance,
  });

  final double openingBalance;
  final double cashIn;
  final double cashOut;
  final double netMovement;
  final double currentBalance;

  factory CashboxWorkspaceMetrics.fromTransactions(
    CashAccountModel account,
    Iterable<CashTransactionModel> transactions,
  ) {
    var cashIn = 0.0;
    var cashOut = 0.0;
    for (final transaction in transactions) {
      if (transaction.isReceipt) cashIn += transaction.amount;
      if (transaction.isPayment) cashOut += transaction.amount;
    }
    final netMovement = cashIn - cashOut;
    return CashboxWorkspaceMetrics(
      openingBalance: account.openingBalance,
      cashIn: cashIn,
      cashOut: cashOut,
      netMovement: netMovement,
      currentBalance: account.openingBalance + netMovement,
    );
  }
}

/// Decision-oriented daily movement buckets. Every transaction in the supplied
/// dataset contributes exactly once to one day bucket.
class CashboxDailyMovement {
  const CashboxDailyMovement({
    required this.day,
    required this.cashIn,
    required this.cashOut,
  });

  final DateTime day;
  final double cashIn;
  final double cashOut;
  double get netMovement => cashIn - cashOut;

  static List<CashboxDailyMovement> fromTransactions(
    Iterable<CashTransactionModel> transactions,
  ) {
    final buckets = <DateTime, List<double>>{};
    for (final transaction in transactions) {
      final local = transaction.transactionDate.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      final totals = buckets.putIfAbsent(day, () => <double>[0, 0]);
      if (transaction.isReceipt) totals[0] += transaction.amount;
      if (transaction.isPayment) totals[1] += transaction.amount;
    }
    final days = buckets.keys.toList()..sort();
    return days
        .map(
          (day) => CashboxDailyMovement(
            day: day,
            cashIn: buckets[day]![0],
            cashOut: buckets[day]![1],
          ),
        )
        .toList(growable: false);
  }
}
