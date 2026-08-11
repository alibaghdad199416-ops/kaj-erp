import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/exporting/export_document.dart';
import 'package:quality_line_erp/core/exporting/report_template_engine.dart';
import 'package:quality_line_erp/core/exporting/excel_export_service.dart';
import 'package:quality_line_erp/core/exporting/pdf_export_service.dart';
import 'package:quality_line_erp/features/accounting/cashbox/models/cash_transaction_model.dart';
import 'package:quality_line_erp/features/accounting/cashbox/services/cash_voucher_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  test('Excel and PDF exporters produce real non-empty documents', () async {
    const document = ExportDocument(
      title: 'Runtime export proof',
      language: 'en',
      currency: 'USD',
      columns: [
        ExportColumn(key: 'reference', label: 'Reference'),
        ExportColumn(key: 'total', label: 'Total', type: ExportValueType.money),
      ],
      rows: [
        ['R55-001', 1250.5],
      ],
    );

    final excel = await ExcelExportService().build(document);
    final pdf = await PdfExportService().build(document);

    expect(excel.length, greaterThan(1000));
    expect(excel.take(2), orderedEquals(const [0x50, 0x4b]));
    expect(pdf.length, greaterThan(1000));
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
  });

  test(
    'cash voucher with long internal references builds a bounded PDF',
    () async {
      final voucher = CashTransactionModel(
        id: '55000000-0000-4000-8000-000000000001',
        voucherNumber: 'RV-2026-000055',
        type: 'receipt',
        category: 'Customer receipt',
        amount: 125000,
        currency: 'IQD',
        transactionDate: DateTime.utc(2026, 8, 11),
        partyType: 'customer',
        partyName: 'Quality Line Customer',
        paymentMethod: 'cash',
        referenceType: 'sales_invoice',
        referenceId: '55000000-0000-4000-8000-000000000002',
        journalEntryId: '55000000-0000-4000-8000-000000000003',
        createdAt: DateTime.utc(2026, 8, 11),
      );

      for (final arabic in const [false, true]) {
        final bytes = await const CashVoucherPdfService().build(
          voucher,
          arabic: arabic,
          cashAccountName: 'Main IQD cashbox',
          counterAccountName: 'Customer receivable IQD',
          journalEntryNumber: 'JE-2026-000055',
        );
        expect(bytes.length, greaterThan(1000));
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      }
    },
  );
}
