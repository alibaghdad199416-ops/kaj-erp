import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/utils/currency_totals_formatter.dart';
import 'package:quality_line_erp/core/widgets/compact_metric_pill.dart';

class CarsStatistics extends StatelessWidget {
  const CarsStatistics({
    super.key,
    required this.totalCars,
    required this.availableCars,
    required this.purchasingCars,
    required this.sellingCars,
    required this.reservedCars,
    required this.soldCars,
    required this.totalValueByCurrency,
    this.showTotalValue = true,
  });

  final int totalCars;
  final int availableCars;
  final int purchasingCars;
  final int sellingCars;
  final int reservedCars;
  final int soldCars;
  final Map<String, double> totalValueByCurrency;
  final bool showTotalValue;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CompactMetricPill(
          icon: Icons.directions_car_outlined,
          label: 'إجمالي السيارات',
          value: '$totalCars',
        ),
        const SizedBox(width: 7),
        CompactMetricPill(
          icon: Icons.check_circle_outline,
          label: 'المتوفرة',
          value: '$availableCars',
        ),
        const SizedBox(width: 7),
        CompactMetricPill(
          icon: Icons.local_shipping_outlined,
          label: 'قيد الشراء',
          value: '$purchasingCars',
        ),
        const SizedBox(width: 7),
        CompactMetricPill(
          icon: Icons.shopping_cart_checkout,
          label: 'قيد البيع',
          value: '$sellingCars',
        ),
        const SizedBox(width: 7),
        CompactMetricPill(
          icon: Icons.bookmark_border_rounded,
          label: 'المحجوزة',
          value: '$reservedCars',
        ),
        const SizedBox(width: 7),
        CompactMetricPill(
          icon: Icons.sell_outlined,
          label: 'المباعة',
          value: '$soldCars',
        ),
        if (showTotalValue) ...[
          const SizedBox(width: 7),
          CompactMetricPill(
            icon: Icons.account_balance_wallet_outlined,
            label: 'قيمة المخزون',
            value: CurrencyTotalsFormatter.format(totalValueByCurrency),
          ),
        ],
      ],
    );
  }
}
