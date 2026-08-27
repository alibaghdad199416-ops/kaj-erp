import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/features/settings/recycle_bin/models/recycle_bin_item.dart';

void main() {
  test('uses a human payload value before any record identifier', () {
    final item = RecycleBinItem.fromMap({
      'entity_type': 'cars',
      'record_id': '550e8400-e29b-41d4-a716-446655440000',
      'payload': {'brand': 'Toyota', 'model': 'Camry'},
    });

    expect(item.title, 'Toyota');
  });

  test('does not expose a full UUID when no human value exists', () {
    final item = RecycleBinItem.fromMap({
      'entity_type': 'cars',
      'record_id': '550e8400-e29b-41d4-a716-446655440000',
      'payload': const <String, dynamic>{},
    });

    expect(item.title, 'سيارة — 550e8400');
    expect(item.title, isNot('550e8400-e29b-41d4-a716-446655440000'));
  });

  test('prefers a human deleted-by name when supplied', () {
    final item = RecycleBinItem.fromMap({
      'entity_type': 'customers',
      'record_id': '1',
      'deleted_by': '550e8400-e29b-41d4-a716-446655440000',
      'deleted_by_name': 'علي بغداد',
      'payload': {'name': 'Customer A'},
    });

    expect(item.deletedBy, '550e8400-e29b-41d4-a716-446655440000');
    expect(item.deletedByName, 'علي بغداد');
  });
}
