import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';
import 'package:quality_line_erp/core/filtering/unified_query_state.dart';
import 'package:quality_line_erp/features/settings/reports/models/contextual_report_section.dart';
import 'package:quality_line_erp/features/settings/reports/models/report_export_options.dart';
import 'package:quality_line_erp/features/settings/reports/services/contextual_report_customizer.dart';

void main() {
  test(
    'unified engine keeps same-key filter values as OR and dimensions as AND',
    () {
      final rows = <Map<String, String>>[
        {'status': 'open', 'currency': 'IQD'},
        {'status': 'paid', 'currency': 'IQD'},
        {'status': 'open', 'currency': 'USD'},
      ];
      final result = UnifiedFilterEngine.apply(
        rows,
        criteria: const UnifiedFilterCriteria(
          statuses: {'open', 'paid'},
          currencies: {'IQD'},
        ),
        adapter: UnifiedFilterAdapter<Map<String, String>>(
          searchableText: (row) => row.values,
          status: (row) => row['status'],
          currency: (row) => row['currency'],
        ),
      );
      expect(result, hasLength(2));
      expect(result.every((row) => row['currency'] == 'IQD'), isTrue);
    },
  );

  test(
    'report customization retains business-facing code and description columns',
    () {
      const section = ContextualReportSection(
        key: 'products',
        title: 'Products',
        columns: ['ID', 'Code', 'SKU', 'Description', 'UUID', 'RawData'],
        rows: [
          ['1', 'P-001', 'SKU-1', 'Oil filter', 'u1', '{raw}'],
        ],
      );
      final result = const ContextualReportCustomizer().apply(const [
        section,
      ], const ReportExportOptions());
      expect(result.single.columns, ['Code', 'SKU', 'Description']);
      expect(result.single.rows.single, ['P-001', 'SKU-1', 'Oil filter']);
    },
  );

  test('report customization applies persisted sort after filtering', () {
    const section = ContextualReportSection(
      key: 'items',
      title: 'Items',
      columns: ['Group', 'Name', 'Qty'],
      rows: [
        ['B', 'Z', '5'],
        ['A', 'B', '10'],
        ['C', 'A', '20'],
      ],
    );
    final options = ReportExportOptions(
      sectionFilters: {
        'items': [
          UnifiedFilterToken(
            key: 'Group',
            label: 'Group',
            value: 'A',
            valueLabel: 'A',
          ),
        ],
      },
      sortColumns: const {'items': 'Group'},
      sortAscending: const {'items': true},
    );
    final result = const ContextualReportCustomizer().apply([section], options);
    expect(result.single.rows, [
      ['A', 'B', '10'],
    ]);
  });
}
