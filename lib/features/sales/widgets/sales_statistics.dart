import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/widgets/compact_metric_pill.dart';
import 'package:quality_line_erp/core/utils/currency_totals_formatter.dart';

class SalesStatistics extends StatelessWidget {
  const SalesStatistics({
    super.key,
    required this.totalSales,
    required this.revenueByCurrency,
    required this.paidByCurrency,
    required this.remainingByCurrency,
  });

  final int totalSales;
  final Map<String, double> revenueByCurrency;
  final Map<String, double> paidByCurrency;
  final Map<String, double> remainingByCurrency;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        CompactMetricPill(
          icon: Icons.receipt_long_outlined,
          label: 'عدد المبيعات',
          value: '$totalSales',
        ),
        CompactMetricPill(
          icon: Icons.payments_outlined,
          label: 'إجمالي المبيعات',
          value: CurrencyTotalsFormatter.format(revenueByCurrency),
        ),
        CompactMetricPill(
          icon: Icons.account_balance_wallet_outlined,
          label: 'المبالغ المستلمة',
          value: CurrencyTotalsFormatter.format(paidByCurrency),
        ),
        CompactMetricPill(
          icon: Icons.pending_actions_outlined,
          label: 'المتبقي',
          value: CurrencyTotalsFormatter.format(remainingByCurrency),
        ),
      ],
    );
  }
}
