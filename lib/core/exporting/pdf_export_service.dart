import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'adaptive_pdf_table.dart';
import 'export_document.dart';
import 'report_template_engine.dart';
import '../printing/premium_document_theme.dart';
import '../printing/pdf_text_support.dart';
import 'binary_download_service.dart';
import 'pdf_print_service.dart';

class PdfExportService {
  PdfExportService({ReportTemplateEngine? templateEngine})
    : _template = templateEngine ?? const ReportTemplateEngine();

  final ReportTemplateEngine _template;

  Future<Uint8List> build(
    ExportDocument document, {
    ExportPageFormat pageFormat = ExportPageFormat.a4Portrait,
  }) async {
    document.validate();
    document = ExportDocument(
      title: document.title,
      subtitle: document.subtitle,
      columns: document.columns,
      rows: document.rows,
      metadata: document.metadata,
      language: document.language,
      currency: document.currency,
      generatedAt: document.generatedAt,
    );
    final pdf = pw.Document(
      title: document.title,
      author: 'Quality Line ERP',
      creator: 'Quality Line ERP',
      subject: document.subtitle,
    );
    final fonts = await PdfTextSupport.loadFonts();
    final regular = fonts.regular;
    final bold = fonts.bold;
    final format = switch (pageFormat) {
      ExportPageFormat.a4Portrait => PdfPageFormat.a4,
      ExportPageFormat.a4Landscape => PdfPageFormat.a4.landscape,
      ExportPageFormat.receipt80mm => PdfPageFormat(
        80 * PdfPageFormat.mm,
        500 * PdfPageFormat.mm,
        marginAll: 4 * PdfPageFormat.mm,
      ),
    };
    final direction = document.isArabic
        ? pw.TextDirection.rtl
        : pw.TextDirection.ltr;
    final ink = PremiumDocumentTheme.ink;
    final accent = PremiumDocumentTheme.accent;
    final accentSoft = PremiumDocumentTheme.accentSoft;
    final surface = PremiumDocumentTheme.surface;
    final border = PremiumDocumentTheme.border;
    final generatedAt = document.generatedAt ?? DateTime.now();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.fromLTRB(26, 24, 26, 24),
        textDirection: direction,
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        header: (_) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 8),
          decoration: pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: accent, width: 1.2)),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Container(
                width: 28,
                height: 28,
                decoration: pw.BoxDecoration(
                  color: ink,
                  borderRadius: pw.BorderRadius.circular(7),
                ),
                alignment: pw.Alignment.center,
                child: PdfTextSupport.text(
                  'QL',
                  style: pw.TextStyle(font: bold, fontSize: 10, color: accent),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  PdfTextSupport.text(
                    document.isArabic ? 'نظام خط الجودة' : 'QUALITY LINE ERP',
                    style: pw.TextStyle(font: bold, fontSize: 10, color: ink),
                  ),
                  PdfTextSupport.text(
                    document.isArabic
                        ? 'وثيقة إلكترونية معتمدة'
                        : 'Official electronic document',
                    style: const pw.TextStyle(
                      fontSize: 6.5,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ),
              pw.Spacer(),
              PdfTextSupport.text(
                document.title,
                style: pw.TextStyle(font: bold, fontSize: 12, color: ink),
                maxLines: 2,
              ),
            ],
          ),
        ),
        footer: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 7),
          decoration: pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: border, width: .5)),
          ),
          child: pw.Row(
            children: [
              PdfTextSupport.text(
                _template.formatValue(
                  generatedAt,
                  const ExportColumn(
                    key: 'generatedAt',
                    label: 'Generated at',
                    type: ExportValueType.dateTime,
                  ),
                  document,
                ),
                style: const pw.TextStyle(fontSize: 6.5),
              ),
              pw.Spacer(),
              PdfTextSupport.text(
                '${context.pageNumber}/${context.pagesCount}',
                style: pw.TextStyle(font: bold, fontSize: 7, color: ink),
              ),
            ],
          ),
        ),
        build: (_) => [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: ink,
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      PdfTextSupport.text(
                        document.title,
                        style: pw.TextStyle(
                          font: bold,
                          fontSize: 20,
                          color: PdfColors.white,
                        ),
                      ),
                      if (document.subtitle?.trim().isNotEmpty == true) ...[
                        pw.SizedBox(height: 4),
                        PdfTextSupport.text(
                          document.subtitle!.trim(),
                          style: pw.TextStyle(fontSize: 8.5, color: accentSoft),
                        ),
                      ],
                    ],
                  ),
                ),
                if (document.currency?.trim().isNotEmpty == true)
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: pw.BoxDecoration(
                      color: accent,
                      borderRadius: pw.BorderRadius.circular(7),
                    ),
                    child: PdfTextSupport.text(
                      document.currency!,
                      style: pw.TextStyle(font: bold, fontSize: 10, color: ink),
                    ),
                  ),
              ],
            ),
          ),
          if (document.metadata.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Wrap(
              spacing: 7,
              runSpacing: 7,
              children: document.metadata.entries
                  .map(
                    (entry) => pw.Container(
                      width: pageFormat == ExportPageFormat.a4Landscape
                          ? 155
                          : 125,
                      padding: const pw.EdgeInsets.all(7),
                      decoration: pw.BoxDecoration(
                        color: surface,
                        border: pw.Border.all(color: border, width: .45),
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          PdfTextSupport.text(
                            entry.key,
                            style: pw.TextStyle(
                              font: bold,
                              fontSize: 6.5,
                              color: PdfColors.grey700,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          PdfTextSupport.text(
                            '${entry.value ?? ''}',
                            style: pw.TextStyle(
                              font: bold,
                              fontSize: 8.5,
                              color: ink,
                            ),
                            maxLines: 4,
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          pw.SizedBox(height: 12),
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
                .toList(),
            regular: regular,
            bold: bold,
            arabic: document.isArabic,
            headerColor: ink,
            alternateColor: accentSoft,
            maxColumnsPerGroup: pageFormat == ExportPageFormat.a4Landscape
                ? 8
                : 6,
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
    final name = _template.fileName(document, 'pdf');
    await BinaryDownloadService.save(
      fileName: name,
      bytes: bytes,
      mimeType: 'application/pdf',
    );
  }
}
