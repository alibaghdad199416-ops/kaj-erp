import 'package:intl/intl.dart';

/// Central money and quantity formatting used across the ERP UI and exports.
/// IQD is displayed without fractional digits by default, while other
/// currencies keep up to two decimal places.
abstract final class MoneyFormatter {
  static final NumberFormat _integer = NumberFormat('#,##0', 'en_US');
  static final NumberFormat _decimal = NumberFormat('#,##0.##', 'en_US');
  static final NumberFormat _fixedTwo = NumberFormat('#,##0.00', 'en_US');

  static String format(num value, {String? currency, bool fixedTwo = false}) {
    if (fixedTwo) return _fixedTwo.format(value);
    if ((currency ?? '').toUpperCase() == 'IQD') {
      return _integer.format(value);
    }
    return _decimal.format(value);
  }

  static String withCurrency(
    num value,
    String currency, {
    bool currencyFirst = false,
  }) {
    final formatted = format(value, currency: currency);
    return currencyFirst ? '$currency $formatted' : '$formatted $currency';
  }

  static String quantity(num value) => _decimal.format(value);
}
