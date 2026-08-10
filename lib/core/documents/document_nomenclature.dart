/// Shared bilingual terminology for every operational document.
///
/// Keeping these labels in one catalog prevents the same concept from being
/// called "code", "reference", "number" or a legacy abbreviation in
/// different screens, exports and printed documents.
abstract final class DocumentNomenclature {
  static String text({
    required bool arabic,
    required String arabicText,
    required String englishText,
  }) => arabic ? arabicText : englishText;

  static String commercialOrder({
    required bool purchase,
    required bool arabic,
  }) => purchase
      ? text(
          arabic: arabic,
          arabicText: 'أمر شراء',
          englishText: 'Purchase Order',
        )
      : text(arabic: arabic, arabicText: 'أمر بيع', englishText: 'Sales Order');

  static String commercialDraft({
    required bool purchase,
    required bool arabic,
  }) => purchase
      ? text(
          arabic: arabic,
          arabicText: 'مسودة شراء',
          englishText: 'Purchase Draft',
        )
      : text(
          arabic: arabic,
          arabicText: 'مسودة بيع',
          englishText: 'Sales Draft',
        );

  static String warehouseStage({
    required bool purchase,
    required bool arabic,
  }) => purchase
      ? text(
          arabic: arabic,
          arabicText: 'إشعار استلام مخزني للشراء',
          englishText: 'Warehouse Receipt',
        )
      : text(
          arabic: arabic,
          arabicText: 'إذن تجهيز مخزني للبيع',
          englishText: 'Warehouse Issue',
        );

  static String invoice({required bool purchase, required bool arabic}) =>
      purchase
      ? text(
          arabic: arabic,
          arabicText: 'فاتورة شراء',
          englishText: 'Purchase Invoice',
        )
      : text(
          arabic: arabic,
          arabicText: 'فاتورة بيع',
          englishText: 'Sales Invoice',
        );

  static String partnerPayment({
    required bool purchase,
    required bool arabic,
  }) => purchase
      ? text(
          arabic: arabic,
          arabicText: 'سند صرف دفعة مورد',
          englishText: 'Supplier Payment',
        )
      : text(
          arabic: arabic,
          arabicText: 'سند قبض دفعة عميل',
          englishText: 'Customer Payment',
        );

  static String maintenanceOrder({required bool arabic}) => text(
    arabic: arabic,
    arabicText: 'أمر صيانة',
    englishText: 'Maintenance Order',
  );

  static String maintenanceIssue({required bool arabic}) => text(
    arabic: arabic,
    arabicText: 'إذن صرف مواد الصيانة',
    englishText: 'Maintenance Parts Issue',
  );

  static String maintenanceInvoice({required bool arabic}) => text(
    arabic: arabic,
    arabicText: 'فاتورة صيانة',
    englishText: 'Maintenance Invoice',
  );

  static String maintenancePayment({required bool arabic}) => text(
    arabic: arabic,
    arabicText: 'سند قبض دفعة صيانة',
    englishText: 'Maintenance Payment',
  );

