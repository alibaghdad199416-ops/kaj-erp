import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';
import 'package:quality_line_erp/core/cloud/workflow_operation_exception.dart';
import 'package:quality_line_erp/core/events/app_data_change_bus.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/features/sales/workflow/models/sales_workflow_models.dart';

class SalesWorkflowRepository {
  SupabaseClient get _client => Supabase.instance.client;
  String get _companyId =>
      CloudTenantContext.instance.companyUuid ??
      (throw StateError('لم يتم تحديد شركة سحابية.'));
  List<Map<String, Object?>> _items(List<SalesOrderItemInput> v) {
    if (v.isEmpty) {
      throw ArgumentError(
        AppTranslation.translate('يجب إضافة بند واحد على الأقل إلى أمر البيع'),
      );
    }
    for (final item in v) {
      item.validate();
    }
    return v
        .map(
          (e) => {
            'itemType': e.itemType,
            'itemId': e.itemId,
            'description': e.description,
            'quantity': e.quantity,
            'unitPrice': e.unitPrice,
          },
        )
        .toList(growable: false);
  }

  void _validateHeader({
    required String partyId,
    required String currency,
    required double discount,
  }) {
    if (partyId.trim().isEmpty) {
      throw ArgumentError(AppTranslation.translate('يجب اختيار العميل'));
    }
    if (currency != 'USD' && currency != 'IQD') {
      throw ArgumentError(
        AppTranslation.translate('عملة أمر البيع غير مدعومة'),
      );
    }
    if (discount < 0) {
      throw ArgumentError(AppTranslation.translate('قيمة الخصم غير صحيحة'));
    }
  }

  Future<String> createDraft({
    required String customerId,
    required String currency,
    required double exchangeRate,
    required List<SalesOrderItemInput> items,
    String? opportunityId,
    double discount = 0,
    String? notes,
    DateTime? effectiveAt,
  }) async {
    _validateHeader(
      partyId: customerId,
      currency: currency,
      discount: discount,
    );
    if (exchangeRate <= 0) {
      throw ArgumentError(
        AppTranslation.translate('سعر الصرف يجب أن يكون أكبر من صفر'),
      );
    }
    final validatedItems = _items(items);
    final id = (await _rpcValue('erp_r49_create_sales_order', {
      'p_company_id': _companyId,
      'p_payload': {
        'customerId': customerId,
        'currency': currency,
        'exchangeRate': exchangeRate,
        'items': validatedItems,
        'opportunityId': opportunityId,
        'discount': discount,
        'notes': notes,
        'effectiveAt': (effectiveAt ?? DateTime.now())
            .toUtc()
            .toIso8601String(),
      },
    })).toString();
    _publishCommittedChange('erp_r49_create_sales_order');
    await _reconcileOpportunityLinks();
    return id;
  }

  Future<void> approveOrder(String orderId) =>
      _void('erp_r49_approve_sales_order', {'p_order_id': orderId});

  Future<Map<String, Object?>?> findOrderByOpportunity(
    String opportunityId,
  ) async {
    if (opportunityId.trim().isEmpty) return null;
    final rows = await _client.rpc(
      'erp_r9_find_sales_order_by_opportunity',
      params: {
        'p_company_id': _companyId,
        'p_opportunity_id': opportunityId.trim(),
      },
    );
    if (rows.isEmpty) return null;
    if (rows.length > 1) {
      throw StateError(
        AppTranslation.translate(
          'توجد أكثر من مسودة أمر بيع مرتبطة بالفرصة. طبّق آخر تحديث لقاعدة البيانات ثم أعد المحاولة.',
        ),
      );
    }
    return Map<String, Object?>.from(rows.first as Map);
  }

  Future<String> createDeliveryDraft({
    required String orderId,
    required String warehouseId,
    String? notes,
  }) async {
    final id = (await _rpcValue('erp_r49_create_sales_delivery', {
      'p_company_id': _companyId,
      'p_order_id': orderId,
      'p_warehouse_id': warehouseId,
      'p_notes': notes,
    })).toString();
    _publishCommittedChange('erp_r49_create_sales_delivery');
    await _reconcileOpportunityLinks();
    return id;
  }

  Future<void> approveDelivery(String deliveryId) =>
      _void('erp_phase2_approve_sales_delivery', {'p_delivery_id': deliveryId});
  Future<void> cancelDelivery(String deliveryId) =>
      _void('erp_cancel_cloud_sales_delivery', {'p_delivery_id': deliveryId});
  Future<String> createInvoiceDraft(String orderId) async {
    final id = (await _rpcValue('erp_create_cloud_sales_workflow_invoice', {
      'p_company_id': _companyId,
      'p_order_id': orderId,
    })).toString();
    _publishCommittedChange('erp_create_cloud_sales_workflow_invoice');
    await _reconcileOpportunityLinks();
    return id;
  }

