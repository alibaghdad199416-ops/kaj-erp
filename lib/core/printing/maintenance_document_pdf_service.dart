import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:quality_line_erp/core/exporting/pdf_print_service.dart';
import 'package:quality_line_erp/core/logging/app_logger.dart';

import 'package:quality_line_erp/core/printing/pdf_text_support.dart';
import 'package:quality_line_erp/core/printing/premium_document_theme.dart';
import 'package:quality_line_erp/core/printing/enterprise_document_presentation.dart';
import 'package:quality_line_erp/features/maintenance/models/maintenance_order_model.dart';

class MaintenanceWarehouseIssueRow {
  const MaintenanceWarehouseIssueRow({
    required this.productId,
    required this.productName,
    required this.warehouseId,
    required this.warehouseName,
    required this.quantity,
    required this.issueReferences,
  });

  final String productId;
  final String productName;
  final String warehouseId;
  final String warehouseName;
  final double quantity;
  final List<String> issueReferences;
}

List<MaintenanceWarehouseIssueRow> maintenanceWarehouseIssueRows({
  required List<MaintenanceLineModel> lines,
  required List<Map<String, Object?>> issueEvents,
  String? fallbackIssueReference,
}) {
  final linesById = <String, MaintenanceLineModel>{
    for (final line in lines) line.id: line,
  };
  final grouped = <String, MaintenanceWarehouseIssueRow>{};
  for (final event in issueEvents) {
    if (event['status']?.toString() != 'executed') continue;
    final quantity = (event['quantity'] as num?)?.toDouble() ?? 0;
    if (quantity <= 0) continue;
    final lineId = event['lineId']?.toString() ?? '';
    final line = linesById[lineId];
    final productId = event['productId']?.toString() ?? line?.productId ?? '';
    final warehouseId = event['warehouseId']?.toString() ?? '';
    final warehouseName = event['warehouseName']?.toString().trim() ?? '';
    final key = '$productId\u0000$warehouseId';
    final reference = fallbackIssueReference?.trim().isNotEmpty == true
        ? fallbackIssueReference!.trim()
        : event['issueNumber']?.toString().trim().isNotEmpty == true
        ? event['issueNumber']!.toString()
        : event['issueId']?.toString() ?? '';
    final previous = grouped[key];
    grouped[key] = MaintenanceWarehouseIssueRow(
      productId: productId,
      productName: line?.productName ?? event['description']?.toString() ?? '-',
      warehouseId: warehouseId,
      warehouseName: warehouseName.isEmpty ? warehouseId : warehouseName,
      quantity: (previous?.quantity ?? 0) + quantity,
      issueReferences: <String>{
        ...?previous?.issueReferences,
        if (reference.isNotEmpty) reference,
      }.toList(growable: false),
    );
  }
  final rows = grouped.values.toList(growable: false);
  rows.sort((a, b) {
    final product = a.productName.compareTo(b.productName);
    return product != 0 ? product : a.warehouseName.compareTo(b.warehouseName);
  });
  return rows;
}

class MaintenanceDocumentPdfService {
  const MaintenanceDocumentPdfService();

  Future<void> print({
    required MaintenanceOrderModel order,
    required List<MaintenanceLineModel> lines,
    List<Map<String, Object?>> issueEvents = const <Map<String, Object?>>[],
    double authoritativeIssuedQuantity = 0,
    required bool arabic,
  }) async {
    final bytes = await build(
      order: order,
      lines: lines,
      issueEvents: issueEvents,
      authoritativeIssuedQuantity: authoritativeIssuedQuantity,
      arabic: arabic,
    );
    await PdfPrintService.print(
      fileName: 'maintenance-${order.orderNumber}.pdf',
      bytes: bytes,
    );
  }

