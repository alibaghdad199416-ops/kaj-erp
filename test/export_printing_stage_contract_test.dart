import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/exporting/export_document.dart';
import 'package:quality_line_erp/core/exporting/report_template_engine.dart';

void main() {
  test('export document rejects rows with a mismatched column count', () {
    const document = ExportDocument(
      title: 'Cars',
      columns: [ExportColumn(key: 'id', label: 'ID')],
      rows: [
        [],
        ['1'],
      ],
    );
    expect(document.validate, throwsStateError);
  });

  test('template formats IQD without fractional digits', () {
    const engine = ReportTemplateEngine();
    const document = ExportDocument(
      title: 'Sales',
      currency: 'IQD',
      language: 'en',
      columns: [
        ExportColumn(key: 'total', label: 'Total', type: ExportValueType.money),
      ],
      rows: [],
    );
    expect(
      engine.formatValue(1250000, document.columns.first, document),
      contains('1,250,000'),
    );
  });

  test('template generates a safe file name', () {
    const engine = ReportTemplateEngine();
    const document = ExportDocument(
      title: 'تقرير / المبيعات',
      columns: [ExportColumn(key: 'x', label: 'X')],
      rows: [],
    );
    expect(engine.fileName(document, 'pdf'), endsWith('.pdf'));
  });
}
