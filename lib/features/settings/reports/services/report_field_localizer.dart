import 'package:quality_line_erp/core/documents/document_nomenclature.dart';
import 'package:quality_line_erp/core/localization/domain_translation_catalog.dart';

/// Localizes database-safe report section and field identifiers without
/// changing the persisted keys used by saved report presets.
class ReportFieldLocalizer {
  const ReportFieldLocalizer._();

  static bool isTechnicalField(String value) {
    final normalized = value
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
        .toLowerCase();
    if (normalized == 'id') return true;
    const retiredCatalogFields = <String>{
      'productcode',
      'sku',
      'internalcode',
      'serialnumber',
      'nameen',
      'englishname',
    };
    return normalized.endsWith('id') ||
        normalized.contains('uuid') ||
        normalized.contains('payload') ||
        normalized.contains('rawdata') ||
        normalized.contains('verification') ||
        retiredCatalogFields.contains(normalized);
  }

  static String localize(String value, String language) {
    final bilingual = value.split(' / ');
    final selected = bilingual.length > 1
        ? (language == 'ar' ? bilingual.last : bilingual.first)
        : value;
    final normalized = selected.trim();
    final field = _labels[normalized];
    if (field != null) return field[language] ?? field['en'] ?? normalized;

    final sharedField = DocumentNomenclature.field(
      normalized,
      arabic: language == 'ar',
    );
    if (sharedField != normalized) return sharedField;

    final sharedDocument = DocumentNomenclature.documentType(
      normalized,
      arabic: language == 'ar',
    );
    if (sharedDocument != normalized) return sharedDocument;

    final translated = DomainTranslationCatalog.translate(normalized, language);
    if (translated != normalized) return translated;

    final humanized = normalized
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match.group(1)} ${match.group(2)}',
        )
        .replaceAll('_', ' ')
        .trim();
    if (humanized.isEmpty) return normalized;
    if (language == 'ar') return humanized;
    return humanized[0].toUpperCase() + humanized.substring(1);
  }

  static const Map<String, Map<String, String>> _labels = {
    'action': {'ar': 'الإجراء', 'en': 'Action'},
    'address': {'ar': 'العنوان', 'en': 'Address'},
    'amount': {'ar': 'المبلغ', 'en': 'Amount'},
    'amountIqd': {'ar': 'المبلغ بالدينار', 'en': 'Amount IQD'},
    'amountUsd': {'ar': 'المبلغ بالدولار', 'en': 'Amount USD'},
    'availableQuantity': {'ar': 'الكمية المتاحة', 'en': 'Available quantity'},
    'averageUnitCost': {'ar': 'متوسط كلفة الوحدة', 'en': 'Average unit cost'},
    'brand': {'ar': 'الماركة', 'en': 'Brand'},
    'cashAccount': {'ar': 'الصندوق', 'en': 'Cash account'},
    'cashAmount': {'ar': 'مبلغ الصندوق', 'en': 'Cash amount'},
    'category': {'ar': 'الفئة', 'en': 'Category'},
    'chassis': {'ar': 'رقم الهيكل', 'en': 'Chassis'},
    'color': {'ar': 'اللون', 'en': 'Color'},
    'createdAt': {'ar': 'تاريخ الإنشاء', 'en': 'Created at'},
    'createdBy': {'ar': 'أنشأ بواسطة', 'en': 'Created by'},
    'currency': {'ar': 'العملة', 'en': 'Currency'},
    'customer': {'ar': 'العميل', 'en': 'Customer'},
    'description': {'ar': 'الوصف', 'en': 'Description'},
    'discount': {'ar': 'الخصم', 'en': 'Discount'},
    'documentNumber': {'ar': 'رقم المستند', 'en': 'Document number'},
    'documentType': {'ar': 'نوع المستند', 'en': 'Document type'},
    'email': {'ar': 'البريد الإلكتروني', 'en': 'Email'},
    'entryDate': {'ar': 'تاريخ القيد', 'en': 'Entry date'},
    'entryNumber': {'ar': 'رقم القيد', 'en': 'Entry number'},
    'exchangeDifference': {'ar': 'فرق الصرف', 'en': 'Exchange difference'},
    'exchangeRate': {'ar': 'سعر الصرف', 'en': 'Exchange rate'},
    'expectedIncoming': {'ar': 'الوارد المتوقع', 'en': 'Expected incoming'},
    'expectedOutgoing': {'ar': 'الصادر المتوقع', 'en': 'Expected outgoing'},
    'fromStatus': {'ar': 'الحالة السابقة', 'en': 'From status'},
    'fromWarehouse': {'ar': 'مخزن المصدر', 'en': 'From warehouse'},
    'invoiceAmount': {'ar': 'مبلغ الفاتورة', 'en': 'Invoice amount'},
    'invoiceCurrency': {'ar': 'عملة الفاتورة', 'en': 'Invoice currency'},
    'invoiceNumber': {'ar': 'رقم الفاتورة', 'en': 'Invoice number'},
    'itemDetails': {'ar': 'تفاصيل البند', 'en': 'Item details'},
    'itemType': {'ar': 'نوع البند', 'en': 'Item type'},
    'lineTotal': {'ar': 'إجمالي البند', 'en': 'Line total'},
    'maintenanceCost': {'ar': 'كلفة الصيانة', 'en': 'Maintenance cost'},
    'model': {'ar': 'الموديل', 'en': 'Model'},
    'module': {'ar': 'الوحدة', 'en': 'Module'},
    'movementDate': {'ar': 'تاريخ الحركة', 'en': 'Movement date'},
    'movementNumber': {'ar': 'رقم الحركة', 'en': 'Movement number'},
    'movementType': {'ar': 'نوع الحركة', 'en': 'Movement type'},
    'name': {'ar': 'الاسم', 'en': 'Name'},
    'notes': {'ar': 'الملاحظات', 'en': 'Notes'},
    'orderNumber': {'ar': 'رقم الأمر', 'en': 'Order number'},
    'opportunityNumber': {'ar': 'رقم الفرصة', 'en': 'Opportunity number'},
    'title': {'ar': 'عنوان الفرصة', 'en': 'Opportunity title'},
    'source': {'ar': 'مصدر الفرصة', 'en': 'Opportunity source'},
    'assignedUser': {'ar': 'المسؤول', 'en': 'Assigned user'},
    'expectedValue': {'ar': 'القيمة المتوقعة', 'en': 'Expected value'},
    'salesOrderNumber': {'ar': 'رقم أمر البيع', 'en': 'Sales order number'},
    'followUpDate': {'ar': 'تاريخ المتابعة', 'en': 'Follow-up date'},
    'closedAt': {'ar': 'تاريخ الإغلاق', 'en': 'Closed at'},
    'count': {'ar': 'العدد', 'en': 'Count'},
    'paid': {'ar': 'المدفوع', 'en': 'Paid'},
    'party': {'ar': 'الطرف', 'en': 'Party'},
    'paymentCurrency': {'ar': 'عملة الدفع', 'en': 'Payment currency'},
    'paymentDate': {'ar': 'تاريخ الدفعة', 'en': 'Payment date'},
    'performedAt': {'ar': 'وقت التنفيذ', 'en': 'Performed at'},
    'performedBy': {'ar': 'المنفذ', 'en': 'Performed by'},
    'phone': {'ar': 'الهاتف', 'en': 'Phone'},
    'plateNumber': {'ar': 'رقم اللوحة', 'en': 'Plate number'},
    'product': {'ar': 'المنتج', 'en': 'Product'},
    'productName': {'ar': 'اسم المنتج', 'en': 'Product name'},
    'purchasePrice': {'ar': 'سعر الشراء', 'en': 'Purchase price'},
    'quantity': {'ar': 'الكمية', 'en': 'Quantity'},
    'reason': {'ar': 'السبب', 'en': 'Reason'},
    'referenceType': {'ar': 'نوع المرجع', 'en': 'Reference type'},
    'remaining': {'ar': 'المتبقي', 'en': 'Remaining'},
    'reservedQuantity': {'ar': 'الكمية المحجوزة', 'en': 'Reserved quantity'},
    'salePrice': {'ar': 'سعر البيع', 'en': 'Sale price'},
    'status': {'ar': 'الحالة', 'en': 'Status'},
    'stockValue': {'ar': 'قيمة المخزون', 'en': 'Stock value'},
    'subtotal': {'ar': 'المجموع الفرعي', 'en': 'Subtotal'},
    'supplier': {'ar': 'المورد', 'en': 'Supplier'},
    'taxNumber': {'ar': 'الرقم الضريبي', 'en': 'Tax number'},
    'toStatus': {'ar': 'الحالة الجديدة', 'en': 'To status'},
    'toWarehouse': {'ar': 'مخزن الهدف', 'en': 'To warehouse'},
    'total': {'ar': 'الإجمالي', 'en': 'Total'},
    'totalCredit': {'ar': 'إجمالي الدائن', 'en': 'Total credit'},
    'totalDebit': {'ar': 'إجمالي المدين', 'en': 'Total debit'},
    'transactionDate': {'ar': 'تاريخ الحركة المالية', 'en': 'Transaction date'},
    'transferDate': {'ar': 'تاريخ النقل', 'en': 'Transfer date'},
    'transferNumber': {'ar': 'رقم النقل', 'en': 'Transfer number'},
    'type': {'ar': 'النوع', 'en': 'Type'},
    'unitCost': {'ar': 'كلفة الوحدة', 'en': 'Unit cost'},
    'unitPrice': {'ar': 'سعر الوحدة', 'en': 'Unit price'},
    'updatedAt': {'ar': 'تاريخ التحديث', 'en': 'Updated at'},
    'updatedBy': {'ar': 'آخر تعديل بواسطة', 'en': 'Updated by'},
    'vehicle': {'ar': 'السيارة', 'en': 'Vehicle'},
    'voucherNumber': {'ar': 'رقم السند', 'en': 'Voucher number'},
    'warehouse': {'ar': 'المخزن', 'en': 'Warehouse'},
    'year': {'ar': 'السنة', 'en': 'Year'},
    'accountCode': {'ar': 'رمز الحساب', 'en': 'Account code'},
    'accountName': {'ar': 'اسم الحساب', 'en': 'Account name'},
    'code': {'ar': 'الرمز', 'en': 'Code'},
    'credit': {'ar': 'دائن', 'en': 'Credit'},
    'debit': {'ar': 'مدين', 'en': 'Debit'},
    'expectedGrossProfitPerUnit': {
      'ar': 'الربح المتوقع للوحدة',
      'en': 'Expected gross profit per unit',
    },
    'expectedQuantity': {'ar': 'الرصيد المتوقع', 'en': 'Expected quantity'},
    'identityNumber': {'ar': 'رقم الهوية', 'en': 'Identity number'},
    'isActive': {'ar': 'فعال', 'en': 'Active'},
    'landedCost': {'ar': 'تكلفة الوصول', 'en': 'Landed cost'},
    'minQuantity': {'ar': 'حد إعادة الطلب', 'en': 'Minimum quantity'},
    'paymentNumber': {'ar': 'رقم الدفعة', 'en': 'Payment number'},
    'reference': {'ar': 'المرجع', 'en': 'Reference'},
    'referenceNumber': {'ar': 'رقم المرجع', 'en': 'Reference number'},
    'linkedDocument': {'ar': 'المستند المرتبط', 'en': 'Linked document'},
    'linkedRecord': {'ar': 'السجل المرتبط', 'en': 'Linked record'},
    'approvedBy': {'ar': 'صُدّق بواسطة', 'en': 'Approved by'},
    'approvedAt': {'ar': 'تاريخ ووقت التصديق', 'en': 'Approved at'},
    'time': {'ar': 'الوقت', 'en': 'Time'},
    'paymentType': {'ar': 'نوع الدفعة', 'en': 'Payment type'},
    'settlementAccountId': {'ar': 'حساب التسوية', 'en': 'Settlement account'},
    'settlementMode': {'ar': 'طريقة التسوية', 'en': 'Settlement mode'},
    'unit': {'ar': 'وحدة القياس', 'en': 'Unit'},
  };
}
