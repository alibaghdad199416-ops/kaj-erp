import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';
import 'package:quality_line_erp/features/maintenance/models/maintenance_order_model.dart';
import '../../../core/cloud/workflow_operation_exception.dart';

/// Supabase-only vehicle maintenance repository.
class MaintenanceRepository {
  SupabaseClient get _client => Supabase.instance.client;

  String get _companyId {
    final value = CloudTenantContext.instance.companyUuid;
    if (value == null || value.isEmpty) {
      throw StateError('لم يتم تحديد شركة سحابية للمستخدم الحالي.');
    }
    return value;
  }

  Future<List<MaintenanceVehicleOption>> getEligibleVehicles() async {
    final result = await _client
        .rpc(
          'erp_r9_list_cloud_maintenance_eligible_cars',
          params: {'p_company_id': _companyId},
        )
        .timeout(const Duration(seconds: 20));
    final vehiclesById = <String, MaintenanceVehicleOption>{};
    for (final row in (result as List)) {
      final vehicle = MaintenanceVehicleOption.fromMap(
        Map<String, dynamic>.from(row as Map),
      );
      if (vehicle.carId.isNotEmpty) {
        vehiclesById[vehicle.carId] = vehicle;
      }
    }
    return vehiclesById.values.toList(growable: false);
  }

  Future<List<MaintenanceOrderModel>> getOrders() async {
    final result = await _client.rpc(
      'erp_r9_list_cloud_maintenance_orders',
      params: {'p_company_id': _companyId},
    );
    return (result as List)
        .map(
          (row) => MaintenanceOrderModel.fromMap(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<void> createDraftOrder({
    required String carId,
    required String warehouseId,
    required String pricingType,
    required double laborCost,
    required double salePrice,
    required List<MaintenancePartRequest> parts,
    required String currencyCode,
    String? maintenanceExpenseAccountId,
    String? notes,
    DateTime? effectiveAt,
  }) async {
    _validate(laborCost, salePrice, parts);
    await _client.rpc(
      'erp_r49_create_cloud_maintenance_order',
      params: {
        'p_company_id': _companyId,
        'p_car_id': carId,
        'p_warehouse_id': warehouseId,
        'p_pricing_type': pricingType,
        'p_labor_cost': laborCost,
        'p_sale_price': salePrice,
        'p_currency_code': currencyCode,
        'p_exchange_rate': 1,
        'p_notes': notes,
        'p_maintenance_expense_account_id': maintenanceExpenseAccountId,
        'p_effective_at': (effectiveAt ?? DateTime.now())
            .toUtc()
            .toIso8601String(),
        'p_parts': parts
            .map(
              (part) => {
                'product_id': part.productId,
                'quantity': part.quantity,
                'warehouse_id': part.warehouseId,
                'unit_price': part.unitPrice,
              },
            )
            .toList(growable: false),
      },
    );
  }

  Future<void> updateDraft({
    required String orderId,
    required String warehouseId,
    required String pricingType,
    required double laborCost,
    required double salePrice,
    required List<MaintenancePartRequest> parts,
    required String currencyCode,
    String? maintenanceExpenseAccountId,
    String? notes,
    DateTime? effectiveAt,
    required DateTime expectedUpdatedAt,
  }) async {
    _validate(laborCost, salePrice, parts);
    await _client.rpc(
      'erp_r49_update_cloud_maintenance_draft',
      params: {
        'p_company_id': _companyId,
        'p_order_id': orderId,
        'p_warehouse_id': warehouseId,
        'p_pricing_type': pricingType,
        'p_labor_cost': laborCost,
        'p_sale_price': salePrice,
        'p_currency_code': currencyCode,
        'p_exchange_rate': 1,
        'p_notes': notes,
        'p_maintenance_expense_account_id': maintenanceExpenseAccountId,
        'p_effective_at': (effectiveAt ?? DateTime.now())
            .toUtc()
            .toIso8601String(),
        'p_expected_updated_at': expectedUpdatedAt.toUtc().toIso8601String(),
        'p_parts': parts
            .map(
              (part) => {
                'product_id': part.productId,
                'quantity': part.quantity,
                'warehouse_id': part.warehouseId,
                'unit_price': part.unitPrice,
              },
            )
            .toList(growable: false),
      },
    );
  }

  Future<List<MaintenanceLineModel>> getOrderLines(String orderId) async {
    final result = await _client.rpc(
      'erp_r9_get_cloud_maintenance_order_lines',
      params: {'p_company_id': _companyId, 'p_order_id': orderId},
    );
    return (result as List)
        .map(
          (row) => MaintenanceLineModel.fromMap(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<void> deleteOrder(String orderId, {String? reason}) async {
    await _client.rpc(
      'erp_delete_cloud_maintenance_order_v3',
      params: {
        'p_company_id': _companyId,
        'p_order_id': orderId,
        'p_reason': reason,
      },
    );
  }

  Future<void> manageOrderComponent({
    required String orderId,
    required String componentType,
    required String action,
    String? reason,
  }) async {
    await _client.rpc(
      'erp_manage_maintenance_order_component',
      params: {
        'p_company_id': _companyId,
        'p_order_id': orderId,
        'p_component_type': componentType,
        'p_action': action,
        'p_reason': reason,
      },
    );
  }

  Future<void> advanceWorkflow(String orderId) async {
    await _client.rpc(
      'erp_r37_advance_maintenance_workflow',
      params: {'p_company_id': _companyId, 'p_order_id': orderId},
    );
  }

  Future<List<Map<String, Object?>>> listCashAccounts() async {
    final result = await _client.rpc(
      'erp_r49_list_cloud_active_cash_accounts',
      params: {'p_company_id': _companyId},
    );
    return (result as List)
        .map((row) => Map<String, Object?>.from(row as Map))
        .toList(growable: false);
  }

  Future<List<Map<String, Object?>>> listSettlementAccounts() async {
    final result = await _client.rpc(
      'erp_list_cloud_settlement_accounts',
      params: {'p_company_id': _companyId},
    );
    return (result as List)
        .map((row) => Map<String, Object?>.from(row as Map))
        .toList(growable: false);
  }

  Future<void> recordPaymentsBatch(
    String orderId,
    List<Map<String, Object?>> payments,
  ) async {
    if (payments.isEmpty) {
      throw ArgumentError('أضف دفعة واحدة على الأقل');
    }
    try {
      await _client.rpc(
        'erp_v2300_record_maintenance_payment_batch',
        params: {
          'p_company_id': _companyId,
          'p_order_id': orderId,
          'p_payments': payments,
        },
      );
    } on PostgrestException catch (error) {
      throw WorkflowOperationException.fromPostgrest(
        'maintenance_payment_batch',
        error,
      );
    }
  }

  Future<void> cancelOrder(String orderId, {String? reason}) async {
    await _client.rpc(
      'erp_cancel_cloud_maintenance_order',
      params: {
        'p_company_id': _companyId,
        'p_order_id': orderId,
        'p_reason': reason,
      },
    );
  }

  static void _validate(
    double laborCost,
    double salePrice,
    List<MaintenancePartRequest> parts,
  ) {
    if (laborCost < 0 || salePrice < 0) {
      throw ArgumentError('قيم أمر الصيانة غير صحيحة');
    }
    if (parts.any((part) => part.quantity <= 0 || part.unitPrice < 0)) {
      throw ArgumentError('كمية قطعة الغيار غير صحيحة');
    }
  }
}
