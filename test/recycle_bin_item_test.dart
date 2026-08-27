import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/features/settings/recycle_bin/models/recycle_bin_item.dart';

void main() {
  test('prefers business reference over internal record id', () {
    final item = RecycleBinItem.fromMap({
      'entity_type': 'sales_order',
      'record_id': '2a5d0f90-9a54-4d20-8b8d-111111111111',
      'deleted_at': '2026-08-27T10:30:00Z',
      'payload': {
        'order_number': 'SO-2026-0042',
        'nameAr': 'أمر بيع بغداد',
      },
    });

    expect(item.title, 'أمر بيع بغداد');
    expect(item.displayReference, 'SO-2026-0042');
  });

  test('does not expose a UUID as the fallback title', () {
    final item = RecycleBinItem.fromMap({
      'entity_type': 'unknown',
      'record_id': '2a5d0f90-9a54-4d20-8b8d-111111111111',
      'payload': const {},
    });

    expect(item.title, 'سجل محذوف');
    expect(item.displayReference, 'غير متوفر');
  });
}
