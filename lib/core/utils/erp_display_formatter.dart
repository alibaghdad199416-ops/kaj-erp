import 'package:intl/intl.dart';

/// Locale-aware final display formatter. Identifiers are never parsed as
/// floating point numbers, preventing account-code corruption.
abstract final class ErpDisplayFormatter {
  static String normalizeCurrency(Object? value) {
    final code = (value ?? '').toString().trim().toUpperCase();
    return switch (code) {
      'DINAR' || 'IQD' => 'IQD',
      'DOLLAR' || 'USD' => 'USD',
      _ => code,
    };
  }

  static String accountCode(Object? value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return '-';
    final ungrouped = raw.replaceAll(',', '');
    if (!RegExp(r'^\d+(?:\.\d+)?$').hasMatch(ungrouped)) return raw;
    final separator = ungrouped.indexOf('.');
    if (separator < 0) return ungrouped;
    final whole = ungrouped.substring(0, separator);
    final fraction = ungrouped.substring(separator + 1);
    if (fraction.length < 6) return ungrouped;

    // Legacy account generators once used floating-point arithmetic and could
    // persist identifiers such as 1000.009999999. Account codes remain text:
    // repair only the recognizable long numeric artifact with decimal-string
    // arithmetic, never by parsing the identifier as double/currency.
    final cents = fraction.padRight(3, '0');
    var rounded = BigInt.parse('$whole${cents.substring(0, 2)}');
    if (int.parse(cents[2]) >= 5) rounded += BigInt.one;
    final digits = rounded.toString().padLeft(3, '0');
    final normalizedWhole = digits.substring(0, digits.length - 2);
    final normalizedFraction = digits.substring(digits.length - 2);
    return normalizedFraction == '00'
        ? normalizedWhole
        : '$normalizedWhole.$normalizedFraction';
  }

  static String number(
    num? value, {
    String locale = 'en_US',
    int maxDecimals = 2,
  }) {
    if (value == null) return '-';
    final safeDecimals = maxDecimals.clamp(0, 12);
    final pattern = safeDecimals == 0
        ? '#,##0'
        : '#,##0.${List.filled(safeDecimals, '#').join()}';
    return NumberFormat(pattern, locale).format(value);
  }

  static String money(num? value, Object? currency, {String locale = 'en_US'}) {
    final code = normalizeCurrency(currency);
    final digits = code == 'IQD' ? 0 : 2;
    return '${number(value, locale: locale, maxDecimals: digits)} $code'.trim();
  }

  static String dateTimeValue(
    Object? value, {
    String locale = 'en_US',
    bool includeTime = true,
  }) {
    if (value == null) return '-';
    final date = value is DateTime
        ? value
        : DateTime.tryParse(value.toString());
    if (date == null) return value.toString();
    return DateFormat(
      includeTime ? 'yyyy/MM/dd HH:mm' : 'yyyy/MM/dd',
      locale,
    ).format(date.toLocal());
  }
}
