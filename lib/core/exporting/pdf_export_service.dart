import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:quality_line_erp/core/cloud/cloud_feature_command.dart';
import 'package:quality_line_erp/core/logging/app_logger.dart';

import 'adaptive_pdf_table.dart';
import 'binary_download_service.dart';
import 'export_document.dart';
import 'pdf_print_service.dart';
import 'report_template_engine.dart';
import '../printing/pdf_text_support.dart';
import '../printing/premium_document_theme.dart';
import '../printing/unified_pdf_document.dart';
import '../printing/unified_pdf_identity.dart';

/// Canonical PDF renderer shared by reports and generic exports.
///
/// [PremiumDocumentTheme] is the compatibility facade over the newer
/// [UnifiedPdfIdentity], so older commercial-document contracts and the unified
/// header/footer pipeline continue to resolve to one visual identity.
class PdfExportService {
  PdfExportService({ReportTemplateEngine? templateEngine})
    : _template = templateEngine ?? const ReportTemplateEngine();

  final ReportTemplateEngine _template;

  Future<Uint8List> build(
    ExportDocument document, {
    ExportPageFormat pageFormat = ExportPageFormat.a4Portrait,
    int maxColumnsPerGroup = 5,
    int maxRowsPerChunk = 12,
  }) async {
    document.validate();
    final fonts = await PdfTextSupport.loadFonts();
    final regular = fonts.regular;
    final bold = fonts.bold;
    final arabic = document.isArabic;
    final direction = arabic ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final generatedAt = document.generatedAt ?? DateTime.now();
    final branding = await _loadBranding(arabic);
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
    final effectiveColumnGroup = receipt
        ? maxColumnsPerGroup.clamp(1, 2).toInt()
        : maxColumnsPerGroup.clamp(1, 12).toInt();
    final pdf = pw.Document(
      title: document.title,
      author: branding.companyName,
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
                companyName: branding.companyName,
                logo: branding.logo,
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
              color: PremiumDocumentTheme.ink,
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
            headerColor: PremiumDocumentTheme.ink,
            alternateColor: PremiumDocumentTheme.surface,
            maxColumnsPerGroup: effectiveColumnGroup,
            maxRowsPerChunk: maxRowsPerChunk,
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

  Future<_PdfBranding> _loadBranding(bool arabic) async {
    Map<String, dynamic> row = <String, dynamic>{};
    try {
      row = await CloudFeatureCommand.instance.map(
        'company_settings',
        'branding',
      );
    } catch (error, stackTrace) {
      AppLogger.debug('PDF branding fallback: $error\n$stackTrace');
    }
    final values = <String, String>{
      for (final entry in row.entries) entry.key: entry.value?.toString() ?? '',
    };
    pw.MemoryImage? logo;
    if (!kIsWeb) {
      for (final path in const [
        'assets/images/khat_al_jawda_logo.jpg',
        'assets/images/logo.png',
      ]) {
        try {
          final data = await rootBundle.load(path);
          logo = pw.MemoryImage(data.buffer.asUint8List());
          break;
        } catch (_) {}
      }
    }
    final companyName = arabic
        ? (values['company_name']?.trim().isNotEmpty == true
              ? values['company_name']!
              : 'شركة خط الجودة')
        : (values['company_name_en']?.trim().isNotEmpty == true
              ? values['company_name_en']!
              : 'Quality Line');
    return _PdfBranding(companyName: companyName, logo: logo);
  }
}

class _PdfBranding {
  const _PdfBranding({required this.companyName, required this.logo});
  final String companyName;
  final pw.MemoryImage? logo;
}
