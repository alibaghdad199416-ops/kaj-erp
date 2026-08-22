import 'package:intl/intl.dart';

/// Canonical typed display contract for ERP values.
///
/// Callers must choose the semantic type they are rendering instead of sending
/// every value through a generic decimal formatter. This keeps money,
/// quantities and rates numeric while identifiers, years and references remain
/// text and can never become values such as `2026.00` or `INV-101.00`.
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
    if (RegExp(r'^0+$').hasMatch(fraction)) return whole;
    if (fraction.length <= 2) return '$whole${fraction.padRight(2, '0')}';

    // Legacy generators used floating-point arithmetic. Round the fractional
    // artifact as decimal text and concatenate it into the identifier; never
    // expose punctuation that can make an account code look like money.
    final cents = fraction.padRight(3, '0');
    var rounded = BigInt.parse('$whole${cents.substring(0, 2)}');
    if (int.parse(cents[2]) >= 5) rounded += BigInt.one;
    final digits = rounded.toString().padLeft(3, '0');
    final normalizedWhole = digits.substring(0, digits.length - 2);
    final normalizedFraction = digits.substring(digits.length - 2);
    return '$normalizedWhole$normalizedFraction';
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

  /// Typed alias used by new code. IQD renders with zero fractional digits;
  /// USD and other currencies retain up to two fractional digits.
  static String formatMoney(
    num? value,
    Object? currency, {
    String locale = 'en_US',
  }) => money(value, currency, locale: locale);

  /// Quantities are numeric measurements, not identifiers.
  static String formatQuantity(
    num? value, {
    String locale = 'en_US',
    int maxDecimals = 3,
  }) => number(value, locale: locale, maxDecimals: maxDecimals);

  /// Rates may require more precision than user-facing money.
  static String formatRate(
    num? value, {
    String locale = 'en_US',
    int maxDecimals = 6,
  }) => number(value, locale: locale, maxDecimals: maxDecimals);

  static String formatPercentage(
    num? value, {
    String locale = 'en_US',
    int maxDecimals = 2,
    bool includeSymbol = true,
  }) {
    final formatted = number(value, locale: locale, maxDecimals: maxDecimals);
    if (value == null || !includeSymbol) return formatted;
    return '$formatted%';
  }

  /// Integer counters may be grouped for readability, but fractional input is
  /// never silently rounded into a different business value.
  static String formatInteger(Object? value, {String locale = 'en_US'}) {
    if (value == null) return '-';
    final raw = value.toString().trim();
    if (raw.isEmpty) return '-';
    final parsed = value is num ? value : num.tryParse(raw.replaceAll(',', ''));
    if (parsed == null || !parsed.isFinite || parsed != parsed.truncateToDouble()) {
      return raw;
    }
    return NumberFormat('#,##0', locale).format(parsed.toInt());
  }

  /// References, VINs, phone numbers, IDs, serials and document numbers are
  /// semantic text. Never parse or decimal-format them.
  static String formatReference(Object? value) {
    final raw = (value ?? '').toString().trim();
    return raw.isEmpty ? '-' : raw;
  }

  /// Years are integer-like identifiers and deliberately have no grouping or
  /// decimal suffix. Legacy numeric text such as `2026.00` is normalized only
  /// when it is exactly integral.
  static String formatYear(Object? value) {
    if (value == null) return '-';
    final raw = value.toString().trim();
    if (raw.isEmpty) return '-';
    final parsed = value is num ? value : num.tryParse(raw.replaceAll(',', ''));
    if (parsed == null || !parsed.isFinite || parsed != parsed.truncateToDouble()) {
      return raw;
    }
    return parsed.toInt().toString();
  }

  static String formatDate(Object? value, {String locale = 'en_US'}) =>
      dateTimeValue(value, locale: locale, includeTime: false);

  static String formatDateTime(Object? value, {String locale = 'en_US'}) =>
      dateTimeValue(value, locale: locale, includeTime: true);

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