  Future<void> approveInvoice(String invoiceId) =>
      _void('erp_r22_approve_sales_invoice', {'p_invoice_id': invoiceId});
  Future<void> addInvoicePayment(
    String invoiceId,
    InvoicePaymentInput payment,
  ) async {
    if (invoiceId.trim().isEmpty) throw ArgumentError('مرجع الفاتورة غير صالح');
    payment.validate();
    await _void('erp_pay_cloud_sales_workflow_invoice', {
      'p_invoice_id': invoiceId,
      'p_payment': {
        'cashAccountId': payment.cashAccountId,
        'paymentCurrency': payment.paymentCurrency,
        'invoiceAmount': payment.invoiceAmount,
        'cashAmount': payment.cashAmount,
        'exchangeRate': payment.exchangeRate,
        'paymentDate': payment.paymentDate.toUtc().toIso8601String(),
        'notes': payment.notes,
        'settlementMode': payment.settlementMode.name,
      },
    });
  }

  Future<void> cancelInvoice(
    String invoiceId, {
    String reason = 'إلغاء فاتورة البيع',
  }) => _void('erp_cancel_cloud_sales_workflow_invoice', {
    'p_invoice_id': invoiceId,
    'p_reason': reason,
  });
  Future<void> updateDraft({
    required String orderId,
    required String customerId,
    required String currency,
    required double exchangeRate,
    required double discount,
    required List<SalesOrderItemInput> items,
    String? notes,
    DateTime? effectiveAt,
    required DateTime expectedUpdatedAt,
  }) async {
    if (orderId.trim().isEmpty) throw ArgumentError('معرف أمر البيع مطلوب');
    _validateHeader(
      partyId: customerId,
      currency: currency,
      discount: discount,
    );
    if (exchangeRate <= 0) {
      throw ArgumentError(
        AppTranslation.translate('سعر الصرف يجب أن يكون أكبر من صفر'),
      );
    }
    await _void('erp_r49_update_sales_order', {
      'p_payload': {
        'orderId': orderId,
        'customerId': customerId,
        'currency': currency,
        'exchangeRate': exchangeRate,
        'discount': discount,
        'items': _items(items),
        'notes': notes,
        'effectiveAt': (effectiveAt ?? DateTime.now())
            .toUtc()
            .toIso8601String(),
        'expectedUpdatedAt': expectedUpdatedAt.toUtc().toIso8601String(),
      },
    });
  }

  Future<void> setEffectiveAt(String orderId, DateTime value) =>
      _void('erp_set_operational_effective_at', {
        'p_module': 'sales',
        'p_record_type': 'order',
        'p_record_id': orderId,
        'p_effective_at': value.toUtc().toIso8601String(),
      });

  Future<void> deleteOrderCascade(String orderId) => _void(
    'erp_r67_delete_commercial_order',
    {'p_order_id': orderId, 'p_module': 'sales'},
  );

  Future<void> cancelOrder(String orderId, {String? reason}) => _void(
    'erp_r62_cancel_commercial_order',
    {'p_order_id': orderId, 'p_module': 'sales', 'p_reason': reason},
  );

  Future<void> manageOrderComponent({
    required String orderId,
    required String componentType,
    required String componentId,
    required String action,
    String? reason,
  }) => _void('erp_manage_commercial_order_component_v3', {
    'p_module': 'sales',
    'p_order_id': orderId,
    'p_component_type': componentType,
    'p_component_id': componentId,
    'p_action': action,
    'p_reason': reason,
  });

  Future<void> addInvoicePaymentsBatch(
    String invoiceId,
    List<Map<String, Object?>> payments,
  ) async {
    if (invoiceId.trim().isEmpty) throw ArgumentError('مرجع الفاتورة غير صالح');
    if (payments.isEmpty) throw ArgumentError('يجب إضافة دفعة واحدة على الأقل');
    await _void('erp_v2300_pay_cloud_workflow_invoice_batch', {
      'p_invoice_id': invoiceId,
      'p_module': 'sales',
      'p_payments': payments,
    });
  }

  Future<Map<String, Object?>> warehouseAllocationContext(
    String orderId,
  ) async {
    final value = await _client.rpc(
      'erp_r49_get_commercial_order_allocation_context',
      params: {
        'p_company_id': _companyId,
        'p_order_id': orderId,
        'p_module': 'sales',
      },
    );
    return value is Map
        ? Map<String, Object?>.from(value)
        : <String, Object?>{};
  }

