import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/exporting/browser_download_lifecycle.dart';
import 'package:quality_line_erp/core/exporting/export_payload_validator.dart';
import 'package:quality_line_erp/core/printing/enterprise_document_pdf_service.dart';
import 'package:quality_line_erp/core/printing/maintenance_document_pdf_service.dart';
import 'package:quality_line_erp/core/printing/warehouse_transfer_pdf_service.dart';
import 'package:quality_line_erp/features/maintenance/models/maintenance_order_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('shared PDF delivery boundary', () {
    test(
      'rejects empty and corrupt PDF payloads before adapter invocation',
      () {
        expect(
          () => ExportPayloadValidator.validate(
            fileName: 'order.pdf',
            bytes: Uint8List(0),
            mimeType: 'application/pdf',
          ),
          throwsStateError,
        );
        expect(
          () => ExportPayloadValidator.validate(
            fileName: 'order.pdf',
            bytes: Uint8List.fromList(const [1, 2, 3, 4, 5]),
            mimeType: 'application/pdf',
          ),
          throwsStateError,
        );
      },
    );

    test('normalizes a valid PDF filename exactly once', () {
      final bytes = Uint8List.fromList('%PDF-1.7'.codeUnits);
      expect(
        ExportPayloadValidator.validate(
          fileName: 'SO-57',
          bytes: bytes,
          mimeType: 'application/pdf',
        ),
        'SO-57.pdf',
      );
      expect(
        ExportPayloadValidator.validate(
          fileName: 'SO-57.PDF',
          bytes: bytes,
          mimeType: 'application/pdf',
        ),
        'SO-57.PDF',
      );
    });

    test('one browser request clicks once and always cleans up', () async {
      var attached = 0;
      var clicked = 0;
      var detached = 0;
      var revoked = 0;

      triggerBrowserDownload(
        attach: () => attached++,
        click: () => clicked++,
        detach: () => detached++,
        revoke: () => revoked++,
        revokeDelay: Duration.zero,
      );
      await Future<void>.delayed(Duration.zero);

      expect(attached, 1);
      expect(clicked, 1);
      expect(detached, 1);
      expect(revoked, 1);
    });
  });

  for (final purchase in const [false, true]) {
    for (final language in const ['en', 'ar']) {
      test(
        '${purchase ? 'purchase' : 'sales'} order builds in $language with large linked workflow data',
        () async {
          final currency = purchase ? 'IQD' : 'USD';
          final items = List<Map<String, Object?>>.generate(
            36,
            (index) => <String, Object?>{
              'itemType': index.isEven ? 'product' : 'vehicle',
              'description': language == 'ar'
                  ? 'اسم بند عربي طويل للاختبار رقم $index'
                  : 'Long wrapping document item number $index',
              'quantity': index + 1,
              'unitPrice': 1250.5 + index,
              'unitCost': 1250000 + index,
              'lineTotal': (index + 1) * 1250.5,
              'warehouseName': index.isEven ? 'Main' : 'Secondary',
              'status': 'partial',
            },
          );
          final bytes = await const EnterpriseDocumentPdfService().build(
            purchase: purchase,
            language: language,
            order: <String, Object?>{
              'orderNumber': purchase ? 'PO-57-001' : 'SO-57-001',
              'partnerName': language == 'ar'
                  ? 'شركة العميل أو المورد التجريبية'
                  : 'Example customer or supplier',
              'status': 'partial',
              'currency': currency,
              'subtotal': 1500000,
              'discount': 50000,
              'total': 1450000,
              'createdAt': '2026-08-12',
              'notes': language == 'ar'
                  ? 'ملاحظات طويلة قابلة للالتفاف والطباعة عبر الصفحات.'
                  : 'Long notes that must wrap and remain printable.',
            },
            items: items,
            logistics: <Map<String, Object?>>[
              <String, Object?>{
                purchase ? 'receiptNumber' : 'deliveryNumber': 'WH-57-001',
                purchase ? 'receiptDate' : 'deliveryDate': '2026-08-12',
                'warehouseName': 'Main',
                'quantity': 18,
                'status': 'approved',
              },
              <String, Object?>{
                purchase ? 'receiptNumber' : 'deliveryNumber': 'WH-57-002',
                purchase ? 'receiptDate' : 'deliveryDate': '2026-08-12',
                'warehouseName': 'Secondary',
                'quantity': 9,
                'status': 'draft',
              },
            ],
            invoices: <Map<String, Object?>>[
              <String, Object?>{
                'invoiceNumber': purchase ? 'PI-57-001' : 'SI-57-001',
                'invoiceDate': '2026-08-12',
                'currency': currency,
                'total': 900000,
                'paidAmount': 400000,
                'remainingAmount': 500000,
                'paymentStatus': 'partial',
              },
            ],
            payments: const <Map<String, Object?>>[],
            movements: const <Map<String, Object?>>[],
            journalEntries: const <Map<String, Object?>>[],
            auditTrail: const <Map<String, Object?>>[],
            reconciliation: <Map<String, Object?>>[
              <String, Object?>{
                'description': language == 'ar'
                    ? 'بند مطابقة الكميات'
                    : 'Quantity reconciliation line',
                'orderedQuantity': 36,
                'operationalQuantity': 27,
                'invoicedQuantity': 18,
                'remainingOperational': 9,
                'remainingInvoice': 18,
                'status': 'partial',
              },
            ],
          );

          _expectPdf(bytes);
          expect(bytes.length, greaterThan(10000));
        },
      );
    }
  }

  for (final arabic in const [false, true]) {
    test(
      'maintenance materials and labor build in ${arabic ? 'ar' : 'en'}',
      () async {
        final order = MaintenanceOrderModel(
          id: 'maintenance-id',
          orderNumber: 'MO-57-001',
          carId: 'car-id',
          carName: arabic
              ? 'تويوتا لاندكروزر 2025'
              : 'Toyota Land Cruiser 2025',
          customerId: 'customer-id',
          customerName: arabic ? 'عميل الصيانة' : 'Maintenance customer',
          warehouseId: 'warehouse-id',
          isSoldCar: true,
          pricingType: 'paid',
          status: 'partial',
          laborCost: 150,
          partsCost: 350,
          totalCost: 500,
          salePrice: 650,
          profit: 150,
          carCostAdded: 0,
          maintenanceDate: '2026-08-12',
          notes: arabic
              ? 'فحص شامل وصيانة دورية'
              : 'Full inspection and periodic service',
          currencyCode: 'USD',
          workflowStage: 'invoice_approved',
          paidAmount: 300,
          invoiceNumber: 'MI-57-001',
          stockIssueNumber: 'MSI-57-001',
        );
        final lines = List<MaintenanceLineModel>.generate(
          30,
          (index) => MaintenanceLineModel(
            id: 'line-$index',
            productId: 'product-$index',
            productName: arabic
                ? 'مادة أو خدمة صيانة طويلة رقم $index'
                : 'Long maintenance material or labor line $index',
            warehouseId: index.isEven ? 'warehouse-id' : null,
            warehouseName: index.isEven ? 'Main warehouse' : null,
            quantity: index + 1,
            unitCost: 5,
            unitPrice: 7,
            lineType: index.isEven ? 'stock' : 'service',
          ),
        );

        final bytes = await const MaintenanceDocumentPdfService().build(
          order: order,
          lines: lines,
          arabic: arabic,
        );
        _expectPdf(bytes);
        expect(bytes.length, greaterThan(10000));
      },
    );
  }

  for (final language in const ['en', 'ar']) {
    test('warehouse product and car transfer builds in $language', () async {
      final printed = <String>[];
      final bytes = await runZoned(
        () => const WarehouseTransferPdfService().build(
          language: language,
          documentNumber: 'WT-57-001',
          transferDate: '2026-08-12',
          sourceWarehouse: const <String, Object?>{
            'id': 'source-id',
            'code': 'WH-01',
            'name': 'Main warehouse',
          },
          destinationWarehouse: const <String, Object?>{
            'id': 'destination-id',
            'code': 'WH-02',
            'name': 'Secondary warehouse',
          },
          preparedBy: language == 'ar' ? 'مستخدم الاختبار' : 'Test user',
          notes: language == 'ar'
              ? 'نقل تشغيلي معتمد'
              : 'Approved operational transfer',
          items: <Map<String, Object?>>[
            const <String, Object?>{
              'code': 'PR-001',
              'name': 'Spare part',
              'details': 'Product transfer',
              'quantity': 12,
              'unit': 'Piece',
              'cost': '15.00',
              'currency': 'USD',
            },
            <String, Object?>{
              'code': 'CAR-001',
              'name': language == 'ar' ? 'سيارة اختبار' : 'Test vehicle',
              'details': 'VIN: TESTVIN57',
              'quantity': 1,
              'unit': language == 'ar' ? 'سيارة' : 'Vehicle',
              'cost': '25000000',
              'currency': 'IQD',
            },
          ],
        ),
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, message) => printed.add(message),
        ),
      );
      _expectPdf(bytes);
      expect(bytes.length, greaterThan(5000));
      expect(
        printed.where((message) => message.contains('Unicode support')),
        isEmpty,
      );
    });
  }
}

void _expectPdf(Uint8List bytes) {
  expect(bytes.length, greaterThan(1000));
  expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
}
