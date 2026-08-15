import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:quality_line_erp/core/cloud/cloud_feature_command.dart';
import 'package:quality_line_erp/core/exporting/pdf_print_service.dart';
import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'package:quality_line_erp/core/printing/pdf_text_support.dart';
import 'package:quality_line_erp/core/printing/unified_pdf_document.dart';
import 'package:quality_line_erp/core/printing/unified_pdf_identity.dart';

/// Official bilingual warehouse-transfer document using the same visual chrome
/// as commercial documents, accounting reports and vouchers.
class WarehouseTransferPdfService {
  const WarehouseTransferPdfService();

  Future<Uint8List> build({
    required String language,
    required String documentNumber,
    required String transferDate,
    required Map<String, Object?> sourceWarehouse,
    required Map<String, Object?> destinationWarehouse,
    required List<Map<String, Object?>> items,
    String? preparedBy,
    String? notes,
    bool includeMachineCode = true,
  }) async {
    language = PdfTextSupport.canonicalPdfLanguage(language);
    final arabic = language == 'ar';
    final fonts = await PdfTextSupport.loadFonts();
    final regular = fonts.regular;
    final bold = fonts.bold;
    final branding = await _loadBranding(language);
    final number = documentNumber.trim().isEmpty ? '—' : documentNumber.trim();
    String value(Object? raw) {
      final text = raw?.toString().trim() ?? '';
      return text.isEmpty || text.toLowerCase() == 'null' ? '—' : text;
    }

    final normalizedItems = items.isEmpty
        ? <Map<String, Object?>>[
            {
              'code': '—',
              'name': _t('No items', language),
              'details': '—',
              'quantity': '—',
              'unit': '—',
              'cost': '—',
              'currency': '—',
            },
          ]
        : items;
    final machinePayload = jsonEncode({
      'documentNumber': number,
      'transferDate': transferDate,
      'fromWarehouseId': sourceWarehouse['id'],
      'toWarehouseId': destinationWarehouse['id'],
      'itemCount': normalizedItems.length,
    });

    final document = pw.Document(
      title: '${_t('Warehouse transfer order', language)} $number',
      author: branding.companyName,
      creator: 'Quality Line ERP',
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
    document.addPage(
      pw.MultiPage(
        pageTheme: UnifiedPdfDocument.pageTheme(
          fonts,
          textDirection: arabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        ),
        header: (_) => UnifiedPdfDocument.documentHeader(
          bold: bold,
          documentType: _t('Warehouse transfer order', language),
          documentNumber: number,
          logo: branding.logo,
          companyName: branding.companyName,
        ),
        footer: (context) => UnifiedPdfDocument.footer(
          regular: regular,
          pageNumber: context.pageNumber,
          pageCount: context.pagesCount,
          arabic: arabic,
        ),
        build: (_) => <pw.Widget>[
          UnifiedPdfDocument.titleBlock(
            bold: bold,
            title: _t('Warehouse transfer order', language),
            subtitle: '${_t('Transfer date', language)}: ${value(transferDate)}',
            status: number,
          ),
          pw.Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              UnifiedPdfDocument.summaryTile(
                bold: bold,
                label: _t('Prepared by', language),
                value: value(preparedBy),
              ),
              UnifiedPdfDocument.summaryTile(
                bold: bold,
                label: _t('Items count', language),
                value: normalizedItems.length.toString(),
              ),
            ],
          ),
          UnifiedPdfDocument.sectionHeader(
            bold: bold,
            title: _t('Warehouses', language),
          ),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _warehousePanel(
                _t('Source warehouse', language),
                sourceWarehouse,
                bold,
                language,
              ),
              pw.SizedBox(width: 10),
              _warehousePanel(
                _t('Destination warehouse', language),
                destinationWarehouse,
                bold,
                language,
              ),
            ],
          ),
          UnifiedPdfDocument.sectionHeader(
            bold: bold,
            title: _t('Transfer items', language),
            trailing: normalizedItems.length.toString(),
          ),
          UnifiedPdfDocument.table(
            regular: regular,
            bold: bold,
            arabic: arabic,
            headers: [
              '#',
              _t('Code', language),
              _t('Item', language),
              _t('Details', language),
              _t('Quantity', language),
              _t('Unit', language),
              _t('Cost', language),
              _t('Currency', language),
            ],
            rows: [
              for (var index = 0; index < normalizedItems.length; index++)
                [
                  '${index + 1}',
                  value(normalizedItems[index]['code']),
                  value(normalizedItems[index]['name']),
                  value(normalizedItems[index]['details']),
                  value(normalizedItems[index]['quantity']),
                  value(normalizedItems[index]['unit']),
                  value(normalizedItems[index]['cost']),
                  value(normalizedItems[index]['currency']),
                ],
            ],
          ),
          if ((notes ?? '').trim().isNotEmpty) ...[
            UnifiedPdfDocument.sectionHeader(
              bold: bold,
              title: _t('Notes', language),
            ),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(9),
              decoration: pw.BoxDecoration(
                color: UnifiedPdfIdentity.surface,
                border: pw.Border.all(color: UnifiedPdfIdentity.border),
              ),
              child: PdfTextSupport.text(notes!.trim()),
            ),
          ],
          if (includeMachineCode) ...[
            UnifiedPdfDocument.sectionHeader(
              bold: bold,
              title: _t('Document verification', language),
            ),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.BarcodeWidget(
                  barcode: pw.Barcode.code128(),
                  data: number,
                  width: 190,
                  height: 38,
                  drawText: false,
                ),
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: machinePayload,
                  width: 70,
                  height: 70,
                ),
              ],
            ),
          ],
          pw.SizedBox(height: 18),
          pw.Row(
            children: [
              UnifiedPdfDocument.signatureBox(
                bold: bold,
                title: _t('Prepared by', language),
              ),
              pw.SizedBox(width: 8),
              UnifiedPdfDocument.signatureBox(
                bold: bold,
                title: _t('Source warehouse signature', language),
              ),
              pw.SizedBox(width: 8),
              UnifiedPdfDocument.signatureBox(
                bold: bold,
                title: _t('Destination warehouse signature', language),
              ),
              pw.SizedBox(width: 8),
              UnifiedPdfDocument.signatureBox(
                bold: bold,
                title: _t('Approval signature', language),
              ),
            ],
          ),
        ],
      ),
    );
    return document.save();
  }

  Future<void> printDocument({
    required String language,
    required String documentNumber,
    required String transferDate,
    required Map<String, Object?> sourceWarehouse,
    required Map<String, Object?> destinationWarehouse,
    required List<Map<String, Object?>> items,
    String? preparedBy,
    String? notes,
    bool includeMachineCode = true,
  }) async {
    final bytes = await build(
      language: language,
      documentNumber: documentNumber,
      transferDate: transferDate,
      sourceWarehouse: sourceWarehouse,
      destinationWarehouse: destinationWarehouse,
      items: items,
      preparedBy: preparedBy,
      notes: notes,
      includeMachineCode: includeMachineCode,
    );
    await PdfPrintService.print(
      fileName: 'warehouse-transfer-$documentNumber.pdf',
      bytes: bytes,
    );
  }

  pw.Widget _warehousePanel(
    String title,
    Map<String, Object?> warehouse,
    pw.Font bold,
    String language,
  ) => pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.all(9),
      decoration: pw.BoxDecoration(
        color: UnifiedPdfIdentity.surface,
        border: pw.Border.all(color: UnifiedPdfIdentity.border),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          PdfTextSupport.text(
            title,
            style: pw.TextStyle(font: bold, fontSize: 9),
          ),
          pw.SizedBox(height: 5),
          _line(_t('Warehouse code', language), warehouse['code'], bold),
          _line(_t('Warehouse name', language), warehouse['name'], bold),
          _line(_t('Address', language), warehouse['address'], bold),
          _line(_t('Manager', language), warehouse['managerName'], bold),
          _line(_t('Phone', language), warehouse['phone'], bold),
        ],
      ),
    ),
  );

  pw.Widget _line(String label, Object? raw, pw.Font bold) {
    final text = raw?.toString().trim() ?? '';
    if (text.isEmpty || text.toLowerCase() == 'null') return pw.SizedBox();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: PdfTextSupport.text(
        '$label: $text',
        style: pw.TextStyle(font: bold, fontSize: 7.5),
      ),
    );
  }

  Future<_WarehouseTransferBranding> _loadBranding(String language) async {
    Map<String, dynamic> row = <String, dynamic>{};
    try {
      row = await CloudFeatureCommand.instance.map('company_settings', 'branding');
    } catch (error, stackTrace) {
      AppLogger.debug('Warehouse transfer branding fallback: $error\n$stackTrace');
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
    final arabic = language == 'ar';
    return _WarehouseTransferBranding(
      companyName: arabic
          ? (values['company_name']?.trim().isNotEmpty == true
              ? values['company_name']!
              : 'شركة خط الجودة')
          : (values['company_name_en']?.trim().isNotEmpty == true
              ? values['company_name_en']!
              : 'Quality Line'),
      logo: logo,
    );
  }

  String _t(String value, String language) {
    if (language != 'ar') return value;
    return const <String, String>{
          'Warehouse transfer order': 'أمر نقل مخزني',
          'No items': 'لا توجد عناصر',
          'Warehouses': 'المخازن',
          'Warehouse code': 'رمز المخزن',
          'Warehouse name': 'اسم المخزن',
          'Address': 'العنوان',
          'Manager': 'المسؤول',
          'Phone': 'الهاتف',
          'Source warehouse': 'المخزن المصدر',
          'Destination warehouse': 'المخزن المستلم',
          'Transfer date': 'تاريخ النقل',
          'Prepared by': 'أعده',
          'Items count': 'عدد العناصر',
          'Transfer items': 'تفاصيل العناصر',
          'Code': 'الرمز',
          'Item': 'العنصر',
          'Details': 'التفاصيل',
          'Quantity': 'الكمية',
          'Unit': 'الوحدة',
          'Cost': 'الكلفة',
          'Currency': 'العملة',
          'Notes': 'الملاحظات',
          'Document verification': 'التحقق من المستند',
          'Source warehouse signature': 'توقيع المخزن المصدر',
          'Destination warehouse signature': 'توقيع المخزن المستلم',
          'Approval signature': 'الاعتماد',
        }[value] ??
        value;
  }
}

class _WarehouseTransferBranding {
  const _WarehouseTransferBranding({required this.companyName, required this.logo});
  final String companyName;
  final pw.MemoryImage? logo;
}
