import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/features/settings/reports/models/contextual_report_section.dart';
import 'package:quality_line_erp/features/settings/reports/models/report_export_options.dart';
import 'package:quality_line_erp/features/settings/reports/services/contextual_report_customizer.dart';
import 'package:quality_line_erp/features/settings/reports/services/report_field_localizer.dart';

void main() {
  test('unified report engine projects filters and sorts module data', () {
    const section = ContextualReportSection(
      key: 'cars',
      title: 'Cars',
      columns: ['Name', 'Year', 'Status'],
      rows: [
        ['B', '2022', 'Available'],
        ['A', '2024', 'Sold'],
        ['C', '2023', 'Available'],
      ],
    );
    const options = ReportExportOptions(
      selectedColumns: {
        'cars': ['Name', 'Year'],
      },
      sectionQueries: {'cars': 'available'},
      sortColumns: {'cars': 'Year'},
      sortAscending: {'cars': false},
    );

    final result = const ContextualReportCustomizer().apply(const [
      section,
    ], options);

    expect(result.single.columns, ['Name', 'Year']);
    expect(result.single.rows, [
      ['C', '2023'],
      ['B', '2022'],
    ]);
  });

  test('report customization survives json persistence', () {
    const options = ReportExportOptions(
      selectedColumns: {
        'sales': ['Invoice', 'Total'],
      },
      sectionQueries: {'sales': 'USD'},
      sortColumns: {'sales': 'Total'},
      sortAscending: {'sales': true},
    );
    final restored = ReportExportOptions.fromJson(options.toJson());
    expect(restored.selectedColumns, options.selectedColumns);
    expect(restored.sectionQueries, options.sectionQueries);
    expect(restored.sortColumns, options.sortColumns);
    expect(restored.sortAscending, options.sortAscending);
  });

  test('report sections can be disabled and row limits are applied last', () {
    const options = ReportExportOptions(
      sectionEnabled: {'hidden': false, 'visible': true},
      sectionRowLimits: {'visible': 1},
      sortColumns: {'visible': 'Total'},
      sortAscending: {'visible': false},
    );
    final result = const ContextualReportCustomizer().apply(const [
      ContextualReportSection(
        key: 'hidden',
        title: 'Hidden',
        columns: ['Total'],
        rows: [
          ['999'],
        ],
      ),
      ContextualReportSection(
        key: 'visible',
        title: 'Visible',
        columns: ['Total'],
        rows: [
          ['10'],
          ['20'],
        ],
      ),
    ], options);

    expect(result, hasLength(1));
    expect(result.single.key, 'visible');
    expect(result.single.rows, [
      ['20'],
    ]);
  });

  test(
    'report field identifiers are localized without changing their keys',
    () {
      expect(ReportFieldLocalizer.localize('orderNumber', 'ar'), 'رقم الأمر');
      expect(
        ReportFieldLocalizer.localize('orderNumber', 'en'),
        'Order number',
      );
      expect(
        ReportFieldLocalizer.localize('Sales orders / أوامر البيع', 'ar'),
        'أوامر البيع',
      );
      expect(
        ReportFieldLocalizer.localize('Sales orders / أوامر البيع', 'en'),
        'Sales Orders',
      );
    },
  );
}
