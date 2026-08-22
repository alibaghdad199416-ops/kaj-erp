import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:quality_line_erp/core/exporting/pdf_print_service.dart';
import 'package:quality_line_erp/core/printing/pdf_text_support.dart';

/// Printable product/material maintenance card.
///
/// Privacy boundary:
/// - no FIFO / requested / actual cost values
/// - no labor / parts / total maintenance cost
/// - no profit / margin
/// - no vehicle purchase / maintenance / total cost
class ProductMaintenanceCardPdfService {
  const ProductMaintenanceCardPdfService();

  Future<void> printCard({
    required Map<String, Object?> card,
    required bool arabic,
  }) async {
    final bytes = await build(card: card, arabic: arabic);
    final product = _map(card['product']);
    await PdfPrintService.print(
      fileName:
          'product-maintenance-card-${_safeFilePart(product['code'] ?? product['id'])}.pdf',
      bytes: bytes,
    );
  }

  Future<Uint8List> build({
    required Map<String, Object?> card,
    required bool arabic,
  }) async {
    arabic = PdfTextSupport.canonicalPdfArabic(arabic);
    final fonts = await PdfTextSupport.loadFonts();
    final presentation = buildPresentation(card);
    final product = _map(presentation['product']);
    final history = _list(presentation['maintenanceHistory']);
    final direction = arabic ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final primary = PdfColor.fromHex('#123B49');
    final accent = PdfColor.fromHex('#C59B45');
    final border = PdfColor.fromHex('#D9DDDF');
    String t(String ar, String en) => arabic ? ar : en;
    String value(Object? raw) {
      final text = PdfTextSupport.sanitize(raw, singleLine: true);
      return text.isEmpty ? '—' : text;
    }

    pw.Widget labelValue(String label, Object? raw, {double width = 170}) {
      return pw.Container(
        width: width,
        padding: const pw.EdgeInsets.all(7),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: border, width: .5),
          borderRadius: pw.BorderRadius.circular(5),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            PdfTextSupport.text(
              label,
              style: pw.TextStyle(
                font: fonts.bold,
                fontSize: 6.7,
                color: PdfColors.grey700,
              ),
            ),
            pw.SizedBox(height: 2),
            PdfTextSupport.text(
              value(raw),
              style: pw.TextStyle(font: fonts.bold, fontSize: 8),
              maxLines: 3,
            ),
          ],
        ),
      );
    }

    final document = pw.Document(
      title: value(t('بطاقة صيانة المادة', 'Product Maintenance Card')),
      theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(26, 24, 26, 24),
        textDirection: direction,
        header: (_) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 8),
          decoration: pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: accent, width: 1.5)),
          ),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: PdfTextSupport.text(
                  t('بطاقة صيانة المادة', 'Product Maintenance Card'),
                  style: pw.TextStyle(
                    font: fonts.bold,
                    color: primary,
                    fontSize: 15,
                  ),
                ),
              ),
              PdfTextSupport.text(
                value(product['code']),
                style: pw.TextStyle(font: fonts.bold, fontSize: 10),
              ),
            ],
          ),
        ),
        footer: (context) => pw.Row(
          children: [
            pw.Expanded(
              child: PdfTextSupport.text(
                t(
                  'سجل تشغيلي — لا يتضمن كلفة الصيانة أو كلفة المركبة.',
                  'Operational service history — maintenance and vehicle costs are excluded.',
                ),
                style: const pw.TextStyle(
                  fontSize: 6.5,
                  color: PdfColors.grey700,
                ),
              ),
            ),
            PdfTextSupport.text(
              '${context.pageNumber}/${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 6.5),
            ),
          ],
        ),
        build: (_) => [
          pw.Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              labelValue(t('المادة', 'Product'), product['name'], width: 250),
              labelValue(t('الرمز', 'Code'), product['code']),
              labelValue(t('الوحدة', 'Unit'), product['unit']),
              if (value(product['category']) != '—')
                labelValue(t('المجموعة', 'Group'), product['category']),
            ],
          ),
          pw.SizedBox(height: 14),
          PdfTextSupport.text(
            t('سجلات الصيانة حسب المركبة', 'Maintenance History by Vehicle'),
            style: pw.TextStyle(font: fonts.bold, color: primary, fontSize: 12),
          ),
          pw.SizedBox(height: 8),
          if (history.isEmpty)
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: border),
              ),
              child: PdfTextSupport.text(
                t(
                  'لا توجد سجلات صيانة مرتبطة بهذه المادة.',
                  'No maintenance records are linked to this product.',
                ),
              ),
            )
          else
            ...history.map((order) {
              final warehouses = _list(order['warehouseContributions']);
              final services = _list(order['relatedServices']);
              final vehicle = <String>[
                value(order['carNumber']),
                value(order['carName']),
              ].where((v) => v != '—').join(' • ');
              return pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 9),
                padding: const pw.EdgeInsets.all(9),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  border: pw.Border.all(color: border, width: .5),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: PdfTextSupport.text(
                            '${value(order['orderNumber'])} • ${value(order['maintenanceDate'])}',
                            style: pw.TextStyle(
                              font: fonts.bold,
                              fontSize: 9.5,
                            ),
                          ),
                        ),
                        PdfTextSupport.text(
                          value(order['workflowStage']),
                          style: pw.TextStyle(
                            font: fonts.bold,
                            fontSize: 8,
                            color: primary,
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 6),
                    pw.Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        labelValue(
                          t('المركبة', 'Vehicle'),
                          vehicle,
                          width: 245,
                        ),
                        labelValue(
                          t('رقم الشاصي', 'Chassis'),
                          order['chassis'],
                          width: 185,
                        ),
                        labelValue(
                          t('رقم اللوحة', 'Plate'),
                          order['plateNumber'],
                          width: 130,
                        ),
                        labelValue(
                          t('العميل', 'Customer'),
                          order['customerName'],
                          width: 190,
                        ),
                        labelValue(
                          t('المطلوب', 'Requested'),
                          order['requestedQuantity'],
                          width: 105,
                        ),
                        labelValue(
                          t('المصروف', 'Issued'),
                          order['issuedQuantity'],
                          width: 105,
                        ),
                        labelValue(
                          t('المرتجع', 'Reversed'),
                          order['reversedQuantity'],
                          width: 105,
                        ),
                        labelValue(
                          t('المتبقي', 'Remaining'),
                          order['remainingQuantity'],
                          width: 105,
                        ),
                        labelValue(
                          t('إذن الصرف', 'Stock issue'),
                          '${value(order['stockIssueNumber'])} / ${value(order['stockIssueStatus'])}',
                          width: 185,
                        ),
                        labelValue(
                          t('الفاتورة', 'Invoice'),
                          '${value(order['invoiceNumber'])} / ${value(order['invoiceStatus'])}',
                          width: 185,
                        ),
                        labelValue(
                          t('حالة الدفع', 'Payment status'),
                          order['paymentStatus'],
                          width: 150,
                        ),
                      ],
                    ),
                    if (warehouses.isNotEmpty) ...[
                      pw.SizedBox(height: 6),
                      PdfTextSupport.text(
                        t('المخازن', 'Warehouses'),
                        style: pw.TextStyle(font: fonts.bold, fontSize: 7.5),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: warehouses
                            .map(
                              (wh) => labelValue(
                                value(wh['warehouseName']),
                                '${t('مصروف', 'Issued')}: ${value(wh['issuedQuantity'])} • ${t('مرتجع', 'Reversed')}: ${value(wh['reversedQuantity'])}',
                                width: 180,
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ],
                    if (services.isNotEmpty) ...[
                      pw.SizedBox(height: 6),
                      PdfTextSupport.text(
                        t('الخدمات المرتبطة', 'Related services'),
                        style: pw.TextStyle(font: fonts.bold, fontSize: 7.5),
                      ),
                      pw.SizedBox(height: 3),
                      ...services.map(
                        (svc) => PdfTextSupport.text(
                          '• ${value(svc['name'])} × ${value(svc['quantity'])}',
                          style: const pw.TextStyle(fontSize: 7.2),
                        ),
                      ),
                    ],
                    if (value(order['notes']) != '—') ...[
                      pw.SizedBox(height: 5),
                      PdfTextSupport.text(
                        '${t('ملاحظات', 'Notes')}: ${value(order['notes'])}',
                        style: const pw.TextStyle(fontSize: 7.2),
                      ),
                    ],
                    if (value(order['cancelReason']) != '—') ...[
                      pw.SizedBox(height: 3),
                      PdfTextSupport.text(
                        '${t('سبب الإلغاء', 'Cancellation reason')}: ${value(order['cancelReason'])}',
                        style: const pw.TextStyle(fontSize: 7.2),
                      ),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );

    return document.save();
  }

  /// Explicit privacy whitelist. Internal costs can never enter the PDF through
  /// accidental future fields added to the RPC.
  Map<String, Object?> buildPresentation(Map<String, Object?> card) {
    final product = _map(card['product']);
    const productKeys = <String>{'id', 'code', 'name', 'unit', 'category'};
    const orderKeys = <String>{
      'id',
      'orderNumber',
      'maintenanceDate',
      'status',
      'workflowStage',
      'isDeleted',
      'pricingType',
      'carId',
      'carName',
      'carNumber',
      'brand',
      'model',
      'year',
      'chassis',
      'plateNumber',
      'customerId',
      'customerName',
      'requestedQuantity',
      'issuedQuantity',
      'reversedQuantity',
      'remainingQuantity',
      'stockIssueNumber',
      'stockIssueStatus',
      'invoiceNumber',
      'invoiceStatus',
      'paymentStatus',
      'notes',
      'cancelReason',
    };
    const warehouseKeys = <String>{
      'warehouseId',
      'warehouseName',
      'issuedQuantity',
      'reversedQuantity',
    };
    const serviceKeys = <String>{'name', 'quantity', 'lineType'};

    return <String, Object?>{
      'product': <String, Object?>{
        for (final entry in product.entries)
          if (productKeys.contains(entry.key)) entry.key: entry.value,
      },
      'maintenanceHistory': _list(card['maintenanceHistory'])
          .map(
            (order) => <String, Object?>{
              for (final entry in order.entries)
                if (orderKeys.contains(entry.key)) entry.key: entry.value,
              'warehouseContributions': _list(order['warehouseContributions'])
                  .map(
                    (warehouse) => <String, Object?>{
                      for (final entry in warehouse.entries)
                        if (warehouseKeys.contains(entry.key))
                          entry.key: entry.value,
                    },
                  )
                  .toList(growable: false),
              'relatedServices': _list(order['relatedServices'])
                  .map(
                    (service) => <String, Object?>{
                      for (final entry in service.entries)
                        if (serviceKeys.contains(entry.key))
                          entry.key: entry.value,
                    },
                  )
                  .toList(growable: false),
            },
          )
          .toList(growable: false),
    };
  }

  static String _safeFilePart(Object? value) =>
      PdfTextSupport.filePart(value).isEmpty
      ? 'product'
      : PdfTextSupport.filePart(value);

  static Map<String, Object?> _map(Object? raw) =>
      raw is Map ? Map<String, Object?>.from(raw) : const {};

  static List<Map<String, Object?>> _list(Object? raw) => raw is List
      ? raw
            .whereType<Map>()
            .map((value) => Map<String, Object?>.from(value))
            .toList(growable: false)
      : const [];
}
