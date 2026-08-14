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
  final raw = error is WorkflowOperationException
      ? <String?>[
          error.message,
          error.code,
          error.details,
          error.hint,
        ].whereType<String>().join(' ').trim()
      : error.toString().trim();
  final cleaned = raw
      .replaceFirst(RegExp(r'^(Exception|StateError|ArgumentError):\s*'), '')
      .replaceFirst(RegExp(r'^Bad state:\s*'), '')
      .trim();
  final normalized = cleaned.toLowerCase();

  if (normalized.contains('opportunity_won_owned_by_sales_workflow') ||
      normalized.contains('opportunity_terminal_stage_sales_owned') ||
      normalized.contains('opportunity_won_requires_canonical_sales_workflow') ||
      normalized.contains('opportunity_already_won')) {
    return isArabic
        ? 'حالة الفوز والإغلاق في الفرصة تُحدَّث تلقائيًا من مسار المبيعات المعتمد. افتح أمر البيع المرتبط وأكمل مرحلته المطلوبة.'
        : 'Opportunity Won/Closed status is controlled by the canonical sales workflow. Open the linked sales order and complete the required stage.';
  }

  if (normalized.contains('opportunity_has_sales_history')) {
    return isArabic
        ? 'لا يمكن حذف الفرصة ما دام أمر بيع فعال مرتبطًا بها. ألغِ أو عالج أمر البيع المرتبط أولًا.'
        : 'The opportunity cannot be deleted while an active sales order is linked to it. Cancel or resolve the linked sales order first.';
  }

  if (normalized.contains('opportunity_customer_required')) {
    return isArabic
        ? 'يجب تحديد عميل صالح للفرصة قبل الحفظ.'
        : 'Select a valid customer for the opportunity before saving.';
  }

  if (normalized.contains('opportunity_customer_mismatch') ||
      normalized.contains('opportunity_sales_customer_locked')) {
    return isArabic
        ? 'عميل الفرصة لا يطابق العميل في أمر البيع المرتبط. بعد إنشاء أمر البيع لا يمكن تغيير هوية العميل من الفرصة.'
        : 'The opportunity customer does not match the linked sales order. Customer identity cannot be changed from CRM after a sales order exists.';
  }

  if (normalized.contains('opportunity_currency_invalid')) {
    return isArabic
        ? 'عملة الفرصة غير صالحة. استخدم USD أو IQD.'
        : 'The opportunity currency is invalid. Use USD or IQD.';
  }

  if (normalized.contains('opportunity_currency_mismatch') ||
      normalized.contains('opportunity_sales_currency_locked')) {
    return isArabic
        ? 'عملة الفرصة لا تطابق عملة أمر البيع المرتبط. بعد إنشاء أمر البيع لا يمكن تغيير العملة من الفرصة.'
        : 'The opportunity currency does not match the linked sales order. Currency cannot be changed from CRM after a sales order exists.';
  }

  if (normalized.contains('opportunity_expected_value_invalid')) {
    return isArabic
        ? 'القيمة المتوقعة للفرصة يجب أن تكون رقمًا صالحًا غير سالب.'
        : 'The opportunity expected value must be a valid non-negative number.';
  }

  if (normalized.contains('opportunity_probability_invalid')) {
    return isArabic
        ? 'احتمالية الفرصة يجب أن تكون بين 0 و100.'
        : 'Opportunity probability must be between 0 and 100.';
  }

  if (normalized.contains('opportunity_responsible_user_invalid')) {
    return isArabic
        ? 'المستخدم المسؤول غير فعال في الشركة الحالية. اختر مستخدمًا فعالًا أو اترك الفرصة بدون إسناد.'
        : 'The responsible user is not an active member of the current company. Select an active user or leave the opportunity unassigned.';
  }

  if (normalized.contains('opportunity_lost_requires_transition') ||
      normalized.contains('opportunity_lost_requires_mark_lost')) {
    return isArabic
        ? 'حوّل الفرصة إلى خاسرة باستخدام إجراء «خاسرة» المعتمد بدل تعديل الحالة مباشرة.'
        : 'Mark the opportunity Lost using the governed Lost action instead of changing the terminal state directly.';
  }

  if (normalized.contains('opportunity_is_lost') ||
      normalized.contains('lost_opportunity_cannot_create_sales_order')) {
    return isArabic
        ? 'الفرصة خاسرة حاليًا ولا يمكن إنشاء أو إعادة تفعيل أمر بيع منها. راجع حالة الفرصة قبل بدء دورة بيع جديدة.'
        : 'This opportunity is currently Lost, so a sales order cannot be created or reactivated from it. Review the opportunity state before starting a new sales lifecycle.';
  }

  if (normalized.contains('lost_opportunity_cannot_create_maintenance_order')) {
    return isArabic
        ? 'الفرصة خاسرة ولا يمكن إنشاء أمر صيانة جديد منها. يمكن فتح أو مراجعة أمر الصيانة التاريخي المرتبط إن وُجد.'
        : 'This opportunity is Lost, so a new maintenance order cannot be created from it. An existing historical maintenance order can still be opened for review.';
  }

  if (normalized.contains('maintenance_opportunity_link_missing_after_save')) {
    return isArabic
        ? 'تم حفظ أمر الصيانة لكن تعذر إعادة قراءة ارتباطه بالفرصة. حدّث الفرص وتحقق من أمر الصيانة قبل إعادة المحاولة.'
        : 'The maintenance order was saved, but its Opportunity link could not be read back. Refresh CRM and verify the maintenance order before trying again.';
  }

  if (normalized.contains('financial_family_incomplete_or_ambiguous') ||
      normalized.contains('financial_family_postcondition_failed')) {
    return isArabic
        ? 'تعذر تحديد جميع السجلات المرتبطة بهذه العملية المالية بشكل آمن. لم يتم حذف أي سجل.'
        : 'Unable to safely identify all linked records for this financial transaction. No records were deleted.';
  }

  if (normalized.contains('payment_linked_to_active_invoice') ||
      normalized.contains('payment_linked_to_active_maintenance_invoice') ||
      normalized.contains('payment_has_active_allocations')) {
    return isArabic
        ? 'هذه الدفعة مرتبطة بفاتورة أو تخصيص نشط. يجب فك أو عكس ارتباط الفاتورة قبل حذف الدفعة.'
        : 'This payment is linked to an invoice or active allocation. Remove or reverse the invoice allocation before deleting the payment.';
  }

  if (normalized.contains('over_receipt') ||
      normalized.contains('purchase_receipt_over_quantity')) {
    return isArabic
        ? 'كمية الاستلام تتجاوز الكمية المتبقية في أمر الشراء. حدّث الأمر وراجع توزيع الاستلام.'
        : 'The receipt quantity exceeds the remaining purchase-order quantity. Refresh the order and review the receipt allocation.';
  }
  if (normalized.contains('receipt_missing') ||
      normalized.contains('receipt_not_approved')) {
    return isArabic
        ? 'يلزم وجود استلام مخزني منفّذ ومعتمد قبل إنشاء فاتورة الشراء.'
        : 'An executed and approved receipt is required before creating the purchase invoice.';
  }
  if (normalized.contains('invoice_already_posted')) {
    return isArabic
        ? 'تم ترحيل هذه الفاتورة مسبقًا. حدّث تفاصيل الأمر لعرض القيد الحالي.'
        : 'This invoice is already posted. Refresh the order details to view the existing journal.';
  }
  if (normalized.contains('account_binding_missing')) {
    return isArabic
        ? 'ربط الحساب المحاسبي المطلوب غير مكتمل. راجع إعدادات الحسابات قبل إعادة المحاولة.'
        : 'A required accounting binding is missing. Review account settings before trying again.';
  }
  if (normalized.contains('payment_allocation_invalid')) {
    return isArabic
        ? 'تخصيص الدفعة غير صالح للمبلغ أو العملة أو الفاتورة المحددة. حدّث التفاصيل وراجع التخصيص.'
        : 'The payment allocation does not match the selected amount, currency, or invoice. Refresh and review the allocation.';
  }
  if (normalized.contains('invalid_transition')) {
    return isArabic
        ? 'لا يمكن نقل المستند من حالته الحالية إلى المرحلة المطلوبة. حدّث التفاصيل وراجع تسلسل العمل.'
        : 'The document cannot move from its current state to the requested stage. Refresh and review the workflow sequence.';
  }

  if (normalized.contains('car_warehouse_mismatch')) {
    return isArabic
        ? 'السيارة المحددة موجودة في مخزن مختلف. نفّذ تحويلًا مخزنيًا معتمدًا أو اختر مخزنها الفعلي ثم أعد المحاولة.'
        : 'The selected vehicle is in a different warehouse. Complete an approved warehouse transfer or select its actual warehouse, then try again.';
  }

  if (normalized.contains('approved_sales_delivery_required') ||
      normalized.contains('approved_inventory_document_required') ||
      normalized.contains('delivery_missing') ||
      normalized.contains('delivery_not_approved')) {
    return isArabic
        ? 'يلزم وجود تسليم مخزني منفّذ ومعتمد قبل إنشاء فاتورة البيع.'
        : 'An executed and approved delivery is required before creating the sales invoice.';
  }

  if (normalized.contains('car_not_available')) {
    return isArabic
        ? 'السيارة المحددة غير متاحة للتسليم من المخزن. حدّث حالة السيارة وموقعها ثم أعد المحاولة.'
        : 'The selected vehicle is not available for warehouse delivery. Refresh its status and warehouse, then try again.';
  }

  if (normalized.contains('commercial_over_fulfillment') ||
      normalized.contains('sales_delivery_over_quantity') ||
      normalized.contains('over_delivery')) {
    return isArabic
        ? 'كمية التسليم تتجاوز الكمية المتبقية في أمر البيع. حدّث الأمر وراجع التوزيع.'
        : 'The delivery quantity exceeds the remaining sales-order quantity. Refresh the order and review the allocation.';
  }

  if (normalized.contains('insufficient_warehouse_stock') ||
      normalized.contains('insufficient_stock')) {
    return isArabic
        ? 'الرصيد المتاح في المخزن غير كافٍ لإتمام التسليم. راجع المخزن والكميات الموزعة.'
        : 'Available warehouse stock is insufficient for this delivery. Review the warehouse and allocated quantities.';
  }

  if (normalized.contains('warehouse_not_found_or_inactive') ||
      normalized.contains('warehouse_not_selected')) {
    return isArabic
        ? 'اختر مخزنًا نشطًا لكل بند قبل إنشاء المستند المخزني.'
        : 'Select an active warehouse for every line before creating the warehouse document.';
  }

  if (normalized.contains('active_delivery_draft_exists') ||
      normalized.contains('delivery_already_executed')) {
    return isArabic
        ? 'يوجد مستند تسليم نشط لهذا الأمر بالفعل. افتحه أو حدّث تفاصيل الأمر.'
        : 'An active delivery document already exists for this order. Open it or refresh the order details.';
  }

  if (normalized.contains('product_inventory_account_missing')) {
    return isArabic
        ? 'حساب مخزون أحد المنتجات غير مهيأ. راجع ربط حسابات المنتج قبل التصديق.'
        : 'An inventory account is missing for one of the products. Review product account mapping before approval.';
  }

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
