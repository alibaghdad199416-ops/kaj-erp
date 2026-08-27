import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/filtering/unified_query_state.dart';
import 'package:quality_line_erp/features/settings/reports/models/contextual_report_section.dart';
import 'package:quality_line_erp/features/settings/reports/models/report_export_options.dart';
import 'package:quality_line_erp/features/settings/reports/services/contextual_report_customizer.dart';
import 'package:quality_line_erp/features/settings/reports/services/report_field_localizer.dart';

void main() {
  test('unified report engine projects filters and sorts module data', () {
    const section = ContextualReportSection(
      key: 'cars', title: 'Cars', columns: ['Name', 'Year', 'Status'],
      rows: [['B', '2022', 'Available'], ['A', '2024', 'Sold'], ['C', '2023', 'Available']],
    );
    const options = ReportExportOptions(
      selectedColumns: {'cars': ['Name', 'Year']},
      sectionQueries: {'cars': 'available'},
      sortColumns: {'cars': 'Year'}, sortAscending: {'cars': false},
    );
    final result = const ContextualReportCustomizer().apply(const [section], options);
    expect(result.single.columns, ['Name', 'Year']);
    expect(result.single.rows, [['C', '2023'], ['B', '2022']]);
  });

  test('report customization uses unified generic field filters', () {
    const section = ContextualReportSection(
      key: 'sales', title: 'Sales', columns: ['Invoice', 'Currency', 'Status'],
      rows: [
        ['INV-001', 'IQD', 'Open'],
        ['INV-002', 'USD', 'Open'],
        ['INV-003', 'IQD', 'Paid'],
      ],
    );
    const options = ReportExportOptions(
      sectionFilters: {
        'sales': [
          UnifiedFilterToken(
            key: 'Currency',
            label: 'Currency',
            value: 'IQD',
            valueLabel: 'IQD',
          ),
          UnifiedFilterToken(
            key: 'Status',
            label: 'Status',
            value: 'Open',
            valueLabel: 'Open',
          ),
        ],
      },
    );
    final result = const ContextualReportCustomizer().apply(const [section], options);
    expect(result.single.rows, [['INV-001', 'IQD', 'Open']]);
  });

  test('report customization uses unified Arabic search normalization', () {
    const section = ContextualReportSection(
      key: 'customers', title: 'Customers', columns: ['Name', 'Status'],
      rows: [['أحمد محمد', 'نشط'], ['احمد علي', 'متوقف'], ['سعيد', 'نشط']],
    );
    const result = ContextualReportCustomizer().apply(
      const [section],
      const ReportExportOptions(sectionQueries: {'customers': 'أحمد'}),
    );
    expect(result.single.rows, [['أحمد محمد', 'نشط'], ['احمد علي', 'متوقف']]);
  });

  test('report customization survives json persistence including filters', () {
    const options = ReportExportOptions(
      selectedColumns: {'sales': ['Invoice', 'Total']},
      sectionQueries: {'sales': 'USD'},
      sectionFilters: {
        'sales': [
          UnifiedFilterToken(
            key: 'Status',
            label: 'Status',
            value: 'Paid',
            valueLabel: 'Paid',
          ),
        ],
      },
      sortColumns: {'sales': 'Total'}, sortAscending: {'sales': true},
    );
    final restored = ReportExportOptions.fromJson(options.toJson());
    expect(restored.selectedColumns, options.selectedColumns);
    expect(restored.sectionQueries, options.sectionQueries);
    expect(restored.sectionFilters['sales']?.single.value, 'Paid');
    expect(restored.sortColumns, options.sortColumns);
    expect(restored.sortAscending, options.sortAscending);
  });

  test('report sections can be disabled and row limits are applied last', () {
    const options = ReportExportOptions(
      sectionEnabled: {'hidden': false, 'visible': true},
      sectionRowLimits: {'visible': 1},
      sortColumns: {'visible': 'Total'}, sortAscending: {'visible': false},
    );
    final result = const ContextualReportCustomizer().apply(const [
      ContextualReportSection(key: 'hidden', title: 'Hidden', columns: ['Total'], rows: [['999']]),
      ContextualReportSection(key: 'visible', title: 'Visible', columns: ['Total'], rows: [['10'], ['20']]),
    ], options);
    expect(result, hasLength(1));
    expect(result.single.key, 'visible');
    expect(result.single.rows, [['20']]);
  });

  test('report field identifiers are localized without changing their keys', () {
    expect(ReportFieldLocalizer.localize('orderNumber', 'ar'), 'رقم الأمر');
    expect(ReportFieldLocalizer.localize('orderNumber', 'en'), 'Order number');
    expect(ReportFieldLocalizer.localize('Sales orders / أوامر البيع', 'ar'), 'أوامر البيع');
    expect(ReportFieldLocalizer.localize('Sales orders / أوامر البيع', 'en'), 'Sales Orders');
  });
}
