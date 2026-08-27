import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';

void main() {
  test('generic field filters compose with search and sorting', () {
    final rows = <Map<String, String>>[
      {'status': 'open', 'owner': 'Ahmed', 'amount': '20'},
      {'status': 'closed', 'owner': 'Ahmed', 'amount': '50'},
      {'status': 'open', 'owner': 'Ali', 'amount': '80'},
    ];

    final result = UnifiedFilterEngine.apply<Map<String, String>>(
      rows,
      criteria: const UnifiedFilterCriteria(
        searchText: 'ahmed',
        fieldValues: <String, Set<String>>{
          'status': <String>{'open'},
        },
      ),
      adapter: UnifiedFilterAdapter<Map<String, String>>(
        searchableText: (row) => row.values,
        fieldValues: <String, Object? Function(Map<String, String>)>{
          'status': (row) => row['status'],
        },
      ),
      sorts: [
        UnifiedSortCriterion<Map<String, String>>(
          key: 'amount',
          value: (row) => int.parse(row['amount']!),
          direction: UnifiedSortDirection.descending,
        ),
      ],
    );

    expect(result.length, 1);
    expect(result.single['owner'], 'Ahmed');
  });
}