  Future<String> createDeliveryDraftMulti({
    required String orderId,
    required List<Map<String, Object?>> allocations,
    String? notes,
  }) async {
    if (allocations.isEmpty) {
      throw ArgumentError('يجب توزيع بند واحد على الأقل على المخازن');
    }
    final id = (await _rpcValue('erp_r49_create_sales_delivery_multi', {
      'p_company_id': _companyId,
      'p_order_id': orderId,
      'p_allocations': allocations,
      'p_notes': notes,
    })).toString();
    _publishCommittedChange('erp_r49_create_sales_delivery_multi');
    await _reconcileOpportunityLinks();
    return id;
  }

  Future<List<Map<String, Object?>>> listOrders() async => _rows(
    await _client.rpc(
      'erp_r9_list_cloud_sales_workflow_orders',
      params: {'p_company_id': _companyId},
    ),
  );
  Future<List<Map<String, Object?>>> listWarehouses() async => _rows(
    await _client.rpc(
      'erp_r49_list_cloud_active_warehouses',
      params: {'p_company_id': _companyId},
    ),
  );
  Future<List<Map<String, Object?>>> listCashAccounts() async => _rows(
    await _client.rpc(
      'erp_r49_list_cloud_active_cash_accounts',
      params: {'p_company_id': _companyId},
    ),
  );
  Future<List<Map<String, Object?>>> listSettlementAccounts() async => _rows(
    await _client.rpc(
      'erp_list_cloud_settlement_accounts',
      params: {'p_company_id': _companyId},
    ),
  );
  Future<List<Map<String, Object?>>> salesCatalog({String? orderId}) async {
    final editing = orderId != null && orderId.trim().isNotEmpty;
    return _rows(
      await _client.rpc(
        editing
            ? 'erp_cloud_sales_order_edit_catalog'
            : 'erp_cloud_sales_order_catalog',
        params: <String, Object?>{
          'p_company_id': _companyId,
          if (editing) 'p_order_id': orderId,
        },
      ),
    );
  }

  Future<Map<String, Object?>?> getDraft(String orderId) async {
    final v = await _client.rpc(
      'erp_r49_get_sales_order_draft',
      params: {'p_company_id': _companyId, 'p_order_id': orderId},
    );
    return v is Map ? Map<String, Object?>.from(v) : null;
  }

  List<Map<String, Object?>> _rows(dynamic value) => value is List
      ? value.whereType<Map>().map((e) => Map<String, Object?>.from(e)).toList()
      : const [];
  Future<Object?> _rpcValue(String fn, Map<String, Object?> params) async {
    try {
      return await _client.rpc(fn, params: params);
    } on PostgrestException catch (error) {
      throw WorkflowOperationException.fromPostgrest(fn, error);
    }
  }

  Future<void> _reconcileOpportunityLinks() async {
    try {
      await _client.rpc(
        'erp_r43_reconcile_opportunity_sales_links',
        params: {'p_company_id': _companyId},
      );
    } catch (_) {
      // The transactional sales action remains authoritative. This helper only
      // repairs/refreshes the opportunity projection and is intentionally best effort.
    }
  }

  Future<void> _void(String fn, Map<String, Object?> p) async {
    try {
      final result = await _client.rpc(
        fn,
        params: {'p_company_id': _companyId, ...p},
      );
      if (result is Map && result['ok'] == false) {
        throw WorkflowOperationException(
          operation: fn,
          message: (result['error'] ?? 'workflow_operation_failed').toString(),
          code: result['code']?.toString(),
          details: result['details']?.toString(),
          hint: result['hint']?.toString(),
        );
      }
      _publishCommittedChange(fn);
      await _reconcileOpportunityLinks();
    } on PostgrestException catch (error) {
      throw WorkflowOperationException.fromPostgrest(fn, error);
    }
  }

  void _publishCommittedChange(String operation) {
    AppDataChangeBus.instance.publish('sales', operation: operation);
    // Every committed sales workflow step is reflected back into its linked
    // opportunity (order, delivery, invoice, cancellation, and payments).
    AppDataChangeBus.instance.publish('opportunities', operation: operation);
    if (operation.contains('receipt') ||
        operation.contains('delivery') ||
        operation.contains('approve_cloud_sales_order') ||
        operation.contains('reopen_cloud_sales_order') ||
        operation.contains('with_links') ||
        operation.contains('delete_cloud_sales_order')) {
      AppDataChangeBus.instance.publish('inventory', operation: operation);
      AppDataChangeBus.instance.publish('cars', operation: operation);
    }
    if (operation.contains('invoice') ||
        operation.contains('payment') ||
        operation.contains('with_links') ||
        operation.contains('delete_cloud')) {
      AppDataChangeBus.instance.publish('accounting', operation: operation);
      AppDataChangeBus.instance.publish('cashbox', operation: operation);
    }
  }
}
