import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';
import 'package:quality_line_erp/core/cloud/workflow_operation_exception.dart';
import 'package:quality_line_erp/core/events/app_data_change_bus.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/features/purchases/models/purchase_workflow_models.dart';

class PurchaseWorkflowRepository {
  SupabaseClient get _client => Supabase.instance.client;
  String get _companyId =>
      CloudTenantContext.instance.companyUuid ??
      (throw StateError('لم يتم تحديد شركة سحابية.'));
  List<Map<String, Object?>> _items(List<PurchaseOrderItemInput> v) {
    if (v.isEmpty) {
      throw ArgumentError('يجب إضافة بند واحد على الأقل إلى أمر الشراء');
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
            'unitCost': e.unitCost,
          },
        )
        .toList(growable: false);
  }

  void _validateHeader({
    required String supplierId,
    required String currency,
    required double discount,
  }) {
    if (supplierId.trim().isEmpty) {
      throw ArgumentError('يجب اختيار المورد');
    }
    if (currency != 'USD' && currency != 'IQD') {
      throw ArgumentError('عملة أمر الشراء غير مدعومة');
    }
    if (discount < 0) {
      throw ArgumentError('قيمة الخصم غير صحيحة');
    }
  }

  Future<String> createDraft({
    required String supplierId,
    required String currency,
    required double exchangeRate,
    required List<PurchaseOrderItemInput> items,
    double discount = 0,
    String? notes,
    String? opportunityId,
    DateTime? effectiveAt,
  }) async {
    _validateHeader(
      supplierId: supplierId,
      currency: currency,
      discount: discount,
    );
    if (exchangeRate <= 0) {
      throw ArgumentError(
        AppTranslation.translate('سعر الصرف يجب أن يكون أكبر من صفر'),
      );
    }
    final validatedItems = _items(items);
    final id = (await _rpcValue('erp_r49_create_purchase_order', {
      'p_company_id': _companyId,
      'p_payload': {
        'supplierId': supplierId,
        'currency': currency,
        'exchangeRate': exchangeRate,
        'items': validatedItems,
        'discount': discount,
        'notes': notes,
        'opportunityId': opportunityId,
        'effectiveAt': (effectiveAt ?? DateTime.now())
            .toUtc()
            .toIso8601String(),
      },
    })).toString();
    _publishCommittedChange('erp_r49_create_purchase_order');
    return id;
  }

  Future<Map<String, Object?>?> findOrderByOpportunity(
    String opportunityId,
  ) async {
    if (opportunityId.trim().isEmpty) return null;
    final rows = await _client.rpc(
      'erp_r9_find_purchase_order_by_opportunity',
      params: {
        'p_company_id': _companyId,
        'p_opportunity_id': opportunityId.trim(),
      },
    );
    if ((rows as List).isEmpty) return null;
    return Map<String, Object?>.from(rows.first as Map);
  }

  Future<void> approveOrder(String orderId) =>
      _void('erp_r49_approve_purchase_order', {'p_order_id': orderId});
  Future<String> createReceiptDraft({
    required String orderId,
    required String warehouseId,
    String? notes,
  }) async {
    final id = (await _client.rpc(
      'erp_r49_create_purchase_receipt',
      params: {
        'p_company_id': _companyId,
        'p_order_id': orderId,
        'p_warehouse_id': warehouseId,
        'p_notes': notes,
      },
    )).toString();
    _publishCommittedChange('erp_r49_create_purchase_receipt');
    return id;
  }

  Future<void> approveReceipt(String receiptId) =>
      _void('erp_phase2_approve_purchase_receipt', {'p_receipt_id': receiptId});
  Future<void> cancelReceipt(String receiptId) =>
      _void('erp_cancel_cloud_purchase_receipt', {'p_receipt_id': receiptId});
  Future<String> createInvoiceDraft(String orderId) async {
    final id = (await _client.rpc(
      'erp_create_cloud_purchase_workflow_invoice',
      params: {'p_company_id': _companyId, 'p_order_id': orderId},
    )).toString();
    _publishCommittedChange('erp_create_cloud_purchase_workflow_invoice');
    return id;
  }

  Future<void> approveInvoice(String invoiceId) =>
      _void('erp_r22_approve_purchase_invoice', {'p_invoice_id': invoiceId});
  Future<void> addInvoicePayment(
    String invoiceId,
    PurchaseInvoicePaymentInput payment,
  ) async {
    if (invoiceId.trim().isEmpty) throw ArgumentError('مرجع الفاتورة غير صالح');
    payment.validate();
    await _void('erp_pay_cloud_purchase_workflow_invoice', {
      'p_invoice_id': invoiceId,
      'p_payment': {
        'cashAccountId': payment.cashAccountId,
        'paymentCurrency': payment.paymentCurrency,
        'invoiceAmount': payment.invoiceAmount,
        'cashAmount': payment.cashAmount,
        'exchangeRate': payment.exchangeRate,
        'paymentDate': payment.paymentDate?.toUtc().toIso8601String(),
        'notes': payment.notes,
        'settlementMode': payment.settlementMode.name,
      },
    });
  }

  Future<void> cancelInvoice(
    String invoiceId, {
    String reason = 'إلغاء فاتورة الشراء',
  }) => _void('erp_cancel_cloud_purchase_workflow_invoice', {
    'p_invoice_id': invoiceId,
    'p_reason': reason,
  });
  Future<void> updateDraft({
    required String orderId,
    required String supplierId,
    required String currency,
    required double exchangeRate,
    required double discount,
    required List<PurchaseOrderItemInput> items,
    String? notes,
    DateTime? effectiveAt,
    required DateTime expectedUpdatedAt,
  }) async {
    if (orderId.trim().isEmpty) throw ArgumentError('معرف أمر الشراء مطلوب');
    _validateHeader(
      supplierId: supplierId,
      currency: currency,
      discount: discount,
    );
    if (exchangeRate <= 0) {
      throw ArgumentError(
        AppTranslation.translate('سعر الصرف يجب أن يكون أكبر من صفر'),
      );
    }
    await _void('erp_r49_update_purchase_order', {
      'p_payload': {
        'orderId': orderId,
        'supplierId': supplierId,
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
        'p_module': 'purchases',
        'p_record_type': 'order',
        'p_record_id': orderId,
        'p_effective_at': value.toUtc().toIso8601String(),
      });

  Future<void> deleteOrderCascade(String orderId) =>
      _void('erp_delete_cloud_purchase_order_v3', {'p_order_id': orderId});

  Future<void> manageOrderComponent({
    required String orderId,
    required String componentType,
    required String componentId,
    required String action,
    String? reason,
  }) => _void('erp_manage_commercial_order_component_v3', {
    'p_module': 'purchases',
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
      'p_module': 'purchases',
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
        'p_module': 'purchases',
      },
    );
    return value is Map
        ? Map<String, Object?>.from(value)
        : <String, Object?>{};
  }

  Future<String> createReceiptDraftMulti({
    required String orderId,
    required List<Map<String, Object?>> allocations,
    String? notes,
  }) async {
    if (allocations.isEmpty) {
      throw ArgumentError('يجب توزيع بند واحد على الأقل على المخازن');
    }
    final id = (await _client.rpc(
      'erp_r49_create_purchase_receipt_multi',
      params: {
        'p_company_id': _companyId,
        'p_order_id': orderId,
        'p_allocations': allocations,
        'p_notes': notes,
      },
    )).toString();
    _publishCommittedChange('erp_r49_create_purchase_receipt_multi');
    return id;
  }

  Future<List<Map<String, Object?>>> listOrders() async => _rows(
    await _client.rpc(
      'erp_r9_list_cloud_purchase_workflow_orders',
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
  Future<List<Map<String, Object?>>> purchaseCatalog({String? orderId}) async {
    final editing = orderId != null && orderId.trim().isNotEmpty;
    return _rows(
      await _client.rpc(
        editing
            ? 'erp_cloud_purchase_order_edit_catalog'
            : 'erp_cloud_purchase_order_catalog',
        params: <String, Object?>{
          'p_company_id': _companyId,
          if (editing) 'p_order_id': orderId,
        },
      ),
    );
  }

  Future<Map<String, Object?>?> getDraft(String orderId) async {
    final v = await _client.rpc(
      'erp_r49_get_purchase_order_draft',
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
    } on PostgrestException catch (error) {
      throw WorkflowOperationException.fromPostgrest(fn, error);
    }
  }

  void _publishCommittedChange(String operation) {
    AppDataChangeBus.instance.publish('purchases', operation: operation);
    if (operation.contains('receipt') ||
        operation.contains('delivery') ||
        operation.contains('approve_cloud_purchase_order') ||
        operation.contains('reopen_cloud_purchase_order') ||
        operation.contains('with_links') ||
        operation.contains('delete_cloud_purchase_order')) {
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
