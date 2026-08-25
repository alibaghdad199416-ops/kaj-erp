import 'package:quality_line_erp/core/utils/money_formatter.dart';

/// Formats multi-currency aggregate values without ever adding unlike
/// currencies together. Currency amounts stay independently traceable to the
/// source documents that produced them.
abstract final class CurrencyTotalsFormatter {
  static String format(Map<String, double> totals) {
    if (totals.isEmpty) return '—';

    final currencies = totals.keys.toList(growable: false)
      ..sort((a, b) {
        const priority = <String, int>{'USD': 0, 'IQD': 1};
        final left = priority[a] ?? 100;
        final right = priority[b] ?? 100;
        if (left != right) return left.compareTo(right);
        return a.compareTo(b);
      });

    return currencies
        .map(
          (currency) =>
              MoneyFormatter.withCurrency(totals[currency] ?? 0, currency),
        )
        .join(' • ');
  }
}
