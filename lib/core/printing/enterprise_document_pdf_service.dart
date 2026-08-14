import 'kaj_final_pdf_layout.dart';
import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;

import 'package:quality_line_erp/core/cloud/cloud_feature_command.dart';
import 'package:quality_line_erp/core/exporting/pdf_print_service.dart';

import 'package:quality_line_erp/core/localization/domain_translation_catalog.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';
import 'package:quality_line_erp/core/release/app_release_info.dart';
import 'package:quality_line_erp/core/printing/pdf_text_support.dart';
import 'package:quality_line_erp/core/printing/premium_document_theme.dart';
import 'package:quality_line_erp/core/printing/enterprise_document_presentation.dart';

/// Generates the official light-theme PDF package for sales and purchase
/// documents. The document is deliberately self-contained so the same bytes
/// can be printed, downloaded, archived, or attached to the document record.
class EnterpriseDocumentPdfService {
  static const _finalLayoutInk = KajFinalPdfLayout.ink;

  static const String _brandToken = 'KHAT AL-JAWDA ERP';
  const EnterpriseDocumentPdfService();

  Future<Uint8List> build({
    required bool purchase,
    required String language,
    required Map<String, Object?> order,
    required List<Map<String, Object?>> items,
    required List<Map<String, Object?>> logistics,
    required List<Map<String, Object?>> invoices,
    required List<Map<String, Object?>> payments,
    required List<Map<String, Object?>> movements,
    required List<Map<String, Object?>> journalEntries,
    required List<Map<String, Object?>> auditTrail,
    List<Map<String, Object?>> reconciliation = const [],
  }) async {
    language = PdfTextSupport.canonicalPdfLanguage(language);
    final arabic = language == 'ar';
    // PdfGoogleFonts.notoNaskhArabicRegular is cached by PdfTextSupport.
    late final PdfFontPack fonts;
    try {
      fonts = await PdfTextSupport.loadFonts();
    } catch (error) {
      throw StateError(
        'تعذر تحميل الخط العربي اللازم لإنشاء ملف PDF. '
        'تم إيقاف التصدير لمنع ظهور رموز بدل الأحرف العربية: $error',
      );
    }
    final regular = fonts.regular;
    final bold = fonts.bold;
    final direction = arabic ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final branding = await _loadBranding(language);
    // KAJ brandbook palette: Pitch Black, neutral grays and Electric Blue.
    final primary = _finalLayoutInk;
    final secondary = PdfColor.fromHex('#6D6E71');
    final border = PdfColor.fromHex('#C8C8CA');
    final surface = PdfColor.fromHex('#F5F6F6');
    final accent = PremiumDocumentTheme.accent;
    final accentSoft = PremiumDocumentTheme.accentSoft;
    final documentNumber =
        (order['orderNumber'] ?? order['invoiceNumber'] ?? '-').toString();
    final printableItems = _flattenRows(items);
    final printableLogistics = _flattenRows(logistics);
    final printableInvoices = _flattenRows(invoices);
    final printablePayments = _flattenRows(payments);
    final printableMovements = _flattenRows(movements);
    final printableJournalEntries = _flattenRows(journalEntries);
    final printableAuditTrail = _flattenRows(auditTrail);
    final printableReconciliation = _flattenRows(reconciliation);
    final document = pw.Document(
      title: '${purchase ? 'Purchase' : 'Sales'} $documentNumber',
      author: _brandToken,
      subject: purchase
          ? 'Purchase document package'
          : 'Sales document package',
      creator: '$_brandToken ${AppReleaseInfo.displayVersion}',
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    pw.Widget labelValue(String label, Object? value) => pw.Container(
      padding: EnterpriseDocumentPresentation.fieldPadding,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: border, width: .5),
        color: PdfColors.white,
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            flex: 2,
            child: PdfTextSupport.text(
              _t(label, language),
              style: pw.TextStyle(
                font: bold,
                fontSize: EnterpriseDocumentPresentation.bodySize,
                color: secondary,
              ),
            ),
          ),
          pw.SizedBox(width: 5),
          pw.Expanded(
            flex: 3,
            child: PdfTextSupport.text(
              _value(value, language),
              style: const pw.TextStyle(
                fontSize: EnterpriseDocumentPresentation.bodySize,
              ),
            ),
          ),
        ],
      ),
    );

    List<pw.Widget> section(
      String title,
      List<Map<String, Object?>> rows, {
      required String kind,
    }) {
      if (rows.isEmpty) return const <pw.Widget>[];
      final normalizedRows = _normalizeTableRows(
        kind,
        rows,
        purchase: purchase,
      );
      final keys = _tableFields(kind, purchase: purchase);
      final columnGroups = _columnGroups(keys);
      const rowsPerPage = 11;
      final rowChunks = <List<Map<String, Object?>>>[];
      for (
        var offset = 0;
        offset < normalizedRows.length;
        offset += rowsPerPage
      ) {
        final end = (offset + rowsPerPage)
            .clamp(0, normalizedRows.length)
            .toInt();
        rowChunks.add(normalizedRows.sublist(offset, end));
      }

      pw.Widget tableFor(
        List<String> groupKeys,
        List<Map<String, Object?>> chunk,
      ) {
        final widths = _tableColumnWidths(kind, groupKeys);
        return pw.Table(
          border: pw.TableBorder(
            horizontalInside: pw.BorderSide(color: border, width: .35),
            verticalInside: pw.BorderSide(color: border, width: .25),
            left: pw.BorderSide(color: border, width: .5),
            right: pw.BorderSide(color: border, width: .5),
            top: pw.BorderSide(color: border, width: .5),
            bottom: pw.BorderSide(color: border, width: .5),
          ),
          columnWidths: widths,
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: secondary),
              children: [
                for (final key in groupKeys)
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 6,
                    ),
                    alignment: pw.Alignment.center,
                    child: PdfTextSupport.text(
                      _field(key, language),
                      textAlign: pw.TextAlign.center,
                      maxLines: 2,
                      style: pw.TextStyle(
                        font: bold,
                        color: PdfColors.white,
                        fontSize:
                            EnterpriseDocumentPresentation.tableHeaderSize,
                      ),
                    ),
                  ),
              ],
            ),
            for (var rowIndex = 0; rowIndex < chunk.length; rowIndex++)
              pw.TableRow(
                decoration: pw.BoxDecoration(
                  color: rowIndex.isOdd ? surface : PdfColors.white,
                ),
                children: [
                  for (final key in groupKeys)
                    pw.Container(
                      constraints: const pw.BoxConstraints(minHeight: 24),
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 5,
                      ),
                      alignment: _numericTableFields.contains(key)
                          ? pw.Alignment.center
                          : (arabic
                                ? pw.Alignment.centerRight
                                : pw.Alignment.centerLeft),
                      child: PdfTextSupport.text(
                        _tableValue(
                          key,
                          chunk[rowIndex][key],
                          chunk[rowIndex],
                          language,
                        ),
                        textAlign: _numericTableFields.contains(key)
                            ? pw.TextAlign.center
                            : (arabic ? pw.TextAlign.right : pw.TextAlign.left),
                        maxLines: key == 'description' ? 3 : 2,
                        style: pw.TextStyle(
                          font: _emphasizedTableFields.contains(key)
                              ? bold
                              : regular,
                          fontSize: 6.7,
                          color: key == 'lineTotal' || key == 'total'
                              ? primary
                              : secondary,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        );
      }

      final widgets = <pw.Widget>[];
      var emittedTable = false;
      for (var groupIndex = 0; groupIndex < columnGroups.length; groupIndex++) {
        for (var chunkIndex = 0; chunkIndex < rowChunks.length; chunkIndex++) {
          if (emittedTable) widgets.add(pw.NewPage());
          emittedTable = true;
          widgets.addAll([
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 7,
              ),
              decoration: pw.BoxDecoration(
                color: primary,
                border: pw.Border(
                  bottom: pw.BorderSide(color: accent, width: 2.4),
                ),
              ),
              child: pw.Row(
                children: [
                  pw.Container(width: 4, height: 14, color: accent),
                  pw.SizedBox(width: 7),
                  pw.Expanded(
                    child: PdfTextSupport.text(
                      title,
                      style: pw.TextStyle(
                        font: bold,
                        fontSize: 10.5,
                        color: PdfColors.white,
                      ),
                    ),
                  ),
                  PdfTextSupport.text(
                    '${normalizedRows.length} ${_t('records', language)}',
                    style: const pw.TextStyle(
                      fontSize: 7,
                      color: PdfColors.white,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 5),
            if (columnGroups.length > 1 || rowChunks.length > 1)
              pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 4),
                alignment: arabic
                    ? pw.Alignment.centerRight
                    : pw.Alignment.centerLeft,
                child: PdfTextSupport.text(
                  '${_t('Columns', language)} ${groupIndex + 1}/${columnGroups.length} - '
                  '${arabic ? 'صفحة البيانات' : 'Data page'} ${chunkIndex + 1}/${rowChunks.length}',
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: 7,
                    color: secondary,
                  ),
                ),
              ),
            tableFor(columnGroups[groupIndex], rowChunks[chunkIndex]),
            pw.SizedBox(height: 12),
          ]);
        }
      }
      return widgets;
    }

    pw.Widget signatures() => pw.Column(
      children: [
        pw.SizedBox(height: 14),
        pw.Divider(color: border),
        pw.SizedBox(height: 8),
        pw.Row(
          children: [
            for (final title in [
              _t('Prepared by', language),
              _t('Reviewed by', language),
              _t('Approval signature', language),
              purchase
                  ? _t('Supplier signature', language)
                  : _t('Customer signature', language),
            ])
              pw.Expanded(
                child: pw.Container(
                  height: 54,
                  margin: const pw.EdgeInsets.symmetric(horizontal: 3),
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: border, width: .6),
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(3),
                    ),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      PdfTextSupport.text(
                        title,
                        style: pw.TextStyle(font: bold, fontSize: 8),
                      ),
                      pw.Spacer(),
                      pw.Divider(color: accent, thickness: .5),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );

    final summaryFields = <(String, Object?)>[
      ('Document number', documentNumber),
      ('Business partner', order['partnerName']),
      ('Status', order['status']),
      ('Currency', order['currency']),
      ('Subtotal', order['subtotal']),
      ('Discount', order['discount']),
      ('Total', order['total']),
      ('Created at', order['createdAt']),
      ('Last updated', order['updatedAt']),
      ('Created by', order['createdByName'] ?? order['createdBy']),
      ('Approved by', order['approvedByName'] ?? order['approvedBy']),
      ('Notes', order['notes']),
      ...order.entries
          .where(
            (entry) =>
                !_isTechnicalField(entry.key) &&
                !const {
                  'orderNumber',
                  'partnerName',
                  'status',
                  'currency',
                  'subtotal',
                  'discount',
                  'total',
                  'createdAt',
                  'updatedAt',
                  'createdByName',
                  'createdBy',
                  'approvedByName',
                  'approvedBy',
                  'notes',
                }.contains(entry.key),
          )
          .map(
            (entry) =>
                (_fieldNames[entry.key] ?? _humanize(entry.key), entry.value),
          ),
    ];

    pw.Widget pageHeader(
      pw.Context context,
      String sectionTitle,
    ) => pw.Container(
      height: 72,
      margin: const pw.EdgeInsets.only(bottom: 12),
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: pw.BoxDecoration(
        color: primary,
        border: pw.Border(bottom: pw.BorderSide(color: accent, width: 3)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            width: 115,
            height: 46,
            alignment: pw.Alignment.center,
            child: branding.logo == null
                ? PdfTextSupport.text(
                    'KAJ',
                    style: pw.TextStyle(
                      font: bold,
                      color: PdfColors.white,
                      fontSize: 20,
                    ),
                  )
                : pw.Image(branding.logo!, fit: pw.BoxFit.contain),
          ),
          pw.Container(
            width: 1,
            height: 38,
            margin: const pw.EdgeInsets.symmetric(horizontal: 13),
            color: accent,
          ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                PdfTextSupport.text(
                  branding.companyName,
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: 14,
                    color: PdfColors.white,
                  ),
                ),
                pw.SizedBox(height: 3),
                PdfTextSupport.text(
                  [
                    branding.address,
                    branding.phone,
                    branding.taxNumber,
                  ].where((value) => value.trim().isNotEmpty).join('  |  '),
                  style: pw.TextStyle(fontSize: 7.5, color: PdfColors.white),
                ),
              ],
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                PdfTextSupport.text(
                  sectionTitle,
                  style: pw.TextStyle(font: bold, fontSize: 9, color: primary),
                ),
                pw.SizedBox(height: 2),
                PdfTextSupport.text(
                  documentNumber,
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: 8,
                    color: secondary,
                  ),
                ),
                PdfTextSupport.text(
                  '${_t('Page', language)} ${context.pageNumber}',
                  style: pw.TextStyle(fontSize: 6.5, color: secondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    pw.Widget pageFooter(pw.Context context) => pw.Column(
      children: [
        pw.Container(height: 2, color: accent),
        pw.SizedBox(height: 5),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            PdfTextSupport.text(
              _t('Generated electronically by Khat Al-Jawda ERP', language),
              style: pw.TextStyle(fontSize: 6.8, color: secondary),
            ),
            PdfTextSupport.text(
              '${context.pageNumber} / ${context.pagesCount}',
              style: pw.TextStyle(font: bold, fontSize: 7, color: primary),
            ),
          ],
        ),
      ],
    );

    pw.Widget pageTitle(String title, String subtitle) => pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border(
          left: pw.BorderSide(color: accent, width: 5),
          bottom: pw.BorderSide(color: border, width: .5),
        ),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                PdfTextSupport.text(
                  title,
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: EnterpriseDocumentPresentation.titleSize,
                    color: primary,
                  ),
                ),
                pw.SizedBox(height: 3),
                PdfTextSupport.text(
                  subtitle,
                  style: pw.TextStyle(fontSize: 8.5, color: secondary),
                ),
              ],
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: pw.BoxDecoration(
              color: accentSoft,
              border: pw.Border.all(color: accent, width: .8),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
            ),
            child: PdfTextSupport.text(
              _value(order['status'], language),
              style: pw.TextStyle(font: bold, fontSize: 8.5, color: primary),
            ),
          ),
        ],
      ),
    );

    pw.Widget totalsPanel() {
      final rows = <(String, Object?)>[
        ('Subtotal', order['subtotal']),
        ('Discount', order['discount']),
        ('Total', order['total']),
      ].where((entry) => entry.$2 != null).toList();
      if (rows.isEmpty) return pw.SizedBox();
      return pw.Align(
        alignment: arabic ? pw.Alignment.centerLeft : pw.Alignment.centerRight,
        child: pw.Container(
          width: 285,
          margin: const pw.EdgeInsets.only(top: 4, bottom: 8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: border, width: .6),
          ),
          child: pw.Column(
            children: [
              for (var index = 0; index < rows.length; index++)
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: pw.BoxDecoration(
                    color: index == rows.length - 1 ? primary : PdfColors.white,
                    border: index == 0
                        ? null
                        : pw.Border(
                            top: pw.BorderSide(color: border, width: .4),
                          ),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      PdfTextSupport.text(
                        _t(rows[index].$1, language),
                        style: pw.TextStyle(
                          font: bold,
                          fontSize: index == rows.length - 1 ? 9 : 8,
                          color: index == rows.length - 1
                              ? PdfColors.white
                              : secondary,
                        ),
                      ),
                      PdfTextSupport.text(
                        _moneyWithCurrency(
                          rows[index].$2,
                          order['currency'],
                          language,
                        ),
                        style: pw.TextStyle(
                          font: bold,
                          fontSize: index == rows.length - 1 ? 10 : 8.5,
                          color: index == rows.length - 1 ? accent : primary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    }

    pw.MultiPage packagePage({
      required String title,
      required String subtitle,
      required List<pw.Widget> content,
    }) => pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: EnterpriseDocumentPresentation.landscapePageFormat,
        margin: EnterpriseDocumentPresentation.pageMargin,
        textDirection: direction,
        buildBackground: (_) => _brandBackground(accentSoft, border),
      ),
      header: (context) => pageHeader(context, title),
      footer: pageFooter,
      build: (_) => [pageTitle(title, subtitle), ...content],
    );

    document.addPage(
      packagePage(
        title: purchase
            ? _t('Purchase order', language)
            : _t('Sales order', language),
        subtitle: _t('Order page', language),
        content: [
          pw.Wrap(
            spacing: 0,
            runSpacing: 0,
            children: summaryFields
                .where(
                  (entry) =>
                      entry.$2 != null && entry.$2.toString().trim().isNotEmpty,
                )
                .map(
                  (entry) => pw.SizedBox(
                    width: 365,
                    child: labelValue(entry.$1, entry.$2),
                  ),
                )
                .toList(),
          ),
          pw.SizedBox(height: 13),
          ...section(
            _t('Unified products and vehicles table', language),
            printableItems,
            kind: 'items',
          ),
          ...section(
            _t('Workflow quantity reconciliation', language),
            printableReconciliation,
            kind: 'reconciliation',
          ),
          totalsPanel(),
          signatures(),
        ],
      ),
    );

    document.addPage(
      packagePage(
        title: _t('Warehouse page', language),
        subtitle: purchase
            ? _t('Purchase receipts and inventory movements', language)
            : _t('Sales deliveries and inventory movements', language),
        content: [
          ...section(
            purchase
                ? _t('Purchase receipts', language)
                : _t('Sales deliveries', language),
            printableLogistics,
            kind: 'logistics',
          ),
          ...section(
            _t('Inventory movements', language),
            printableMovements,
            kind: 'movements',
          ),
        ],
      ),
    );

    document.addPage(
      packagePage(
        title: _t('Invoice page', language),
        subtitle: _t('Invoices linked to this order', language),
        content: [
          ...section(
            _t('Invoices', language),
            printableInvoices,
            kind: 'invoices',
          ),
        ],
      ),
    );

    document.addPage(
      packagePage(
        title: _t('Financial payments page', language),
        subtitle: _t('Payments, accounting entries and audit trail', language),
        content: [
          ...section(
            _t('Payments', language),
            printablePayments,
            kind: 'payments',
          ),
          ...section(
            _t('Journal entries', language),
            printableJournalEntries,
            kind: 'journal',
          ),
          ...section(
            _t('Audit trail', language),
            printableAuditTrail,
            kind: 'audit',
          ),
        ],
      ),
    );
    return document.save();
  }

  Future<void> printDocument({
    required bool purchase,
    required String language,
    required Map<String, Object?> order,
    required List<Map<String, Object?>> items,
    required List<Map<String, Object?>> logistics,
    required List<Map<String, Object?>> invoices,
    required List<Map<String, Object?>> payments,
    required List<Map<String, Object?>> movements,
    required List<Map<String, Object?>> journalEntries,
    required List<Map<String, Object?>> auditTrail,
    List<Map<String, Object?>> reconciliation = const [],
  }) async {
    final bytes = await build(
      purchase: purchase,
      language: language,
      order: order,
      items: items,
      logistics: logistics,
      invoices: invoices,
      payments: payments,
      movements: movements,
      journalEntries: journalEntries,
      auditTrail: auditTrail,
      reconciliation: reconciliation,
    );
    await PdfPrintService.print(
      fileName:
          '${purchase ? 'purchase' : 'sales'}_${order['orderNumber'] ?? 'document'}.pdf',
      bytes: bytes,
    );
  }

  Future<_PdfBranding> _loadBranding(String language) async {
    Map<String, dynamic> row = <String, dynamic>{};
    try {
      row = await CloudFeatureCommand.instance.map(
        'company_settings',
        'branding',
      );
    } catch (error, stackTrace) {
      // Branding is optional. A missing phase-26 RPC must never prevent an
      // order from being exported or printed.
      AppLogger.debug('PDF branding fallback used: $error\n$stackTrace');
    }
    final values = <String, String>{
      for (final entry in row.entries) entry.key: entry.value?.toString() ?? '',
    };
    pw.MemoryImage? logo;
    if (kIsWeb) {
      // Browser PDF generation must not depend on AssetManifest.json. The
      // document remains valid without a bundled logo.
      logo = null;
    } else {
      try {
        final data = await rootBundle.load(
          'assets/images/khat_al_jawda_logo.jpg',
        );
        logo = pw.MemoryImage(data.buffer.asUint8List());
      } catch (primaryError, primaryStackTrace) {
        AppLogger.debug(
          'Primary PDF logo could not be loaded: '
          '$primaryError\n$primaryStackTrace',
        );
        try {
          final data = await rootBundle.load('assets/images/logo.png');
          logo = pw.MemoryImage(data.buffer.asUint8List());
        } catch (fallbackError, fallbackStackTrace) {
          AppLogger.debug(
            'Fallback PDF logo could not be loaded: '
            '$fallbackError\n$fallbackStackTrace',
          );
        }
      }
    }
    final arabic = language == 'ar';
    return _PdfBranding(
      companyName: arabic
          ? (values['company_name']?.trim().isNotEmpty == true
                ? values['company_name']!
                : 'شركة خط الجودة')
          : (values['company_name_en']?.trim().isNotEmpty == true
                ? values['company_name_en']!
                : 'Quality Line'),
      address: values['company_address'] ?? '',
      phone: values['company_phone'] ?? '',
      taxNumber: values['company_tax_number'] ?? '',
      logo: logo,
    );
  }

  pw.Widget _brandBackground(PdfColor accentSoft, PdfColor border) =>
      pw.FullPage(
        ignoreMargins: true,
        child: pw.Stack(
          children: [
            pw.Positioned(
              right: -28,
              top: 88,
              child: pw.Transform.rotate(
                angle: .78,
                child: pw.Container(
                  width: 150,
                  height: 150,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: accentSoft, width: 7),
                  ),
                ),
              ),
            ),
            pw.Positioned(
              right: 28,
              top: 145,
              child: pw.Transform.rotate(
                angle: .78,
                child: pw.Container(
                  width: 92,
                  height: 92,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: border, width: .7),
                  ),
                ),
              ),
            ),
            pw.Positioned(
              left: -45,
              bottom: -70,
              child: pw.Transform.rotate(
                angle: .78,
                child: pw.Container(
                  width: 175,
                  height: 175,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: accentSoft, width: 5),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  List<String> _tableFields(String kind, {required bool purchase}) =>
      switch (kind) {
        'items' => [
          'itemType',
          'description',
          'brandModel',
          'reference',
          'quantity',
          'unitAmount',
          'lineTotal',
          'warehouseName',
          'status',
        ],
        'logistics' => [
          'documentNumber',
          'movementDate',
          'warehouseName',
          'movementType',
          'description',
          'quantity',
          'status',
        ],
        'movements' => [
          'movementNumber',
          'movementDate',
          'warehouseName',
          'movementType',
          'description',
          'quantity',
          'status',
        ],
        'invoices' => [
          'invoiceNumber',
          'invoiceDate',
          'currency',
          'total',
          'paidAmount',
          'remainingAmount',
          'paymentStatus',
        ],
        'payments' => [
          'paymentDate',
          'cashAccountName',
          'paymentCurrency',
          'cashAmount',
          'settlementMode',
          'status',
        ],
        'journal' => [
          'entryNumber',
          'entryDate',
          'description',
          'totalDebit',
          'totalCredit',
          'status',
        ],
        'audit' => [
          'performedAt',
          'performedBy',
          'action',
          'description',
          'status',
        ],
        'reconciliation' => [
          'description',
          'orderedQuantity',
          'operationalQuantity',
          'invoicedQuantity',
          'remainingOperational',
          'remainingInvoice',
          'status',
        ],
        _ => _preferredSectionFields.take(7).toList(),
      };

  List<List<String>> _columnGroups(
    List<String> keys, {
    int maximumColumns = 9,
  }) {
    if (keys.isEmpty) return const <List<String>>[];
    if (keys.length <= maximumColumns) {
      return <List<String>>[List<String>.unmodifiable(keys)];
    }

    final anchorKeys = <String>[
      for (final key in const ['description', 'documentNumber', 'entryNumber'])
        if (keys.contains(key)) key,
    ];
    final detailKeys = keys.where((key) => !anchorKeys.contains(key)).toList();
    final detailCapacity = (maximumColumns - anchorKeys.length)
        .clamp(1, 9)
        .toInt();
    final groups = <List<String>>[];
    for (var offset = 0; offset < detailKeys.length; offset += detailCapacity) {
      final end = (offset + detailCapacity).clamp(0, detailKeys.length).toInt();
      groups.add(<String>[...anchorKeys, ...detailKeys.sublist(offset, end)]);
    }
    return groups;
  }

  Map<int, pw.TableColumnWidth> _tableColumnWidths(
    String kind,
    List<String> keys,
  ) {
    final weights = <String, double>{
      'itemType': .8,
      'description': 2.3,
      'brandModel': 1.35,
      'reference': 1.25,
      'quantity': .65,
      'unitAmount': .9,
      'lineTotal': .95,
      'warehouseName': 1.1,
      'status': .85,
      'documentNumber': 1.0,
      'movementNumber': 1.0,
      'movementDate': 1.0,
      'movementType': 1.0,
      'invoiceNumber': 1.0,
      'invoiceDate': 1.0,
      'currency': .65,
      'total': .9,
      'paidAmount': .9,
      'remainingAmount': 1.0,
      'paymentStatus': .9,
      'paymentDate': 1.0,
      'cashAccountName': 1.4,
      'paymentCurrency': .8,
      'cashAmount': .9,
      'settlementMode': 1.1,
      'entryNumber': 1.0,
      'entryDate': 1.0,
      'totalDebit': .9,
      'totalCredit': .9,
      'performedAt': 1.1,
      'performedBy': 1.2,
      'action': 1.0,
    };
    return {
      for (var index = 0; index < keys.length; index++)
        index: pw.FlexColumnWidth(weights[keys[index]] ?? 1),
    };
  }

  List<Map<String, Object?>> _normalizeTableRows(
    String kind,
    List<Map<String, Object?>> rows, {
    required bool purchase,
  }) => rows
      .map((row) {
        final normalized = Map<String, Object?>.from(row);
        Object? first(List<String> aliases) {
          for (final alias in aliases) {
            final value = row[alias];
            if (value != null && value.toString().trim().isNotEmpty)
              return value;
          }
          return null;
        }

        if (kind == 'items') {
          final brand = first([
            'detail_brand',
            'brand',
            'vehicleBrand',
            'productBrand',
          ]);
          final model = first([
            'detail_model',
            'model',
            'vehicleModel',
            'productModel',
          ]);
          normalized['brandModel'] = [brand, model]
              .where(
                (value) => value != null && value.toString().trim().isNotEmpty,
              )
              .join(' / ');
          normalized['reference'] = first([
            'detail_chassis',
            'chassisNumber',
            'vin',
            'detail_code',
            'sku',
            'code',
          ]);
          normalized['unitAmount'] = purchase
              ? first(['unitCost', 'cost', 'purchasePrice', 'unitPrice'])
              : first(['unitPrice', 'salePrice', 'price', 'unitCost']);
          normalized['description'] = first([
            'description',
            'detail_name',
            'productName',
            'vehicleName',
            'name',
          ]);
          normalized['itemType'] = first(['itemType', 'type', 'catalogType']);
          normalized['warehouseName'] = first([
            'warehouseName',
            'warehouse_name',
            'locationName',
          ]);
        }
        normalized['documentNumber'] = first([
          'documentNumber',
          'receiptNumber',
          'deliveryNumber',
          'orderNumber',
        ]);
        normalized['movementDate'] = first([
          'movementDate',
          'receiptDate',
          'deliveryDate',
          'createdAt',
        ]);
        normalized['invoiceDate'] = first([
          'invoiceDate',
          'issuedAt',
          'createdAt',
        ]);
        normalized['description'] ??= first(['notes', 'memo', 'details']);
        normalized['status'] ??= first([
          'paymentStatus',
          'movementStatus',
          'state',
        ]);
        return normalized;
      })
      .toList(growable: false);

  static const _numericTableFields = <String>{
    'quantity',
    'unitAmount',
    'lineTotal',
    'total',
    'paidAmount',
    'remainingAmount',
    'cashAmount',
    'totalDebit',
    'totalCredit',
    'orderedQuantity',
    'operationalQuantity',
    'invoicedQuantity',
    'remainingOperational',
    'remainingInvoice',
  };

  static const _monetaryTableFields = <String>{
    'unitAmount',
    'lineTotal',
    'total',
    'paidAmount',
    'remainingAmount',
    'cashAmount',
    'totalDebit',
    'totalCredit',
  };

  static const _emphasizedTableFields = <String>{
    'lineTotal',
    'total',
    'remainingAmount',
    'cashAmount',
  };

  List<Map<String, Object?>> _flattenRows(List<Map<String, Object?>> rows) =>
      rows.map(_flattenRow).toList(growable: false);

  Map<String, Object?> _flattenRow(Map<String, Object?> row) {
    final result = <String, Object?>{};
    void addValue(String key, Object? value) {
      if (value is String &&
          (key.toLowerCase().contains('rawdata') ||
              key.toLowerCase().contains('payload') ||
              key.toLowerCase().contains('details'))) {
        final trimmed = value.trim();
        if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
            (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
          try {
            addValue(key, jsonDecode(trimmed));
            return;
          } catch (_) {
            // Keep malformed or legacy payloads printable as their raw text.
          }
        }
      }
      if (value is Map) {
        for (final entry in value.entries) {
          addValue('${key}_${entry.key}', entry.value);
        }
      } else if (value is List) {
        result[key] = jsonEncode(value);
      } else {
        result[key] = value;
      }
    }

    for (final entry in row.entries) {
      addValue(entry.key, entry.value);
    }
    return result;
  }

  String _tableValue(
    String key,
    Object? value,
    Map<String, Object?> row,
    String language,
  ) {
    final numeric = _asNumber(value);
    if (numeric == null) return _value(value, language);
    if (key == 'quantity') return MoneyFormatter.quantity(numeric);
    if (_monetaryTableFields.contains(key)) {
      final currency = _rowCurrency(row);
      return MoneyFormatter.format(numeric, currency: currency);
    }
    return MoneyFormatter.quantity(numeric);
  }

  String _moneyWithCurrency(
    Object? value,
    Object? currencyValue,
    String language,
  ) {
    final currency = currencyValue?.toString().trim().toUpperCase() ?? '';
    final numeric = _asNumber(value);
    if (numeric == null) {
      return '${_value(value, language)} ${_value(currencyValue, language)}'
          .trim();
    }
    return MoneyFormatter.withCurrency(numeric, currency);
  }

  num? _asNumber(Object? value) {
    if (value is num) return value;
    if (value == null) return null;
    final normalized = value.toString().replaceAll(',', '').trim();
    return num.tryParse(normalized);
  }

  String? _rowCurrency(Map<String, Object?> row) {
    for (final key in const [
      'currency',
      'paymentCurrency',
      'invoiceCurrency',
      'cashCurrency',
    ]) {
      final value = row[key]?.toString().trim().toUpperCase();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  String _value(Object? value, String language) {
    if (value == null) return '-';
    final text = value is Map || value is List
        ? jsonEncode(value)
        : value.toString();
    return PdfTextSupport.sanitize(
      DomainTranslationCatalog.translate(text, language),
    );
  }

  String _field(String key, String language) =>
      _t(_fieldNames[key] ?? _humanize(key), language);

  String _humanize(String value) => value
      .replaceFirst(RegExp(r'^detail_'), '')
      .replaceAllMapped(
        RegExp(r'([a-z])([A-Z])'),
        (match) => '${match[1]} ${match[2]}',
      )
      .replaceAll('_', ' ')
      .trim();

  static bool _isTechnicalField(String key) {
    final normalized = key
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
        .toLowerCase();
    if (normalized == 'paymentkey' || normalized == 'id') return true;
    return normalized.endsWith('id') ||
        normalized.contains('uuid') ||
        normalized.contains('payload') ||
        normalized.contains('rawdata') ||
        normalized.contains('verification');
  }

  static const _preferredSectionFields = <String>[
    'description',
    'itemType',
    'quantity',
    'unitCost',
    'unitPrice',
    'lineTotal',
    'detail_brand',
    'detail_model',
    'detail_year',
    'detail_chassis',
    'detail_code',
    'detail_name',
    'warehouseName',
    'status',
    'invoiceNumber',
    'total',
    'paidAmount',
    'remainingAmount',
    'cashAccountName',
    'cashAmount',
    'paymentCurrency',
    'paymentDate',
    'movementNumber',
    'productName',
    'movementType',
    'entryNumber',
    'entryDate',
    'totalDebit',
    'totalCredit',
    'documentNumber',
    'action',
    'performedBy',
    'performedAt',
  ];

  static const _fieldNames = <String, String>{
    'orderNumber': 'Order number',
    'invoiceNumber': 'Invoice number',
    'receiptNumber': 'Receipt number',
    'deliveryNumber': 'Delivery number',
    'status': 'Status',
    'currency': 'Currency',
    'exchangeRate': 'Exchange rate',
    'total': 'Total',
    'subtotal': 'Subtotal',
    'discount': 'Discount',
    'partnerName': 'Business partner',
    'description': 'Description',
    'quantity': 'Quantity',
    'unitPrice': 'Unit price',
    'unitCost': 'Unit cost',
    'lineTotal': 'Line total',
    'brandModel': 'Brand / model',
    'reference': 'Reference',
    'unitAmount': 'Unit amount',
    'invoiceDate': 'Invoice date',
    'paymentDate': 'Payment date',
    'paymentCurrency': 'Payment currency',
    'invoiceAmount': 'Invoice amount',
    'cashAmount': 'Cash amount',
    'settlementMode': 'Settlement mode',
    'settlementAccountId': 'Settlement account',
    'exchangeDifference': 'Exchange difference',
    'expectedCashAmount': 'Expected cash amount',
    'movementDate': 'Movement date',
    'movementType': 'Movement type',
    'entryDate': 'Entry date',
    'performedAt': 'Performed at',
    'performedBy': 'Performed by',
    'warehouseName': 'Warehouse',
    'cashAccountName': 'Cash account',
    'paymentStatus': 'Payment status',
    'remainingAmount': 'Remaining amount',
    'paidAmount': 'Paid amount',
    'referenceType': 'Reference type',
    'createdBy': 'Created by',
    'updatedAt': 'Last updated',
    'orderedQuantity': 'Ordered quantity',
    'operationalQuantity': 'Prepared / received quantity',
    'invoicedQuantity': 'Invoiced quantity',
    'remainingOperational': 'Remaining operational quantity',
    'remainingInvoice': 'Remaining invoice quantity',
  };

  String _t(String english, String language) {
    if (language != 'ar') return english;
    return const <String, String>{
          'Purchase order': 'أمر شراء',
          'Sales order': 'أمر بيع',
          'Official business document': 'مستند أعمال رسمي',
          'Generated electronically by Quality Line ERP':
              'تم إنشاء المستند إلكترونيًا بواسطة نظام خط الجودة',
          'Generated electronically by Khat Al-Jawda ERP':
              'تم إنشاء المستند إلكترونيًا بواسطة نظام خط الجودة',
          'Page': 'الصفحة',
          'Items': 'البنود',
          'records': 'سجل',
          'Columns': 'مجموعة الأعمدة',
          'Brand / model': 'العلامة / الطراز',
          'Reference': 'المرجع',
          'Unit amount': 'سعر الوحدة',
          'Invoice date': 'تاريخ الفاتورة',
          'Purchase receipts': 'استلامات الشراء',
          'Sales deliveries': 'تجهيزات البيع',
          'Invoices': 'الفواتير',
          'Payments': 'الدفعات',
          'Inventory movements': 'الحركات المخزنية',
          'Journal entries': 'القيود المحاسبية',
          'Audit trail': 'سجل التدقيق',
          'Order page': 'صفحة الأمر',
          'Warehouse page': 'صفحة المخزن',
          'Invoice page': 'صفحة الفوترة',
          'Financial payments page': 'صفحة الدفعات المالية',
          'Unified products and vehicles table': 'جدول موحد للمنتجات والسيارات',
          'Workflow quantity reconciliation': 'مطابقة كميات سير العمل',
          'Purchase receipts and inventory movements':
              'استلامات الشراء والحركات المخزنية',
          'Sales deliveries and inventory movements':
              'تجهيزات البيع والحركات المخزنية',
          'Invoices linked to this order': 'الفواتير المرتبطة بهذا الأمر',
          'Payments, accounting entries and audit trail':
              'الدفعات والقيود المحاسبية وسجل التدقيق',
          'Prepared by': 'إعداد',
          'Reviewed by': 'مراجعة',
          'Approval signature': 'اعتماد',
          'Supplier signature': 'توقيع المورد',
          'Customer signature': 'توقيع العميل',
          'Document number': 'رقم المستند',
          'Order number': 'رقم الأمر',
          'Invoice number': 'رقم الفاتورة',
          'Receipt number': 'رقم الاستلام',
          'Delivery number': 'رقم التجهيز',
          'Status': 'الحالة',
          'Currency': 'العملة',
          'Exchange rate': 'سعر الصرف',
          'Total': 'الإجمالي',
          'Subtotal': 'المجموع الفرعي',
          'Discount': 'الخصم',
          'Business partner': 'شريك الأعمال',
          'Description': 'الوصف',
          'Quantity': 'الكمية',
          'Ordered quantity': 'الكمية المطلوبة',
          'Prepared / received quantity': 'الكمية المجهزة / المستلمة',
          'Invoiced quantity': 'الكمية المفوترة',
          'Remaining operational quantity': 'الكمية التشغيلية المتبقية',
          'Remaining invoice quantity': 'الكمية المتبقية للفوترة',
          'Unit price': 'سعر الوحدة',
          'Unit cost': 'كلفة الوحدة',
          'Line total': 'إجمالي البند',
          'Payment date': 'تاريخ الدفعة',
          'Payment currency': 'عملة الدفع',
          'Invoice amount': 'المبلغ بعملة الفاتورة',
          'Cash amount': 'المبلغ بعملة الصندوق',
          'Settlement mode': 'نوع التسوية',
          'Settlement account': 'حساب التسوية',
          'Exchange difference': 'فرق الصرف',
          'Expected cash amount': 'مبلغ الصندوق المتوقع',
          'Movement date': 'تاريخ الحركة',
          'Movement type': 'نوع الحركة',
          'Entry date': 'تاريخ القيد',
          'Performed at': 'وقت التنفيذ',
          'Performed by': 'المنفذ',
          'Warehouse': 'المخزن',
          'Cash account': 'الصندوق',
          'Payment status': 'حالة الدفع',
          'Remaining amount': 'المبلغ المتبقي',
          'Paid amount': 'المبلغ المدفوع',
          'Reference type': 'نوع المرجع',
          'Created at': 'تاريخ الإنشاء',
          'Last updated': 'آخر تحديث',
          'Created by': 'أنشأ بواسطة',
          'Approved by': 'صُدّق بواسطة',
          'Notes': 'الملاحظات',
          'Action': 'الإجراء',
          'Address': 'العنوان',
          'Amount': 'المبلغ',
          'Amount IQD': 'المبلغ بالدينار',
          'Amount USD': 'المبلغ بالدولار',
          'Available quantity': 'الكمية المتاحة',
          'Average unit cost': 'متوسط كلفة الوحدة',
          'Brand': 'الماركة',
          'Category': 'الفئة',
          'Chassis': 'رقم الهيكل',
          'Color': 'اللون',
          'Customer': 'العميل',
          'Document ID': 'معرف المستند',
          'Document type': 'نوع المستند',
          'Email': 'البريد الإلكتروني',
          'Entry number': 'رقم القيد',
          'Expected incoming': 'الوارد المتوقع',
          'Expected outgoing': 'الصادر المتوقع',
          'From status': 'الحالة السابقة',
          'From warehouse': 'مخزن المصدر',
          'Item details': 'تفاصيل البند',
          'Item type': 'نوع البند',
          'Maintenance cost': 'كلفة الصيانة',
          'Model': 'الموديل',
          'Module': 'الوحدة',
          'Movement number': 'رقم الحركة',
          'Name': 'الاسم',
          'Parent ID': 'معرف المستند الأصل',
          'Party': 'الطرف',
          'Payload': 'البيانات التفصيلية',
          'Payment ID': 'معرف الدفعة',
          'Phone': 'الهاتف',
          'Plate number': 'رقم اللوحة',
          'Product': 'المنتج',
          'Product name': 'اسم المنتج',
          'Purchase price': 'سعر الشراء',
          'Raw data': 'البيانات الخام',
          'Reason': 'السبب',
          'Reserved quantity': 'الكمية المحجوزة',
          'Sale price': 'سعر البيع',
          'Stock value': 'قيمة المخزون',
          'Supplier': 'المورد',
          'Tax number': 'الرقم الضريبي',
          'To status': 'الحالة الجديدة',
          'To warehouse': 'مخزن الهدف',
          'Total credit': 'إجمالي الدائن',
          'Total debit': 'إجمالي المدين',
          'Transaction date': 'تاريخ الحركة المالية',
          'Transfer date': 'تاريخ النقل',
          'Transfer number': 'رقم النقل',
          'Type': 'النوع',
          'Updated at': 'تاريخ التحديث',
          'Vehicle': 'السيارة',
          'Voucher number': 'رقم السند',
          'Year': 'السنة',
        }[english] ??
        english;
  }
}

class _PdfBranding {
  const _PdfBranding({
    required this.companyName,
    required this.address,
    required this.phone,
    required this.taxNumber,
    required this.logo,
  });

  final String companyName;
  final String address;
  final String phone;
  final String taxNumber;
  final pw.MemoryImage? logo;
}
