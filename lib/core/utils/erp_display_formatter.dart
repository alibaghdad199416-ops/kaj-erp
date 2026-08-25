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
    // Account codes are identifiers, never numeric values. Do not parse,
    // round, regroup, or strip hierarchy separators here; PostgreSQL text is
    // the source of truth and the UI must render the same identifier.
    return raw;
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
