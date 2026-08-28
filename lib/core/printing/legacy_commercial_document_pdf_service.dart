import 'dart:typed_data';

import 'package:quality_line_erp/core/exporting/pdf_print_service.dart';

import 'package:quality_line_erp/core/printing/enterprise_document_pdf_service.dart';
import 'package:quality_line_erp/features/purchases/models/purchase_item_model.dart';
import 'package:quality_line_erp/features/purchases/models/purchase_model.dart';
import 'package:quality_line_erp/features/sales/models/sale_model.dart';

class LegacyCommercialDocumentPdfService {
  const LegacyCommercialDocumentPdfService();

  Future<void> printSale({
    required SaleModel sale,
    required String customerName,
    required String carName,
    String language = 'ar',
  }) async {
    final bytes = await buildSale(
      sale: sale,
      customerName: customerName,
      carName: carName,
      language: language,
    );
    await PdfPrintService.print(
      fileName: 'sale-${sale.invoiceNumber}.pdf',
      bytes: bytes,
    );
  }

  Future<Uint8List> buildSale({
    required SaleModel sale,
    required String customerName,
    required String carName,
    String language = 'ar',
  }) => const EnterpriseDocumentPdfService().build(
    purchase: false,
    language: language,
    order: <String, Object?>{
      'documentType': 'فاتورة بيع',
      'documentReference': sale.id,
      'orderNumber': sale.invoiceNumber,
      'invoiceNumber': sale.invoiceNumber,
      'orderDate': sale.saleDate,
      'documentDate': sale.saleDate,
      'partnerName': customerName,
      'customerName': customerName,
      'currency': sale.currencyCode,
      'paymentMethod': sale.paymentMethod,
      'subtotal': sale.salePrice,
      'total': sale.salePrice,
      'paidAmount': sale.paidAmount,
      'remainingAmount': sale.remainingAmount,
      'status': sale.remainingAmount <= 0
          ? 'paid'
          : (sale.paidAmount > 0 ? 'partial' : 'unpaid'),
      'notes': sale.notes,
      'createdBy': sale.createdByUserName,
    },
    items: <Map<String, Object?>>[
      <String, Object?>{
        'itemType': 'vehicle',
        'name': carName,
        'description': sale.isResale ? 'إعادة بيع سيارة' : 'بيع سيارة',
        'quantity': 1,
        'unitPrice': sale.salePrice,
        'lineTotal': sale.salePrice,
        'currency': sale.currencyCode,
      },
    ],
    logistics: const <Map<String, Object?>>[],
    invoices: <Map<String, Object?>>[
      <String, Object?>{
        'invoiceNumber': sale.invoiceNumber,
        'invoiceDate': sale.saleDate,
        'total': sale.salePrice,
        'paid': sale.paidAmount,
        'remaining': sale.remainingAmount,
        'currency': sale.currencyCode,
        'status': sale.remainingAmount <= 0
            ? 'paid'
            : (sale.paidAmount > 0 ? 'partial' : 'unpaid'),
      },
    ],
    payments: const <Map<String, Object?>>[],
    movements: const <Map<String, Object?>>[],
    journalEntries: const <Map<String, Object?>>[],
    auditTrail: <Map<String, Object?>>[
      <String, Object?>{
        'action': 'print',
        'createdAt': DateTime.now().toIso8601String(),
        'userName': sale.createdByUserName ?? '',
      },
    ],
  );

  Future<void> printPurchase({
    required PurchaseModel purchase,
    required List<PurchaseItemModel> items,
    String language = 'ar',
  }) async {
    final bytes = await buildPurchase(
      purchase: purchase,
      items: items,
      language: language,
    );
    await PdfPrintService.print(
      fileName: 'purchase-${purchase.invoiceNumber}.pdf',
      bytes: bytes,
    );
  }

  Future<Uint8List> buildPurchase({
    required PurchaseModel purchase,
    required List<PurchaseItemModel> items,
    String language = 'ar',
  }) => const EnterpriseDocumentPdfService().build(
    purchase: true,
    language: language,
    order: <String, Object?>{
      'documentType': 'فاتورة شراء',
      'documentReference': purchase.id,
      'orderNumber': purchase.invoiceNumber,
      'invoiceNumber': purchase.invoiceNumber,
      'orderDate': purchase.purchaseDate.toIso8601String(),
      'documentDate': purchase.purchaseDate.toIso8601String(),
      'partnerName': purchase.supplierName,
      'supplierName': purchase.supplierName,
      'currency': purchase.currencyCode,
      'paymentMethod': purchase.paymentMethod,
      'subtotal': purchase.totalAmount,
      'total': purchase.totalAmount,
      'paidAmount': purchase.paidAmount,
      'remainingAmount': purchase.remainingAmount,
      'status': purchase.isPaid
          ? 'paid'
          : (purchase.isPartial ? 'partial' : 'unpaid'),
      'notes': purchase.notes,
    },
    items: items
        .map(
          (item) => <String, Object?>{
            'itemType': 'vehicle',
            'code': item.chassisNumber,
            'name': item.carName,
            'chassis': item.chassisNumber,
            'description': item.notes ?? '',
            'quantity': 1,
            'unitPrice': item.purchasePrice,
            'additionalCosts': item.additionalCosts,
            'lineTotal': item.totalCost,
            'currency': purchase.currencyCode,
          },
        )
        .toList(growable: false),
    logistics: const <Map<String, Object?>>[],
    invoices: <Map<String, Object?>>[
      <String, Object?>{
        'invoiceNumber': purchase.invoiceNumber,
        'invoiceDate': purchase.purchaseDate.toIso8601String(),
        'total': purchase.totalAmount,
        'paid': purchase.paidAmount,
        'remaining': purchase.remainingAmount,
        'currency': purchase.currencyCode,
        'status': purchase.isPaid
            ? 'paid'
            : (purchase.isPartial ? 'partial' : 'unpaid'),
      },
    ],
    payments: const <Map<String, Object?>>[],
    movements: const <Map<String, Object?>>[],
    journalEntries: const <Map<String, Object?>>[],
    auditTrail: <Map<String, Object?>>[
      <String, Object?>{
        'action': 'print',
        'createdAt': DateTime.now().toIso8601String(),
      },
    ],
  );
}