  Future<Uint8List> build({
    required MaintenanceOrderModel order,
    required List<MaintenanceLineModel> lines,
    List<Map<String, Object?>> issueEvents = const <Map<String, Object?>>[],
    double authoritativeIssuedQuantity = 0,
    required bool arabic,
  }) async {
    arabic = PdfTextSupport.canonicalPdfArabic(arabic);
    final stockLines = lines.where((line) => !line.isService).toList();
    final issuedRows = maintenanceWarehouseIssueRows(
      lines: stockLines,
      issueEvents: issueEvents,
      fallbackIssueReference: order.stockIssueNumber,
    );
    AppLogger.debug(
      'Maintenance PDF export: order=${order.orderNumber} orderId=${order.id} '
      'stockIssue=${order.stockIssueNumber ?? ''} issueEvents=${issueEvents.length} '
      'authoritativeIssuedQuantity=$authoritativeIssuedQuantity '
      'printableRows=${issuedRows.length}',
    );
    for (final event in issueEvents) {
      AppLogger.debug(
        'Maintenance PDF issue event: productId=${event['productId'] ?? ''} '
        'product=${event['description'] ?? ''} warehouseId=${event['warehouseId'] ?? ''} '
        'warehouse=${event['warehouseName'] ?? ''} quantity=${event['quantity'] ?? 0} '
        'reference=${event['issueNumber'] ?? event['issueId'] ?? ''} '
        'status=${event['status'] ?? ''} reversedAt=${event['reversedAt'] ?? ''}',
      );
    }
    for (final row in issuedRows) {
      AppLogger.debug(
        'Maintenance PDF row: product=${row.productName} warehouse=${row.warehouseName} '
        'quantity=${row.quantity} reference=${row.issueReferences.join(',')}',
      );
    }
    if ((order.stockIssueNumber?.trim().isNotEmpty ?? false) &&
        authoritativeIssuedQuantity > 0 &&
        issuedRows.isEmpty) {
      throw StateError('maintenance_issue_document_rows_missing');
    }
    final fonts = await PdfTextSupport.loadFonts();
    final regular = fonts.regular;
    final bold = fonts.bold;
    String clean(Object? value) => PdfTextSupport.sanitize(value);
    pw.MemoryImage? logo;
    if (!kIsWeb) {
      try {
        final logoData = await rootBundle.load(
          'assets/images/khat_al_jawda_logo.jpg',
        );
        logo = pw.MemoryImage(logoData.buffer.asUint8List());
      } catch (_) {
        logo = null;
      }
    }
    final direction = arabic ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final document = pw.Document(
      title: clean(
        arabic
            ? 'أمر صيانة ${order.orderNumber}'
            : 'Maintenance order ${order.orderNumber}',
      ),
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
    final primary = PdfColor.fromHex('#111827');
    final accent = PremiumDocumentTheme.accent;
    final border = PdfColor.fromHex('#D1D5DB');
    final surface = PdfColor.fromHex('#F5F6F6');

    pw.Widget heading(String title, {bool main = false}) => pw.Container(
      margin: const pw.EdgeInsets.only(top: 8, bottom: 7),
      padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: pw.BoxDecoration(
        color: primary,
        border: pw.Border(bottom: pw.BorderSide(color: accent, width: 2)),
      ),
      child: PdfTextSupport.text(
        clean(title),
        style: pw.TextStyle(
          font: bold,
          color: PdfColors.white,
          fontSize: main
              ? EnterpriseDocumentPresentation.titleSize
              : EnterpriseDocumentPresentation.sectionHeadingSize,
        ),
      ),
    );

    pw.Widget field(String label, Object? value) => pw.Container(
      constraints: const pw.BoxConstraints(minHeight: 34),
      padding: EnterpriseDocumentPresentation.fieldPadding,
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: border, width: .5),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: PdfTextSupport.text(
              clean(label),
              style: pw.TextStyle(
                font: bold,
                fontSize: EnterpriseDocumentPresentation.bodySize,
              ),
              textAlign: arabic ? pw.TextAlign.right : pw.TextAlign.left,
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            flex: 2,
            child: PdfTextSupport.text(
              clean(value ?? '-'),
              style: pw.TextStyle(
                font: regular,
                fontSize: EnterpriseDocumentPresentation.bodySize,
              ),
              textAlign: arabic ? pw.TextAlign.right : pw.TextAlign.left,
              maxLines: 4,
            ),
          ),
        ],
      ),
    );

    pw.Widget header(pw.Context context) => pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 9),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: border)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Row(
            children: [
              pw.SizedBox(
                width: 44,
                height: 44,
                child: logo == null
                    ? pw.SizedBox()
                    : pw.Image(logo, fit: pw.BoxFit.contain),
              ),
              pw.SizedBox(width: 10),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  PdfTextSupport.text(
                    clean(arabic ? 'شركة خط الجودة' : 'Quality Line'),
                    style: pw.TextStyle(font: bold, fontSize: 15),
                  ),
                  PdfTextSupport.text(
                    clean(
                      arabic
                          ? 'حزمة أمر صيانة رسمية'
                          : 'Official maintenance order package',
                    ),
                    style: pw.TextStyle(font: regular, fontSize: 8),
                  ),
                ],
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              PdfTextSupport.text(
                clean(order.orderNumber),
                style: pw.TextStyle(font: bold, fontSize: 12),
              ),
              PdfTextSupport.text(
                '${context.pageNumber} / ${context.pagesCount}',
                style: pw.TextStyle(font: regular, fontSize: 8),
              ),
            ],
          ),
        ],
      ),
    );

    pw.Widget footer(pw.Context context) => pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        PdfTextSupport.text(
          clean(
            arabic
                ? 'مستند إلكتروني صادر من نظام خط الجودة'
                : 'Electronic document generated by Quality Line ERP',
          ),
          style: pw.TextStyle(
            font: regular,
            fontSize: EnterpriseDocumentPresentation.footerSize,
          ),
        ),
        PdfTextSupport.text(
          clean(order.orderNumber),
          style: pw.TextStyle(
            font: regular,
            fontSize: EnterpriseDocumentPresentation.footerSize,
          ),
        ),
      ],
    );

    pw.Widget twoFields(
      String firstLabel,
      Object? firstValue,
      String secondLabel,
      Object? secondValue,
    ) => pw.Table(
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FlexColumnWidth(),
        1: pw.FlexColumnWidth(),
      },
      children: [
        pw.TableRow(
          children: [
            field(firstLabel, firstValue),
            field(secondLabel, secondValue),
          ],
        ),
      ],
    );

    pw.Widget tableHeaderCell(String value) => pw.Container(
      padding: EnterpriseDocumentPresentation.tableHeaderPadding,
      alignment: pw.Alignment.center,
      child: PdfTextSupport.text(
        clean(value),
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          font: bold,
          color: PdfColors.white,
          fontSize: EnterpriseDocumentPresentation.tableHeaderSize,
        ),
      ),
    );

    pw.Widget linesTable(List<MaintenanceLineModel> chunk) {
      final headers = arabic
          ? const ['البند', 'النوع', 'المخزن', 'الكمية', 'السعر', 'الإجمالي']
          : const ['Item', 'Type', 'Warehouse', 'Qty', 'Price', 'Total'];
      return pw.Table(
        columnWidths: const <int, pw.TableColumnWidth>{
          0: pw.FlexColumnWidth(2.5),
          1: pw.FlexColumnWidth(1.0),
          2: pw.FlexColumnWidth(1.5),
          3: pw.FlexColumnWidth(.7),
          4: pw.FlexColumnWidth(1.0),
          5: pw.FlexColumnWidth(1.1),
        },
        border: pw.TableBorder.all(color: border, width: .4),
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: primary),
            children: [for (final value in headers) tableHeaderCell(value)],
          ),
          for (var index = 0; index < chunk.length; index++)
            pw.TableRow(
              decoration: pw.BoxDecoration(
                color: index.isOdd ? surface : PdfColors.white,
              ),
              children: [
                _lineCell(
                  clean(chunk[index].productName),
                  regular: regular,
                  arabic: arabic,
                  alignCenter: false,
                ),
                _lineCell(
                  clean(
                    chunk[index].isService
                        ? (arabic ? 'خدمة' : 'Service')
                        : (arabic ? 'منتج مخزني' : 'Stock item'),
                  ),
                  regular: regular,
                  arabic: arabic,
                ),
                _lineCell(
                  clean(
                    chunk[index].isService
                        ? (arabic ? 'غير مخزني' : 'Non-stock')
                        : (chunk[index].warehouseName ?? '-'),
                  ),
                  regular: regular,
                  arabic: arabic,
                  alignCenter: false,
                ),
                _lineCell(
                  chunk[index].quantity.toString(),
                  regular: regular,
                  arabic: arabic,
                ),
                _lineCell(
                  chunk[index].unitPrice.toStringAsFixed(2),
                  regular: regular,
                  arabic: arabic,
                ),
                _lineCell(
                  (chunk[index].unitPrice * chunk[index].quantity)
                      .toStringAsFixed(2),
                  regular: bold,
                  arabic: arabic,
                ),
              ],
            ),
        ],
      );
    }

    pw.Widget issueTable(List<MaintenanceWarehouseIssueRow> chunk) {
      final headers = arabic
          ? const [
              'Ø§Ù„Ø¨Ù†Ø¯',
              'Ø§Ù„Ù…Ø®Ø²Ù†',
              'Ø§Ù„ÙƒÙ…ÙŠØ© Ø§Ù„ÙØ¹Ù„ÙŠØ©',
              'Ù…Ø±Ø¬Ø¹ Ø§Ù„ØµØ±Ù',
            ]
          : const ['Item', 'Actual warehouse', 'Actual qty', 'Issue reference'];
      return pw.Table(
        columnWidths: const <int, pw.TableColumnWidth>{
          0: pw.FlexColumnWidth(2.5),
          1: pw.FlexColumnWidth(1.8),
          2: pw.FlexColumnWidth(1),
          3: pw.FlexColumnWidth(2),
        },
        border: pw.TableBorder.all(color: border, width: .4),
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: primary),
            children: [for (final value in headers) tableHeaderCell(value)],
          ),
          for (var index = 0; index < chunk.length; index++)
            pw.TableRow(
              decoration: pw.BoxDecoration(
                color: index.isOdd ? surface : PdfColors.white,
              ),
              children: [
                _lineCell(
                  clean(chunk[index].productName),
                  regular: regular,
                  arabic: arabic,
                  alignCenter: false,
                ),
                _lineCell(
                  clean(chunk[index].warehouseName),
                  regular: regular,
                  arabic: arabic,
                  alignCenter: false,
                ),
                _lineCell(
                  clean(chunk[index].quantity),
                  regular: regular,
                  arabic: arabic,
                ),
                _lineCell(
                  clean(chunk[index].issueReferences.join(', ')),
                  regular: regular,
                  arabic: arabic,
                  alignCenter: false,
                ),
              ],
            ),
        ],
      );
    }

    const rowsPerPage = 13;
    List<List<MaintenanceLineModel>> chunksOf(
      List<MaintenanceLineModel> source,
    ) {
      if (source.isEmpty) return <List<MaintenanceLineModel>>[const []];
      final result = <List<MaintenanceLineModel>>[];
      for (var offset = 0; offset < source.length; offset += rowsPerPage) {
        final end = (offset + rowsPerPage).clamp(0, source.length).toInt();
        result.add(source.sublist(offset, end));
      }
      return result;
    }

    final requestedLineChunks = chunksOf(lines);
    final invoiceChunks = chunksOf(lines);
    final lineChunks = <List<MaintenanceWarehouseIssueRow>>[];
    if (issuedRows.isEmpty) {
      lineChunks.add(const <MaintenanceWarehouseIssueRow>[]);
    } else {
      for (var offset = 0; offset < issuedRows.length; offset += rowsPerPage) {
        final end = (offset + rowsPerPage).clamp(0, issuedRows.length).toInt();
        lineChunks.add(issuedRows.sublist(offset, end));
      }
    }
    final content = <pw.Widget>[
      heading(
        arabic ? 'صفحة أمر الصيانة' : 'Maintenance order page',
        main: true,
      ),
      twoFields(
        arabic ? 'رقم أمر الصيانة' : 'Maintenance order number',
        order.orderNumber,
        arabic ? 'الحالة' : 'Status',
        order.workflowLabel(arabic),
      ),
      twoFields(
        arabic ? 'السيارة' : 'Vehicle',
        order.carName,
        arabic ? 'العميل' : 'Customer',
        order.customerName ?? '-',
      ),
      twoFields(
        arabic ? 'تاريخ التشغيل' : 'Operational date',
        order.maintenanceDate,
        arabic ? 'نوع التسعير' : 'Pricing type',
        order.pricingLabelFor(arabic),
      ),
      twoFields(
        arabic ? 'العملة' : 'Currency',
        order.currencyCode,
        arabic ? 'مرحلة المستند' : 'Document stage',
        order.workflowLabel(arabic),
      ),
    ];

    for (var index = 0; index < requestedLineChunks.length; index++) {
      if (index > 0) content.add(pw.NewPage());
      content.add(
        heading(
          arabic
              ? 'الخدمات والمواد والأعمال المطلوبة — صفحة ${index + 1} من ${requestedLineChunks.length}'
              : 'Requested services, materials, and work — page ${index + 1} of ${requestedLineChunks.length}',
        ),
      );
      content.add(linesTable(requestedLineChunks[index]));
    }

    content.addAll([
      pw.SizedBox(height: 12),
      field(
        arabic ? 'وصف العمل والملاحظات' : 'Work description and notes',
        order.notes,
      ),
      pw.SizedBox(height: 24),
      pw.Row(
        children: [
          pw.Expanded(
            child: field(
              arabic ? 'اعتماد مسؤول الصيانة' : 'Maintenance approval',
              '',
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: field(arabic ? 'اعتماد العميل' : 'Customer approval', ''),
          ),
        ],
      ),
      pw.NewPage(),
      heading(arabic ? 'صفحة التجهيز المخزني' : 'Warehouse issue page'),
      twoFields(
        arabic ? 'رقم إذن صرف المخزون' : 'Stock issue number',
        order.stockIssueNumber,
        arabic ? 'مرجع أمر الصيانة' : 'Maintenance order reference',
        order.orderNumber,
      ),
    ]);

    for (var index = 0; index < lineChunks.length; index++) {
      content.add(
        pw.Align(
          alignment: arabic
              ? pw.Alignment.centerRight
              : pw.Alignment.centerLeft,
          child: PdfTextSupport.text(
            clean(
              arabic
                  ? 'مواد المخزن — صفحة ${index + 1} من ${lineChunks.length}'
                  : 'Warehouse materials — page ${index + 1} of ${lineChunks.length}',
            ),
            style: pw.TextStyle(font: bold, fontSize: 8),
          ),
        ),
      );
      content.add(pw.SizedBox(height: 6));
      content.add(issueTable(lineChunks[index]));
      if (index < lineChunks.length - 1) content.add(pw.NewPage());
    }

    for (var index = 0; index < invoiceChunks.length; index++) {
      content.add(pw.NewPage());
      content.add(
        heading(
          index == 0
              ? (arabic ? 'صفحة فاتورة الصيانة' : 'Maintenance invoice page')
              : (arabic
                    ? 'تفاصيل فاتورة الصيانة — صفحة ${index + 1} من ${invoiceChunks.length}'
                    : 'Maintenance invoice details — page ${index + 1} of ${invoiceChunks.length}'),
        ),
      );
      if (index == 0) {
        content.addAll([
          twoFields(
            arabic ? 'رقم فاتورة الصيانة' : 'Maintenance invoice number',
            order.invoiceNumber,
            arabic ? 'رقم أمر الصيانة' : 'Maintenance order number',
            order.orderNumber,
          ),
          twoFields(
            arabic ? 'قيمة الفاتورة' : 'Invoice amount',
            order.salePrice.toStringAsFixed(2),
            arabic ? 'العملة' : 'Currency',
            order.currencyCode,
          ),
        ]);
      }
      content.add(
        heading(
          arabic
              ? 'تفاصيل الخدمات والمواد المفوترة'
              : 'Billed services and materials',
        ),
      );
      content.add(linesTable(invoiceChunks[index]));
    }

    content.addAll([
      pw.NewPage(),
      heading(
        arabic
            ? 'صفحة الدفعات والقيود المالية'
            : 'Financial payments and posting page',
      ),
      twoFields(
        arabic ? 'قيمة الفاتورة' : 'Invoice amount',
        order.salePrice.toStringAsFixed(2),
        arabic ? 'المبلغ المدفوع' : 'Paid amount',
        order.paidAmount.toStringAsFixed(2),
      ),
      field(
        arabic ? 'الرصيد المتبقي' : 'Remaining balance',
        (order.salePrice - order.paidAmount).toStringAsFixed(2),
      ),
      twoFields(
        arabic ? 'مرجع الفاتورة' : 'Invoice reference',
        order.invoiceNumber,
        arabic ? 'مرجع الصرف المخزني' : 'Stock issue reference',
        order.stockIssueNumber,
      ),
      heading(arabic ? 'الملاحظات والاعتمادات' : 'Notes and approvals'),
      field(arabic ? 'الملاحظات' : 'Notes', order.notes),
      if ((order.cancelReason ?? '').trim().isNotEmpty) ...[
        pw.SizedBox(height: 8),
        field(
          arabic ? 'سبب الإلغاء' : 'Cancellation reason',
          order.cancelReason,
        ),
      ],
      pw.SizedBox(height: 30),
      pw.Row(
        children: [
          pw.Expanded(
            child: field(arabic ? 'توقيع المحاسب' : 'Accountant signature', ''),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: field(arabic ? 'توقيع العميل' : 'Customer signature', ''),
          ),
        ],
      ),
    ]);

    document.addPage(
      pw.MultiPage(
        pageFormat: EnterpriseDocumentPresentation.landscapePageFormat,
        margin: EnterpriseDocumentPresentation.pageMargin,
        textDirection: direction,
        header: header,
        footer: footer,
        build: (_) => content,
      ),
    );
    return document.save();
  }

  static pw.Widget _lineCell(
    String value, {
    required pw.Font regular,
    required bool arabic,
    bool alignCenter = true,
  }) => pw.Container(
    constraints: const pw.BoxConstraints(minHeight: 24),
    padding: EnterpriseDocumentPresentation.tableCellPadding,
    alignment: alignCenter
        ? pw.Alignment.center
        : (arabic ? pw.Alignment.centerRight : pw.Alignment.centerLeft),
    child: PdfTextSupport.text(
      value,
      textAlign: alignCenter
          ? pw.TextAlign.center
          : (arabic ? pw.TextAlign.right : pw.TextAlign.left),
      maxLines: 4,
      style: pw.TextStyle(
        font: regular,
        fontSize: EnterpriseDocumentPresentation.tableBodySize,
      ),
    ),
  );
}
