import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';

void main() {
  final rows = <Map<String, Object?>>[
    {
      'reference': 'SO-101',
      'customer': 'c1',
      'createdBy': 'u1',
      'approvedBy': 'u9',
      'documentType': 'salesOrder',
      'sourceModule': 'sales',
      'amount': 1500,
      'quantity': 3,
    },
    {
      'reference': 'SO-102',
      'customer': 'c1',
      'createdBy': 'u1',
      'approvedBy': 'u8',
      'documentType': 'salesOrder',
      'sourceModule': 'sales',
      'amount': 2500,
      'quantity': 5,
    },
    {
      'reference': 'SO-103',
      'customer': 'c2',
      'createdBy': 'u2',
      'approvedBy': 'u9',
      'documentType': 'salesOrder',
      'sourceModule': 'sales',
      'amount': 3500,
      'quantity': 7,
    },
  ];

  UnifiedFilterAdapter<Map<String, Object?>> adapter() =>
      UnifiedFilterAdapter<Map<String, Object?>>(
        searchableText: (row) => [row['reference']],
        dimensions: {
          'customer': (row) => row['customer'],
          'createdBy': (row) => row['createdBy'],
          'approvedBy': (row) => row['approvedBy'],
          'documentType': (row) => row['documentType'],
          'sourceModule': (row) => row['sourceModule'],
        },
        numericDimensions: {
          'amount': (row) => row['amount'] as num?,
          'quantity': (row) => row['quantity'] as num?,
        },
        sortValues: {
          'reference': (row) => row['reference'],
          'amount': (row) => row['amount'],
        },
      );

  test('operational dimensions and numeric ranges compose with AND', () {
    final criteria = UnifiedFilterCriteria(
      searchText: 'SO',
      dimensions: const {
        'customer': {'c1'},
        'createdBy': {'u1'},
        'documentType': {'salesOrder'},
        'sourceModule': {'sales'},
      },
      numericRanges: const {
        'amount': UnifiedNumericRange(min: 1000, max: 3000),
        'quantity': UnifiedNumericRange(min: 4),
      },
    );

    final result = UnifiedFilterEngine.apply(
      rows,
      criteria: criteria,
      adapter: adapter(),
    );

    expect(result.map((row) => row['reference']), ['SO-102']);
    expect(
      criteria.activeFilterKeys,
      containsAll({
        'searchText',
        'customer',
        'createdBy',
        'documentType',
        'sourceModule',
        'amount',
        'quantity',
      }),
    );
  });

  test('sort and pagination use the already-filtered dataset', () {
    final result = UnifiedFilterEngine.apply(
      rows,
      criteria: const UnifiedFilterCriteria(
        dimensions: {
          'sourceModule': {'sales'},
        },
        sort: UnifiedSortSpec(
          'amount',
          direction: UnifiedSortDirection.descending,
        ),
        offset: 1,
        limit: 1,
      ),
      adapter: adapter(),
    );

    expect(result, hasLength(1));
    expect(result.single['reference'], 'SO-102');
  });

  test('unknown active filter dimensions fail closed', () {
    final matches = UnifiedFilterEngine.matches(
      rows.first,
      criteria: const UnifiedFilterCriteria(
        dimensions: {
          'unmappedSensitiveField': {'secret'},
        },
      ),
      adapter: adapter(),
    );

    expect(matches, isFalse);
  });

  test('unknown sort keys fail explicitly instead of silently reordering', () {
    expect(
      () => UnifiedFilterEngine.apply(
        rows,
        criteria: const UnifiedFilterCriteria(
          sort: UnifiedSortSpec('missingSort'),
        ),
        adapter: adapter(),
      ),
      throwsArgumentError,
    );
  });

  test('invalid numeric range fails closed', () {
    expect(
      const UnifiedNumericRange(min: 10, max: 5).contains(7),
      isFalse,
    );
  });
}
