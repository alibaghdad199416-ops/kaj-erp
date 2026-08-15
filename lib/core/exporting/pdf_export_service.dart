import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'adaptive_pdf_table.dart';
import 'binary_download_service.dart';
import 'export_document.dart';
import 'pdf_print_service.dart';
import 'report_template_engine.dart';
import '../printing/pdf_text_support.dart';
import '../printing/unified_pdf_document.dart';
import '../printing/unified_pdf_identity.dart';

/// Canonical PDF renderer used by generic exports and as the shared fallback
/// for module reports. It intentionally uses the same KAJ / Quality Line header,
/// title hierarchy, table palette and footer as commercial documents.
class PdfExportService {
  PdfExportService({ReportTemplateEngine? templateEngine})
    : _template = templateEngine ?? const ReportTemplateEngine();

  final ReportTemplateEngine _template;

  Future<Uint8List> build(
    ExportDocument document, {
    ExportPageFormat pageFormat = ExportPageFormat.a4Portrait,
  }) async {
    document.validate();
    final fonts = await PdfTextSupport.loadFonts();
    final regular = fonts.regular;
    final bold = fonts.bold;
    final arabic = document.isArabic;
    final direction = arabic ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final generatedAt = document.generatedAt ?? DateTime.now();
    final format = switch (pageFormat) {
      ExportPageFormat.a4Portrait => PdfPageFormat.a4,
      ExportPageFormat.a4Landscape => PdfPageFormat.a4.landscape,
      ExportPageFormat.receipt80mm => PdfPageFormat(
        80 * PdfPageFormat.mm,
        500 * PdfPageFormat.mm,
        marginAll: 4 * PdfPageFormat.mm,
      ),
    };
    final landscape = pageFormat == ExportPageFormat.a4Landscape;
    final receipt = pageFormat == ExportPageFormat.receipt80mm;
    final pdf = pw.Document(
      title: document.title,
      author: 'Quality Line ERP',
      creator: 'Quality Line ERP',
      subject: document.subtitle,
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: receipt
            ? const pw.EdgeInsets.all(10)
            : const pw.EdgeInsets.fromLTRB(
                UnifiedPdfIdentity.pageMarginHorizontal,
                UnifiedPdfIdentity.pageMarginTop,
                UnifiedPdfIdentity.pageMarginHorizontal,
                UnifiedPdfIdentity.pageMarginBottom,
              ),
        textDirection: direction,
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        header: receipt
            ? null
            : (_) => UnifiedPdfDocument.documentHeader(
                bold: bold,
                documentType: document.title,
                documentNumber: document.metadata.entries
                    .map((entry) => '${entry.value ?? ''}'.trim())
                    .firstWhere(
                      (value) => value.isNotEmpty && value.length <= 28,
                      orElse: () => '',
                    ),
              ),
        footer: receipt
            ? null
            : (context) => UnifiedPdfDocument.footer(
                regular: regular,
                pageNumber: context.pageNumber,
                pageCount: context.pagesCount,
                arabic: arabic,
              ),
        build: (_) => <pw.Widget>[
          if (receipt)
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              color: UnifiedPdfIdentity.ink,
              child: PdfTextSupport.text(
                document.title,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  font: bold,
                  fontSize: 12,
                  color: UnifiedPdfIdentity.white,
                ),
              ),
            )
          else
            UnifiedPdfDocument.titleBlock(
              bold: bold,
              title: document.title,
              subtitle: document.subtitle,
              status: document.currency,
            ),
          if (document.metadata.isNotEmpty) ...[
            pw.Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final entry in document.metadata.entries)
                  UnifiedPdfDocument.summaryTile(
                    bold: bold,
                    label: entry.key,
                    value: '${entry.value ?? ''}',
                    width: receipt ? 115 : (landscape ? 155 : 125),
                  ),
                if (!receipt)
                  UnifiedPdfDocument.summaryTile(
                    bold: bold,
                    label: arabic ? 'تاريخ الإنشاء' : 'Generated at',
                    value: _template.formatValue(
                      generatedAt,
                      const ExportColumn(
                        key: 'generatedAt',
                        label: 'Generated at',
                        type: ExportValueType.dateTime,
                      ),
                      document,
                    ),
                    width: landscape ? 155 : 125,
                  ),
              ],
            ),
            pw.SizedBox(height: 10),
          ],
          if (!receipt)
            UnifiedPdfDocument.sectionHeader(
              bold: bold,
              title: arabic ? 'البيانات' : 'Data',
              trailing: '${document.rows.length}',
            ),
          ...AdaptivePdfTable.build(
            headers: document.columns.map((column) => column.label).toList(),
            rows: document.rows
                .map(
                  (row) => List<String>.generate(
                    document.columns.length,
                    (index) => _template.formatValue(
                      row[index],
                      document.columns[index],
                      document,
                    ),
                  ),
                )
                .toList(growable: false),
            regular: regular,
            bold: bold,
            arabic: arabic,
            headerColor: UnifiedPdfIdentity.tableHeader,
            alternateColor: UnifiedPdfIdentity.surface,
            maxColumnsPerGroup: receipt ? 2 : (landscape ? 8 : 6),
          ),
        ],
      ),
    );
    return pdf.save();
  }

  Future<void> preview(
    ExportDocument document, {
    ExportPageFormat pageFormat = ExportPageFormat.a4Portrait,
  }) async {
    final bytes = await build(document, pageFormat: pageFormat);
    await PdfPrintService.print(
      fileName: _template.fileName(document, 'pdf'),
      bytes: bytes,
    );
  }

  Future<void> save(
    ExportDocument document, {
    ExportPageFormat pageFormat = ExportPageFormat.a4Portrait,
  }) async {
    final bytes = await build(document, pageFormat: pageFormat);
    await BinaryDownloadService.save(
      fileName: _template.fileName(document, 'pdf'),
      bytes: bytes,
      mimeType: 'application/pdf',
    );
  }
}
