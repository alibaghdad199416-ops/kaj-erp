import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Formats numeric input with thousands separators while keeping a parseable
/// decimal value. Use [parse] before sending values to repositories/RPCs.
class ThousandsInputFormatter extends TextInputFormatter {
  ThousandsInputFormatter({this.decimalDigits = 2, this.allowNegative = false});

  final int decimalDigits;
  final bool allowNegative;
  static final NumberFormat _integer = NumberFormat('#,##0', 'en_US');

  static double? parse(String? value) {
    if (value == null) return null;
    return double.tryParse(value.replaceAll(',', '').trim());
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var raw = newValue.text.replaceAll(',', '').trim();
    if (raw.isEmpty || raw == '-' && allowNegative) return newValue;
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
    if (pieces.length > 1) {
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
