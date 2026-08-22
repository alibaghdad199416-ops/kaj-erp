import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';
import 'package:quality_line_erp/features/maintenance/models/maintenance_order_model.dart';
import 'package:quality_line_erp/features/maintenance/models/maintenance_cost_reconciliation.dart';
import 'package:quality_line_erp/features/maintenance/models/maintenance_order_snapshot.dart';
import '../../../core/cloud/workflow_operation_exception.dart';

/// Supabase-only vehicle maintenance repository.
class MaintenanceRepository {
  static const String maintenanceScheduleFieldPermission =
      'maintenanceSchedule';

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
      'erp_r87_list_cloud_maintenance_orders',
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

  Future<List<Map<String, Object?>>> getMaintenancePayments(
    String orderId,
  ) async {
    final result = await _client.rpc(
      'erp_r90_list_maintenance_payments',
      params: {'p_company_id': _companyId, 'p_order_id': orderId},
    );
    return _rows(result);
  }

  Future<MaintenanceOrderSnapshot> getOrderSnapshot(String orderId) async {
    final result = await _client.rpc(
      'erp_r90_get_maintenance_order_snapshot',
      params: {'p_company_id': _companyId, 'p_order_id': orderId},
    );
    return MaintenanceOrderSnapshot.fromRpc(result);
  }

  Future<MaintenanceOrderModel?> findByOpportunity(String opportunityId) async {
    final result = await _client.rpc(
      'erp_r56_find_maintenance_by_opportunity',
      params: {'p_company_id': _companyId, 'p_opportunity_id': opportunityId},
    );
    if (result is! Map) return null;
    return MaintenanceOrderModel.fromMap(Map<String, dynamic>.from(result));
  }

  Future<Map<String, Object?>> getVehicleServiceCard(String carId) async {
    final result = await _client.rpc(
      'erp_r90_vehicle_service_card',
      params: {'p_company_id': _companyId, 'p_car_id': carId},
    );
    return result is Map ? Map<String, Object?>.from(result) : const {};
  }

  Future<List<Map<String, Object?>>> getMaintenanceSchedules(
    String carId,
  ) async {
    final result = await _client.rpc(
      'erp_r88_list_vehicle_maintenance_schedules',
      params: {'p_company_id': _companyId, 'p_car_id': carId},
    );
    return _rows(result);
  }

  Future<String> saveMaintenanceSchedule(Map<String, Object?> schedule) async {
    final result = await _client.rpc(
      'erp_r88_save_vehicle_maintenance_schedule',
      params: {'p_company_id': _companyId, 'p_schedule': schedule},
    );
    return result.toString();
  }

  Future<void> deleteMaintenanceSchedule(String scheduleId) async {
    await _client.rpc(
      'erp_r88_delete_vehicle_maintenance_schedule',
      params: {'p_company_id': _companyId, 'p_schedule_id': scheduleId},
    );
  }

  Future<void> linkMaintenanceScheduleToOrder({
    required String scheduleId,
    required String maintenanceOrderId,
  }) async {
    await _client.rpc(
      'erp_r88_link_maintenance_schedule_order',
      params: {
        'p_company_id': _companyId,
        'p_schedule_id': scheduleId,
        'p_maintenance_order_id': maintenanceOrderId,
      },
    );
  }

  Future<String> saveMaintenanceHistoryDetail(
    Map<String, Object?> detail,
  ) async {
    final result = await _client.rpc(
      'erp_r88_save_maintenance_history_detail',
      params: {'p_company_id': _companyId, 'p_detail': detail},
    );
    return result.toString();
  }

  Future<void> deleteMaintenanceHistoryDetail(String detailId) async {
    await _client.rpc(
      'erp_r88_delete_maintenance_history_detail',
      params: {'p_company_id': _companyId, 'p_detail_id': detailId},
    );
  }

  Future<int> materializeMaintenanceScheduleReminders() async {
    final result = await _client.rpc(
      'erp_r88_materialize_maintenance_schedule_reminders',
      params: {'p_company_id': _companyId},
    );
    return result is num ? result.toInt() : int.tryParse('$result') ?? 0;
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
    String? opportunityId,
    String? notes,
    DateTime? effectiveAt,
  }) async {
    _validate(laborCost, salePrice, parts);
    await _client.rpc(
      'erp_r56_create_cloud_maintenance_order',
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
        'p_opportunity_id': opportunityId,
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

  Future<MaintenanceCostReconciliation> getCostReconciliation(
    String orderId,
  ) async {
    final results = await Future.wait<Object?>(<Future<Object?>>[
      _client.rpc(
        'erp_r89_maintenance_cost_reconciliation',
        params: {'p_company_id': _companyId, 'p_order_id': orderId},
      ),
      _client.rpc(
        'erp_r90_maintenance_material_issue_state',
        params: {'p_company_id': _companyId, 'p_order_id': orderId},
      ),
    ]);
    if (results[0] is! Map || results[1] is! Map) {
      throw StateError('maintenance_cost_reconciliation_invalid');
    }
    return mergeMaintenanceReconciliationPayloads(
      reconciliation: Map<String, Object?>.from(results[0] as Map),
      issueState: Map<String, Object?>.from(results[1] as Map),
    );
  }

  Future<List<Map<String, Object?>>> getIssueWarehouseOptions(
    String partId,
  ) async {
    final result = await _client.rpc(
      'erp_r90_maintenance_issue_warehouse_options',
      params: {'p_company_id': _companyId, 'p_part_id': partId},
    );
    return (result as List)
        .map((row) => Map<String, Object?>.from(row as Map))
        .toList(growable: false);
  }

  Future<void> saveMaterialIssueDraftLine({
    required String orderId,
    required String partId,
    required String warehouseId,
    required double quantity,
  }) async {
    await _client.rpc(
      'erp_r90_save_maintenance_issue_draft_line',
      params: {
        'p_company_id': _companyId,
        'p_order_id': orderId,
        'p_part_id': partId,
        'p_warehouse_id': warehouseId,
        'p_quantity': quantity,
      },
    );
  }

  Future<void> deleteMaterialIssueDraftLine(String lineId) async {
    await _client.rpc(
      'erp_r90_delete_maintenance_issue_draft_line',
      params: {'p_company_id': _companyId, 'p_line_id': lineId},
    );
  }

  Future<void> reverseMaterialIssue(String issueId, {String? reason}) async {
    await _client.rpc(
      'erp_r57_reverse_maintenance_material_issue',
      params: {
        'p_company_id': _companyId,
        'p_issue_id': issueId,
        'p_reason': reason,
      },
    );
  }

  Future<void> deleteOrder(String orderId, {String? reason}) async {
    await _client.rpc(
      'erp_r67_delete_maintenance_order',
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
      'erp_r92_list_workflow_cash_accounts',
      params: {'p_company_id': _companyId, 'p_module': 'maintenance'},
    );
    return (result as List)
        .map((row) => Map<String, Object?>.from(row as Map))
        .toList(growable: false);
  }

  Future<List<Map<String, Object?>>> listSettlementAccounts() async {
    final result = await _client.rpc(
      'erp_r92_list_workflow_settlement_accounts',
      params: {'p_company_id': _companyId, 'p_module': 'maintenance'},
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
      'erp_r67_cancel_maintenance_order',
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

  static List<Map<String, Object?>> _rows(Object? raw) => raw is List
      ? raw
            .whereType<Map>()
            .map((row) => Map<String, Object?>.from(row))
            .toList(growable: false)
      : const <Map<String, Object?>>[];
}
