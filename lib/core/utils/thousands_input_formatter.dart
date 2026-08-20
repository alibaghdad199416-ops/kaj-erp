import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Formats numeric input with thousands separators while keeping a parseable
/// decimal value. Use [parse] before sending values to repositories/RPCs.
///
/// Numeric keyboards follow the active device locale. Arabic and Persian
/// keyboards can therefore emit Arabic-Indic/Persian digits plus U+066B/U+066C
/// decimal/grouping separators. Normalize those characters before filtering so
/// a user can enter IQD (or any other numeric amount) without the keystrokes
/// being discarded by an ASCII-only formatter.
class ThousandsInputFormatter extends TextInputFormatter {
  ThousandsInputFormatter({this.decimalDigits = 2, this.allowNegative = false});

  final int decimalDigits;
  final bool allowNegative;
  static final NumberFormat _integer = NumberFormat('#,##0', 'en_US');

  static const String _arabicIndicDigits = '٠١٢٣٤٥٦٧٨٩';
  static const String _persianDigits = '۰۱۲۳۴۵۶۷۸۹';

  static String _normalizeLocalizedNumber(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      final arabicIndex = _arabicIndicDigits.indexOf(char);
      if (arabicIndex >= 0) {
        buffer.write(arabicIndex);
        continue;
      }
      final persianIndex = _persianDigits.indexOf(char);
      if (persianIndex >= 0) {
        buffer.write(persianIndex);
        continue;
      }
      switch (char) {
        case '٫': // Arabic decimal separator (U+066B).
          buffer.write('.');
          break;
        case '٬': // Arabic thousands separator (U+066C).
        case ',':
        case ' ':
        case '\u00a0':
        case '\u202f':
          // Group separators are presentation-only and must not affect value.
          break;
        case '−': // Unicode minus sign used by some localized keyboards.
          buffer.write('-');
          break;
        default:
          buffer.write(char);
      }
    }
    return buffer.toString().trim();
  }

  static double? parse(String? value) {
    if (value == null) return null;
    final normalized = _normalizeLocalizedNumber(value);
    if (normalized.isEmpty || normalized == '-' || normalized == '.') {
      return null;
    }
    return double.tryParse(normalized);
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var raw = _normalizeLocalizedNumber(newValue.text);
    if (raw.isEmpty || raw == '-' && allowNegative) {
      return TextEditingValue(
        text: raw,
        selection: TextSelection.collapsed(offset: raw.length),
      );
    }
    if (!allowNegative) raw = raw.replaceAll('-', '');
    raw = raw.replaceAll(RegExp(r'[^0-9.\-]'), '');
    final dot = raw.indexOf('.');
    if (dot >= 0) {
      raw =
          '${raw.substring(0, dot + 1)}${raw.substring(dot + 1).replaceAll('.', '')}';
    }
    final pieces = raw.split('.');
    final integerRaw = pieces.first;
    final integerValue = int.tryParse(
      integerRaw == '' || integerRaw == '-' ? '0' : integerRaw,
    );
    if (integerValue == null) return oldValue;
    final negative = raw.startsWith('-');
    var formatted = _integer.format(integerValue.abs());
    if (negative) formatted = '-$formatted';
    if (decimalDigits > 0 && pieces.length > 1) {
      final fraction = pieces[1].substring(
        0,
        pieces[1].length.clamp(0, decimalDigits),
      );
      formatted = '$formatted.$fraction';
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
