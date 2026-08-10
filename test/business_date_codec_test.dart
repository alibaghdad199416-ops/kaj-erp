import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/utils/business_date_codec.dart';

void main() {
  test('business DATE serialization never emits a timestamp', () {
    final value = DateTime(2026, 8, 10, 23, 59);
    expect(BusinessDateCodec.encode(value), '2026-08-10');
  });

  test('UTC instant is converted to local calendar date before encoding', () {
    final instant = DateTime.utc(2026, 8, 10, 12, 30);
    final local = instant.toLocal();
    final expected =
        '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
    expect(BusinessDateCodec.encode(instant), expected);
  });
}
