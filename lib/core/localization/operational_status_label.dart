import 'app_localizations.dart';

/// Converts persisted workflow/status codes into user-facing localized labels.
/// Unknown values are still passed through the application translation layer.
String operationalStatusLabel(Object? value) {
  final raw = value?.toString().trim() ?? '';
  final normalized = raw
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_');
  final arabic = switch (normalized) {
    '' => 'غير محدد',
    'all' => 'الكل',
    'defined' || 'identified' => 'معرفة',
    'purchase_pending' ||
    'pending_purchase' ||
    'under_purchase' => 'قيد الشراء',
    'available' || 'in_stock' => 'متوفرة',
    'damaged' || 'scrap' || 'تالفة' || 'تالف' => 'تالفة',
    'sale_pending' || 'pending_sale' || 'under_sale' => 'قيد البيع',
    'sold' => 'مباعة',
    'draft' => 'مسودة',
    'approved' => 'مصدق',
    'cancelled' || 'canceled' => 'ملغى',
    'paid' => 'مسدد',
    'partial' || 'partially_paid' => 'مسدد جزئياً',
    'pending' => 'قيد الانتظار',
    'completed' || 'complete' => 'مكتمل',
    'reversed' => 'معكوس',
    'active' => 'نشط',
    'inactive' => 'غير نشط',
    'overdue' => 'متأخر',
    'due' => 'مستحق',
    'open' => 'مفتوح',
    'closed' => 'مغلق',
    _ => raw,
  };
  return AppTranslation.translate(arabic);
}
