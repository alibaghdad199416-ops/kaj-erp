import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';

void main() {
  test('all populated conditions are combined with logical AND', () {
    final rows = <Map<String, Object?>>[
      {
        'name': 'Toyota Camry',
        'warehouse': 'w1',
        'status': 'available',
        'currency': 'USD',
      },
      {
        'name': 'Toyota Corolla',
        'warehouse': 'w2',
        'status': 'available',
        'currency': 'USD',
      },
      {
        'name': 'Toyota Camry',
        'warehouse': 'w1',
        'status': 'sold',
        'currency': 'USD',
      },
    ];

    final result = UnifiedFilterEngine.apply(
      rows,
      criteria: const UnifiedFilterCriteria(
        searchText: 'camry',
        warehouseIds: {'w1'},
        statuses: {'available'},
        currencies: {'USD'},
      ),
      adapter: UnifiedFilterAdapter<Map<String, Object?>>(
        searchableText: (row) => [row['name']],
        warehouseId: (row) => row['warehouse'],
        status: (row) => row['status'],
        currency: (row) => row['currency'],
      ),
    );

    expect(result, hasLength(1));
    expect(result.single['name'], 'Toyota Camry');
  });

  test('Arabic diacritics and alef forms do not break search', () {
    expect(
      UnifiedFilterEngine.normalize('إدارةُ السّيّارات'),
      UnifiedFilterEngine.normalize('ادارة السيارات'),
    );
  });
}