  static String documentType(String key, {required bool arabic}) {
    final normalized = key
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z]'), '')
        .toLowerCase();
    return switch (normalized) {
      'salesorder' ||
      'saleorder' => commercialOrder(purchase: false, arabic: arabic),
      'purchaseorder' => commercialOrder(purchase: true, arabic: arabic),
      'salesdraft' => commercialDraft(purchase: false, arabic: arabic),
      'purchasedraft' => commercialDraft(purchase: true, arabic: arabic),
      'delivery' ||
      'warehouseissue' => warehouseStage(purchase: false, arabic: arabic),
      'receipt' ||
      'warehousereceipt' => warehouseStage(purchase: true, arabic: arabic),
      'salesinvoice' => invoice(purchase: false, arabic: arabic),
      'purchaseinvoice' => invoice(purchase: true, arabic: arabic),
      'customerpayment' => partnerPayment(purchase: false, arabic: arabic),
      'supplierpayment' => partnerPayment(purchase: true, arabic: arabic),
      'maintenanceorder' => maintenanceOrder(arabic: arabic),
      'maintenanceissue' => maintenanceIssue(arabic: arabic),
      'maintenanceinvoice' => maintenanceInvoice(arabic: arabic),
      'maintenancepayment' => maintenancePayment(arabic: arabic),
      'warehousemovement' => text(
        arabic: arabic,
        arabicText: 'حركة مخزنية',
        englishText: 'Warehouse Movement',
      ),
      'stocktransfer' || 'inventorytransfer' => text(
        arabic: arabic,
        arabicText: 'أمر نقل مخزني',
        englishText: 'Stock Transfer Order',
      ),
      'stockscrap' || 'inventoryscrap' || 'scrap' => text(
        arabic: arabic,
        arabicText: 'محضر إتلاف مخزني',
        englishText: 'Inventory Scrap Order',
      ),
      'inventoryinput' || 'stockinput' || 'inventoryadjustment' => text(
        arabic: arabic,
        arabicText: 'سند إدخال أو تسوية مخزنية',
        englishText: 'Inventory Input',
      ),
      'journalentry' || 'accountingentry' => text(
        arabic: arabic,
        arabicText: 'قيد يومية محاسبي',
        englishText: 'Journal Entry',
      ),
      'vehicletransfer' => text(
        arabic: arabic,
        arabicText: 'أمر تحويل سيارة بين المخازن',
        englishText: 'Vehicle Warehouse Transfer',
      ),
      'producttransfer' => text(
        arabic: arabic,
        arabicText: 'أمر تحويل منتجات بين المخازن',
        englishText: 'Inventory Transfer',
      ),
      'cashreceipt' => text(
        arabic: arabic,
        arabicText: 'سند قبض',
        englishText: 'Receipt Voucher',
      ),
      'cashpayment' => text(
        arabic: arabic,
        arabicText: 'سند صرف',
        englishText: 'Payment Voucher',
      ),
      _ => key,
    };
  }

  /// Stable, readable prefixes used by documents, links, exports, and journals.
  static String prefix(String key) {
    final normalized = key
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z]'), '')
        .toLowerCase();
    return switch (normalized) {
      'salesorder' => 'SO',
      'salesdelivery' || 'delivery' || 'warehouseissue' => 'SD',
      'salesinvoice' => 'SI',
      'customerpayment' || 'salespayment' => 'SR',
      'purchaseorder' => 'PO',
      'purchasereceipt' || 'receipt' || 'warehousereceipt' => 'PR',
      'purchaseinvoice' => 'PI',
      'supplierpayment' || 'purchasepayment' => 'PP',
      'maintenanceorder' => 'MO',
      'maintenanceissue' => 'MSI',
      'maintenanceinvoice' => 'MINV',
      'maintenancepayment' => 'MP',
      'stocktransfer' || 'inventorytransfer' => 'ST',
      'stockscrap' || 'inventoryscrap' || 'scrap' => 'SC',
      'inventoryinput' || 'stockinput' || 'inventoryadjustment' => 'IA',
      'journalentry' || 'accountingentry' => 'JE',
      _ => 'DOC',
    };
  }

  static String field(String key, {required bool arabic}) {
    final normalized = key.trim().replaceAll('_', '').toLowerCase();
    final pair = _fieldLabels[normalized];
    if (pair == null) return key;
    return arabic ? pair.$1 : pair.$2;
  }

  static const Map<String, (String, String)> _fieldLabels = {
    'code': ('الرمز', 'Code'),
    'reference': ('المرجع', 'Reference'),
    'referencenumber': ('رقم المرجع', 'Reference Number'),
    'documentnumber': ('رقم المستند', 'Document Number'),
    'ordernumber': ('رقم الأمر', 'Order Number'),
    'invoicenumber': ('رقم الفاتورة', 'Invoice Number'),
    'movementnumber': ('رقم الحركة', 'Movement Number'),
    'transfernumber': ('رقم التحويل', 'Transfer Number'),
    'paymentnumber': ('رقم الدفعة', 'Payment Number'),
    'vouchernumber': ('رقم السند', 'Voucher Number'),
    'entrynumber': ('رقم القيد', 'Journal Entry Number'),
    'opportunitynumber': ('رقم الفرصة', 'Opportunity Number'),
    'date': ('التاريخ', 'Date'),
    'time': ('الوقت', 'Time'),
    'datetime': ('التاريخ والوقت', 'Date and Time'),
    'currency': ('العملة', 'Currency'),
    'exchangerate': ('سعر الصرف', 'Exchange Rate'),
    'status': ('الحالة', 'Status'),
    'notes': ('الملاحظات', 'Notes'),
    'linkedrecord': ('السجل المرتبط', 'Linked Record'),
    'linkeddocument': ('المستند المرتبط', 'Linked Document'),
    'createdby': ('أُنشئ بواسطة', 'Created By'),
    'approvedby': ('صُدّق بواسطة', 'Approved By'),
    'updatedby': ('آخر تعديل بواسطة', 'Last Updated By'),
    'warehouse': ('المخزن', 'Warehouse'),
    'vehicle': ('السيارة', 'Vehicle'),
    'product': ('المادة المخزنية', 'Inventory Item'),
    'customer': ('العميل', 'Customer'),
    'supplier': ('المورد', 'Supplier'),
    'quantity': ('الكمية', 'Quantity'),
    'unitprice': ('سعر الوحدة', 'Unit Price'),
    'unitcost': ('كلفة الوحدة', 'Unit Cost'),
    'total': ('الإجمالي', 'Total'),
    'paid': ('المدفوع', 'Paid'),
    'remaining': ('المتبقي', 'Remaining'),
  };
}
