import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/models/model_value_reader.dart';

void main() {
  group('ModelValueReader', () {
    test('accepts snake_case and camelCase aliases transparently', () {
      final values = <String, dynamic>{
        'full_name': 'Ali Hassan',
        'cloudAuthUid': 'firebase-1',
      };

      expect(ModelValueReader.string(values, 'fullName'), 'Ali Hassan');
      expect(ModelValueReader.string(values, 'cloud_auth_uid'), 'firebase-1');
    });

    test('converts common Supabase scalar representations safely', () {
      final values = <String, dynamic>{
        'count': '7',
        'amount': '1250.50',
        'enabled': 1,
        'disabled': 'false',
      };

      expect(ModelValueReader.integer(values, 'count'), 7);
      expect(ModelValueReader.decimal(values, 'amount'), 1250.5);
      expect(ModelValueReader.boolean(values, 'enabled'), isTrue);
      expect(ModelValueReader.boolean(values, 'disabled'), isFalse);
    });

    test('uses explicit fallbacks instead of throwing on malformed data', () {
      final values = <String, dynamic>{
        'date': 'not-a-date',
        'items': 'not-a-list',
        'metadata': 42,
      };

      expect(ModelValueReader.dateTime(values, 'date'), isNull);
      expect(ModelValueReader.integer(values, 'missing', fallback: 9), 9);
      expect(ModelValueReader.list(values, 'items'), isEmpty);
      expect(ModelValueReader.objectMap(values, 'metadata'), isEmpty);
    });
  });
}
