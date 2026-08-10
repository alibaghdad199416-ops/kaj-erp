export 'erp_display_formatter.dart';
export 'thousands_input_formatter.dart';

import 'package:intl/intl.dart';

/// Applies one consistent thousands separator to user-facing quantities,
/// counts, percentages and monetary values embedded in localized labels.
/// Document identifiers, dates, times, versions and account codes are left
/// untouched because separators would change their meaning.
abstract final class DisplayNumberFormatter {
  static final NumberFormat _integer = NumberFormat('#,##0', 'en_US');
  static final NumberFormat _decimal = NumberFormat(
    '#,##0.################',
    'en_US',
  );

  static final RegExp _standaloneNumber = RegExp(
    r'(?<![A-Za-z0-9_./:\-])(-?\d{4,}(?:\.\d+)?)(?![A-Za-z0-9_./:\-])',
  );

  static String format(num value) {
    if (value is int || value == value.roundToDouble()) {
      return _integer.format(value);
    }
    return _decimal.format(value);
  }

  static String formatText(String value) {
    return value.replaceAllMapped(_standaloneNumber, (match) {
      final raw = match.group(1)!;
      final parsed = num.tryParse(raw);
      return parsed == null ? raw : format(parsed);
    });
  }
}
