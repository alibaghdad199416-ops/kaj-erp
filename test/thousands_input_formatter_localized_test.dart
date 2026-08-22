import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/utils/thousands_input_formatter.dart';

void main() {
  group('ThousandsInputFormatter localized numeric entry', () {
    test('parses Arabic-Indic digits and Arabic separators', () {
      expect(
        ThousandsInputFormatter.parse('١٢٣٬٤٥٦٫٧٥'),
        closeTo(123456.75, 0.000001),
      );
    });

    test('parses Persian digits and localized grouping', () {
      expect(
        ThousandsInputFormatter.parse('۹۸۷٬۶۵۴٫۵'),
        closeTo(987654.5, 0.000001),
      );
    });

    test('formats Arabic keyboard input instead of discarding it', () {
      final formatter = ThousandsInputFormatter(decimalDigits: 2);
      final result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: '١٢٣٤٥٦٫٧٥',
          selection: TextSelection.collapsed(offset: 9),
        ),
      );

      expect(result.text, '123,456.75');
      expect(result.selection.baseOffset, result.text.length);
    });

    test('normalizes localized minus when negatives are allowed', () {
      final formatter = ThousandsInputFormatter(allowNegative: true);
      final result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: '−١٢٣٫٥',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );

      expect(result.text, '-123.5');
    });

    test('integer fields do not retain a decimal separator', () {
      final formatter = ThousandsInputFormatter(decimalDigits: 0);
      final result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: '١٢٣٫٤',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );

      expect(result.text, '123');
    });

    test('discarded nonnumeric input keeps a valid collapsed selection', () {
      final formatter = ThousandsInputFormatter();
      final result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: 'أ',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );

      expect(result.text, isEmpty);
      expect(result.selection, const TextSelection.collapsed(offset: 0));
    });
  });
}
