import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:quality_line_erp/core/exporting/pdf_print_service.dart';

import 'package:quality_line_erp/core/cloud/cloud_feature_command.dart';
import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'package:quality_line_erp/core/printing/premium_document_theme.dart';
import 'package:quality_line_erp/core/printing/pdf_text_support.dart';

/// Official printable warehouse-transfer document used by both vehicles and
/// inventory products. It intentionally shares the same company identity,
/// header hierarchy, tables and signature layout as commercial documents.
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
    // The bundled family covers Arabic and Latin plus operational punctuation,
    // keeping English transfer details free of missing-glyph substitutions.
    final fontPack = await PdfTextSupport.loadFonts();
    final regular = fontPack.regular;
    final bold = fontPack.bold;
    final branding = await _loadBranding(language);
    final direction = arabic ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final border = PdfColor.fromHex('#D3D5D7');
    final surface = PdfColor.fromHex('#F5F6F6');
    final accent = PremiumDocumentTheme.accent;
    final primary = PdfColor.fromHex('#000000');
    final secondary = PdfColor.fromHex('#5F6266');
    final number = documentNumber.trim().isEmpty ? '—' : documentNumber.trim();
    final normalizedItems = items.isEmpty
        ? <Map<String, Object?>>[
            <String, Object?>{
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

    final document = pw.Document(
      title: '${_t('Warehouse transfer order', language)} $number',
      author: branding.companyName,
      creator: 'Quality Line ERP',
    );

    String value(Object? raw) {
      final text = raw?.toString().trim() ?? '';
      return text.isEmpty || text.toLowerCase() == 'null' ? '—' : text;
    }

    pw.Widget warehousePanel(String title, Map<String, Object?> warehouse) =>
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: border, width: .7),
              color: PdfColors.white,
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.symmetric(vertical: 5),
                  decoration: pw.BoxDecoration(
                    color: primary,
                    border: pw.Border(
                      bottom: pw.BorderSide(color: accent, width: 2),
                    ),
                  ),
                  child: PdfTextSupport.text(
                    _t(title, language),
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      font: bold,
                      color: PdfColors.white,
                      fontSize: 10,
                    ),
                  ),
                ),
                pw.SizedBox(height: 8),
                _line(_t('Warehouse code', language), warehouse['code'], bold),
                _line(_t('Warehouse name', language), warehouse['name'], bold),
                _line(_t('Address', language), warehouse['address'], bold),
                _line(_t('Manager', language), warehouse['managerName'], bold),
                _line(_t('Phone', language), warehouse['phone'], bold),
              ],
            ),
          ),
        );

    final machinePayload = jsonEncode(<String, Object?>{
      'documentNumber': number,
      'transferDate': transferDate,
      'fromWarehouseId': sourceWarehouse['id'],
      'toWarehouseId': destinationWarehouse['id'],
      'itemCount': normalizedItems.length,
    });

    document.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 26),
          theme: pw.ThemeData.withFont(base: regular, bold: bold),
          textDirection: direction,
        ),
        header: (_) => pw.Column(
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.SizedBox(
                  width: 72,
                  height: 52,
                  child: branding.logo == null
                      ? pw.Container(
                          alignment: pw.Alignment.center,
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(color: border),
                          ),
                          child: PdfTextSupport.text(
                            'QL',
                            style: pw.TextStyle(font: bold, fontSize: 18),
                          ),
                        )
                      : pw.Image(branding.logo!, fit: pw.BoxFit.contain),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      PdfTextSupport.text(
                        branding.companyName,
                        style: pw.TextStyle(font: bold, fontSize: 16),
                      ),
                      if (branding.address.isNotEmpty)
                        PdfTextSupport.text(
                          branding.address,
                          style: pw.TextStyle(fontSize: 8, color: secondary),
                        ),
                      if (branding.phone.isNotEmpty)
                        PdfTextSupport.text(
                          '${_t('Phone', language)}: ${branding.phone}',
                          style: pw.TextStyle(fontSize: 8, color: secondary),
                        ),
                    ],
                  ),
                ),
                pw.Container(
                  width: 190,
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: primary,
                    border: pw.Border(
                      bottom: pw.BorderSide(color: accent, width: 3),
                    ),
                  ),
                  child: pw.Column(
                    children: [
                      PdfTextSupport.text(
                        _t('Warehouse transfer order', language),
                        style: pw.TextStyle(
                          font: bold,
                          color: PdfColors.white,
                          fontSize: 13,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      PdfTextSupport.text(
                        number,
                        style: pw.TextStyle(
                          font: bold,
                          color: accent,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Divider(color: border, thickness: .7),
          ],
        ),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            PdfTextSupport.text(
              '${_t('Printed from Quality Line ERP', language)} • ${DateTime.now().toLocal().toIso8601String()}',
              style: pw.TextStyle(fontSize: 6.5, color: secondary),
            ),
            PdfTextSupport.text(
              '${_t('Page', language)} ${context.pageNumber}/${context.pagesCount}',
              style: pw.TextStyle(fontSize: 6.5, color: secondary),
            ),
          ],
        ),
        build: (_) => [
          pw.Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _summaryBox(
                _t('Transfer date', language),
                value(transferDate),
                border,
                bold,
              ),
              _summaryBox(
                _t('Prepared by', language),
                value(preparedBy),
                border,
                bold,
              ),
              _summaryBox(
                _t('Items count', language),
                normalizedItems.length.toString(),
                border,
                bold,
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              warehousePanel('Source warehouse', sourceWarehouse),
              pw.SizedBox(width: 10),
              warehousePanel('Destination warehouse', destinationWarehouse),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: pw.BoxDecoration(
              color: primary,
              border: pw.Border(bottom: pw.BorderSide(color: accent, width: 2)),
            ),
            child: PdfTextSupport.text(
              _t('Transfer items', language),
              style: pw.TextStyle(
                font: bold,
                color: PdfColors.white,
                fontSize: 11,
              ),
            ),
          ),
          pw.TableHelper.fromTextArray(
            border: pw.TableBorder.all(color: border, width: .45),
            headerDecoration: pw.BoxDecoration(color: secondary),
            oddRowDecoration: pw.BoxDecoration(color: surface),
            headerStyle: pw.TextStyle(
              font: bold,
              color: PdfColors.white,
              fontSize: 7.5,
            ),
            cellStyle: const pw.TextStyle(fontSize: 7.2),
            cellAlignment: arabic
                ? pw.Alignment.centerRight
                : pw.Alignment.centerLeft,
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
            data: [
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
            pw.SizedBox(height: 12),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(9),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: border),
                color: surface,
              ),
              child: PdfTextSupport.text(
                '${_t('Notes', language)}: ${notes!.trim()}',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ),
          ],
          pw.SizedBox(height: 18),
          if (includeMachineCode)
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    PdfTextSupport.text(
                      _t('Document verification', language),
                      style: pw.TextStyle(font: bold, fontSize: 8),
                    ),
                    pw.SizedBox(height: 5),
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.code128(),
                      data: number,
                      width: 190,
                      height: 38,
                      drawText: false,
                      textStyle: pw.TextStyle(font: regular, fontSize: 7),
                    ),
                  ],
                ),
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: machinePayload,
                  width: 70,
                  height: 70,
                  textStyle: pw.TextStyle(font: regular, fontSize: 7),
                ),
              ],
            ),
          pw.SizedBox(height: 22),
          pw.Row(
            children: [
              _signature(_t('Prepared by', language), border, bold),
              pw.SizedBox(width: 12),
              _signature(
                _t('Source warehouse signature', language),
                border,
                bold,
              ),
              pw.SizedBox(width: 12),
              _signature(
                _t('Destination warehouse signature', language),
                border,
                bold,
              ),
              pw.SizedBox(width: 12),
              _signature(_t('Approval signature', language), border, bold),
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

  static pw.Widget _line(String label, Object? raw, pw.Font bold) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty || value.toLowerCase() == 'null') return pw.SizedBox();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: PdfTextSupport.text(
        '$label: $value',
        style: pw.TextStyle(font: bold, fontSize: 8),
      ),
    );
  }

  static pw.Widget _summaryBox(
    String label,
    String value,
    PdfColor border,
    pw.Font bold,
  ) => pw.Container(
    width: 165,
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: border, width: .6),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        PdfTextSupport.text(
          label,
          style: pw.TextStyle(font: bold, fontSize: 7),
        ),
        pw.SizedBox(height: 3),
        PdfTextSupport.text(value, style: const pw.TextStyle(fontSize: 8.5)),
      ],
    ),
  );

  static pw.Widget _signature(String title, PdfColor border, pw.Font bold) =>
      pw.Expanded(
        child: pw.Container(
          height: 70,
          padding: const pw.EdgeInsets.all(7),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: border, width: .6),
          ),
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              PdfTextSupport.text(
                title,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(font: bold, fontSize: 7),
              ),
              pw.Container(height: .5, color: border),
            ],
          ),
        ),
      );

  Future<_WarehouseTransferBranding> _loadBranding(String language) async {
    Map<String, dynamic> row = <String, dynamic>{};
    try {
      row = await CloudFeatureCommand.instance.map(
        'company_settings',
        'branding',
      );
    } catch (error, stackTrace) {
      AppLogger.debug(
        'Warehouse transfer branding fallback: $error\n$stackTrace',
      );
    }
    final values = <String, String>{
      for (final entry in row.entries) entry.key: entry.value?.toString() ?? '',
    };
    pw.MemoryImage? logo;
    if (!kIsWeb) {
      for (final path in const <String>[
        'assets/images/khat_al_jawda_logo.jpg',
        'assets/images/logo.png',
      ]) {
        try {
          final data = await rootBundle.load(path);
          logo = pw.MemoryImage(data.buffer.asUint8List());
          break;
        } catch (_) {
          // Try the next configured logo.
        }
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
      address: values['company_address'] ?? '',
      phone: values['company_phone'] ?? '',
      logo: logo,
    );
  }

  static String _t(String value, String language) {
    if (language != 'ar') return value;
    return const <String, String>{
          'Warehouse transfer order': 'أمر نقل مخزني',
          'No items': 'لا توجد عناصر',
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
          'Printed from Quality Line ERP': 'طبع من نظام خط الجودة ERP',
          'Page': 'الصفحة',
        }[value] ??
        value;
  }
}

class _WarehouseTransferBranding {
  const _WarehouseTransferBranding({
    required this.companyName,
    required this.address,
    required this.phone,
    required this.logo,
  });

  final String companyName;
  final String address;
  final String phone;
  final pw.MemoryImage? logo;
}
