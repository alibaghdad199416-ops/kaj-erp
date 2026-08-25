import 'package:quality_line_erp/core/cloud/workflow_operation_exception.dart';

/// Converts internal exceptions into messages that are safe to display in the UI.
///
/// Technical details must remain in development logs and must not expose database
/// functions, constraints, UUIDs, RPC names, or raw exception types to users.
String userFacingError(
  Object error, {
  required bool isArabic,
  String? arabicFallback,
  String? englishFallback,
}) {
  if (error is WorkflowOperationException) {
    return error.localizedMessage(isArabic: isArabic);
  }
  final raw = error.toString().trim();
  final cleaned = raw
      .replaceFirst(RegExp(r'^(Exception|StateError|ArgumentError):\s*'), '')
      .replaceFirst(RegExp(r'^Bad state:\s*'), '')
      .trim();
  final normalized = cleaned.toLowerCase();

  if (normalized.contains('maintenance_insufficient_stock')) {
    final item = cleaned.contains(':') ? cleaned.split(':').last.trim() : '';
    return isArabic
        ? 'الرصيد المتاح غير كافٍ${item.isEmpty ? '' : ' للمادة $item'}. راجع المخزن والكمية المحجوزة ثم أعد المحاولة.'
        : 'Available stock is insufficient${item.isEmpty ? '' : ' for $item'}. Review warehouse stock and reserved quantity, then try again.';
  }

  if (normalized.contains('operational_account_parents_missing')) {
    return isArabic
        ? 'تعذر تجهيز الحسابات التشغيلية الافتراضية. حدّث دليل الحسابات ثم أعد التصديق.'
        : 'Default operational accounts could not be prepared. Refresh the chart of accounts and approve again.';
  }

  if (normalized.contains('inventory_item_not_found')) {
    return isArabic
        ? 'أحد بنود الأمر لم يعد موجودًا في المخزون. حدّث الأمر أو أعد اختيار البند.'
        : 'One order item no longer exists in inventory. Refresh the order or select the item again.';
  }

  if (normalized.contains('service_item_has_no_inventory_posting')) {
    return isArabic
        ? 'تمت إضافة خدمة ضمن مرحلة مخزنية. انقل الخدمة إلى بنود الخدمات واترك المخزن للمواد والسيارات.'
        : 'A service was included in an inventory stage. Keep services in service lines and warehouse stages for products and vehicles.';
  }

  if (normalized.contains('purchase_receipt_must_be_approved')) {
    return isArabic
        ? 'يجب أن يكون الاستلام المخزني في حالة مسودة قابلة للتصديق ثم يُعتمد من داخل الأمر.'
        : 'The warehouse receipt must be an approvable draft and then approved from the order.';
  }

  if (normalized.contains('payment_is_cashbox_owned') ||
      normalized.contains('delete_payment_from_cashbox_first')) {
    return isArabic
        ? 'الدفعة المالية مستقلة عن الأمر. احذف الدفعة نفسها من الصندوق عند الحاجة؛ حذف الأمر أو الفاتورة يُبقيها رصيدًا للطرف.'
        : 'The payment is independent from the order. Delete the payment itself from the cashbox when needed; deleting the order or invoice preserves it as partner balance.';
  }

  if (normalized.contains('advance_has_active_allocations')) {
    return isArabic
        ? 'هذا الرصيد مستخدم في فاتورة أو أمر نشط. احذف أو اعكس الارتباط الحالي قبل تعديل مبلغ الدفعة.'
        : 'This balance is allocated to an active invoice or order. Reverse the current allocation before editing the payment amount.';
  }

  if (normalized.contains('purchase_receipt_has_downstream_sales')) {
    return isArabic
        ? 'لا يمكن حذف الاستلام لأن بعض المواد المستلمة استُخدمت في بيع أو صرف لاحق. اعكس العملية اللاحقة أولًا.'
        : 'The receipt cannot be deleted because received items were consumed by a later sale or issue. Reverse the later operation first.';
  }

  if (normalized.contains('inventory_product_not_back_to_opening_state')) {
    return isArabic
        ? 'لم تعد المادة بعد إلى حالتها الافتتاحية أو ما زالت لها روابط بيع أو شراء أو نقل فعالة. حدّث الصفحة واعكس الروابط الفعالة ثم أعد المحاولة.'
        : 'The item has not returned to its opening state or still has active sales, purchase, or transfer links. Refresh, reverse the active links, and try again.';
  }

  if (normalized.contains('workflow_component_type_mismatch')) {
    return isArabic
        ? 'نوع المرحلة لا يطابق المستند المحدد. حدّث الأمر ثم اختر المرحلة مرة أخرى.'
        : 'The selected component does not match the document type. Refresh the order and select the component again.';
  }

  if (normalized.contains('delete_invoice_component_first')) {
    return isArabic
        ? 'احذف الفاتورة المرتبطة أولًا قبل حذف التجهيز المخزني.'
        : 'Delete the linked invoice before deleting the warehouse component.';
  }

  if (normalized.contains('delete_downstream_components_first')) {
    return isArabic
        ? 'احذف المراحل اللاحقة من داخل الأمر أولًا.'
        : 'Delete the later order components first.';
  }

  if (normalized.contains('delete_active_inventory_links_first') ||
      normalized.contains('delete_consuming_sales_documents_first')) {
    return isArabic
        ? 'لا يمكن حذف المادة قبل حذف عمليات البيع والشراء والتحويل النشطة المرتبطة بها.'
        : 'Delete the active sales, purchase, and transfer operations linked to this item first.';
  }

  if (normalized.contains('inventory_history_not_back_to_original')) {
    return isArabic
        ? 'ما زالت للمادة حركة مخزنية غير معكوسة. احذف العملية المرتبطة أولًا.'
        : 'The item still has an unreversed warehouse movement. Delete its linked operation first.';
  }

  if (normalized.contains('warehouse_history_would_be_negative')) {
    return isArabic
        ? 'لا يمكن عكس التحويل لأن حركة لاحقة ستجعل الرصيد سالبًا. عالج التحويلات اللاحقة أولًا.'
        : 'The transfer cannot be reversed because a later movement would make stock negative. Reverse later transfers first.';
  }

  if (normalized.contains('financial_account_currency_invalid')) {
    return isArabic
        ? 'يوجد حساب إيراد أو مصروف مستخدم في قيد مرحّل بدون عملة صحيحة. صحح عملة الحساب (USD أو IQD) ثم أعد المحاولة.'
        : 'A posted revenue or expense account has an invalid or missing currency. Correct the account currency (USD or IQD), then try again.';
  }

  if (normalized.contains('financial_document_currency_invalid')) {
    return isArabic
        ? 'يوجد مستند مالي محفوظ بدون عملة صحيحة. صحح عملة المستند المرتبط (USD أو IQD) ثم أعد المحاولة.'
        : 'A persisted financial document has an invalid or missing currency. Correct the linked document currency (USD or IQD), then try again.';
  }

  if (normalized.contains('unsupported_currency')) {
    return isArabic
        ? 'العملة غير مدعومة في هذه العملية. استخدم USD أو IQD.'
        : 'This currency is not supported for the operation. Use USD or IQD.';
  }

  if (normalized.contains('cashbox_currency_required')) {
    return isArabic
        ? 'يجب تحديد عملة صحيحة للصندوق قبل الحفظ.'
        : 'Select a valid cashbox currency before saving.';
  }

  if (normalized.contains('cashbox_active_state_required')) {
    return isArabic
        ? 'حالة الصندوق غير مكتملة. حدّد ما إذا كان الصندوق فعالًا ثم أعد الحفظ.'
        : 'The cashbox active state is incomplete. Set whether the cashbox is active, then save again.';
  }

  if (normalized.contains('cashbox_has_financial_movements')) {
    return isArabic
        ? 'لا يمكن حذف الصندوق لأنه يحتوي على حركات مالية. استخدم الإيقاف أو عالج الحركات المرتبطة أولًا.'
        : 'The cashbox cannot be deleted because it has financial movements. Deactivate it or resolve the linked movements first.';
  }

  if (normalized.contains('maintenance_cash_account_required')) {
    return isArabic
        ? 'أنشئ صندوقًا فعالًا بعملة الدفعة واربطه بحساب محاسبي أولًا.'
        : 'Create an active cashbox in the payment currency and link it to a ledger account first.';
  }

  if (normalized.contains('maintenance_customer_required_for_payment')) {
    return isArabic
        ? 'يجب ربط أمر الصيانة بعميل قبل تسجيل الدفعة.'
        : 'Link the maintenance order to a customer before recording a payment.';
  }

  if (normalized.contains('workflow_component_not_found')) {
    return isArabic
        ? 'هذه المرحلة غير موجودة أو حُذفت مسبقًا. حدّث الأمر وأعد المحاولة.'
        : 'This component is missing or was already deleted. Refresh the order and try again.';
  }

  if (normalized.contains('stale_record_conflict') ||
      normalized.contains('stale_version_required') ||
      normalized.contains('stale_version_invalid')) {
    return isArabic
        ? 'تم تعديل هذا السجل من جلسة أخرى. أعد تحميل المستند ثم طبّق تعديلاتك على النسخة الأحدث.'
        : 'This record was changed in another session. Reload the document, then apply your changes to the latest version.';
  }

  if (normalized.contains('network') ||
      normalized.contains('socket') ||
      normalized.contains('connection') ||
      normalized.contains('timeout')) {
    return isArabic
        ? 'تعذر الاتصال بالخدمة. تحقق من الاتصال ثم أعد المحاولة.'
        : 'Unable to reach the service. Check the connection and try again.';
  }

  if (normalized.contains('permission') ||
      normalized.contains('not authorized') ||
      normalized.contains('unauthorized') ||
      normalized.contains('forbidden') ||
      normalized.contains('row-level security')) {
    return isArabic
        ? 'لا تملك صلاحية تنفيذ هذه العملية.'
        : 'You do not have permission to perform this action.';
  }

  if (normalized.contains('duplicate') ||
      normalized.contains('unique constraint') ||
      normalized.contains('already exists')) {
    return isArabic
        ? 'توجد بيانات مماثلة مسجلة مسبقًا.'
        : 'A matching record already exists.';
  }

  if (normalized.contains('foreign key') ||
      normalized.contains('still referenced') ||
      normalized.contains('violates') && normalized.contains('constraint')) {
    return isArabic
        ? 'لا يمكن إتمام العملية لوجود بيانات مرتبطة بهذا السجل.'
        : 'The action cannot be completed because linked records exist.';
  }

  final technical = RegExp(
    r'(postgrest|supabase|sqlstate|constraint|rpc|function\s+erp_|'
    r'\berp_[a-z0-9_]+|uuid|stack trace|databaseexception|typeerror|'
    r'\.dart:\d+|[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-'
    r'[89ab][0-9a-f]{3}-[0-9a-f]{12})',
    caseSensitive: false,
  ).hasMatch(cleaned);

  // Preserve short, intentional domain messages while hiding raw technical text.
  if (!technical && cleaned.isNotEmpty && cleaned.length <= 180) {
    return cleaned;
  }

  return isArabic
      ? (arabicFallback ?? 'تعذر إتمام العملية. راجع البيانات ثم أعد المحاولة.')
      : (englishFallback ??
            'The action could not be completed. Review the data and try again.');
}
