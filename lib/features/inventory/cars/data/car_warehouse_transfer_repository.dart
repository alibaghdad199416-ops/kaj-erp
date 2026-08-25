import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:quality_line_erp/core/cloud/cloud_master_data_service.dart';
import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';

/// Supabase-only car warehouse transfer repository.
/// Mutating operations are delegated to PostgreSQL RPCs so the transfer row,
/// vehicle warehouse and reversal state change atomically.
class CarWarehouseTransferRepository {
  final CloudMasterDataService _cloud = CloudMasterDataService.instance;

  String get _companyId {
    final id = CloudTenantContext.instance.companyUuid;
    if (id == null || id.isEmpty) throw StateError('لم يتم تحديد الشركة.');
    return id;
  }

  Future<List<Map<String, Object?>>> listTransfers() async {
    final results = await Future.wait([
      _cloud.list('erp_car_warehouse_transfers'),
      _cloud.list('erp_cars'),
      _cloud.list('erp_warehouses'),
    ]);
    final rows = results[0];
    final cars = <String, Map<String, dynamic>>{
      for (final row in results[1]) row['id']?.toString() ?? '': row,
    };
    final warehouses = <String, Map<String, dynamic>>{
      for (final row in results[2]) row['id']?.toString() ?? '': row,
    };
    return rows
        .map<Map<String, Object?>>((raw) {
          final row = Map<String, Object?>.from(raw);
          final carId =
              row['carId']?.toString() ?? row['car_id']?.toString() ?? '';
          final car = cars[carId] ?? const <String, dynamic>{};
          final fromId =
              row['fromWarehouseId']?.toString() ??
              row['from_warehouse_id']?.toString() ??
              '';
          final toId =
              row['toWarehouseId']?.toString() ??
              row['to_warehouse_id']?.toString() ??
              '';
          final fromWarehouse = warehouses[fromId] ?? const <String, dynamic>{};
          final toWarehouse = warehouses[toId] ?? const <String, dynamic>{};
          final currentWarehouseId =
              car['warehouseId']?.toString() ??
              car['warehouse_id']?.toString() ??
              '';
          final currentWarehouse =
              warehouses[currentWarehouseId] ?? const <String, dynamic>{};
          Object? first(Object? current, List<String> keys) {
            final text = current?.toString().trim() ?? '';
            if (text.isNotEmpty && text.toLowerCase() != 'null') return current;
            for (final key in keys) {
              final value = car[key];
              final candidate = value?.toString().trim() ?? '';
              if (candidate.isNotEmpty && candidate.toLowerCase() != 'null') {
                return value;
              }
            }
            return current;
          }

          return <String, Object?>{
            ...row,
            'carId': carId,
            'fromWarehouseId': fromId,
            'toWarehouseId': toId,
            'fromWarehouseName':
                row['fromWarehouseName'] ?? fromWarehouse['name'],
            'fromWarehouseCode': fromWarehouse['code'],
            'fromWarehouseAddress': fromWarehouse['address'],
            'toWarehouseName': row['toWarehouseName'] ?? toWarehouse['name'],
            'toWarehouseCode': toWarehouse['code'],
            'toWarehouseAddress': toWarehouse['address'],
            'currentWarehouseId': currentWarehouseId,
            'currentWarehouseName': currentWarehouse['name'],
            'vehicleType': first(row['vehicleType'], const [
              'vehicleType',
              'vehicle_type',
            ]),
            'brand': first(row['brand'], const ['brand', 'make']),
            'model': first(row['model'], const ['model']),
            'year': first(row['year'], const ['year']),
            'color': first(row['color'], const ['color']),
            'chassis': first(row['chassis'], const ['chassis', 'vin']),
            'engineNumber': first(row['engineNumber'], const [
              'engineNumber',
              'engine_number',
              'engine_no',
            ]),
            'plateNumber': first(row['plateNumber'], const [
              'plateNumber',
              'plate_number',
              'plate',
            ]),
            'carNumber': first(row['carNumber'], const [
              'carNumber',
              'car_number',
            ]),
            'purchasePrice': first(row['purchasePrice'], const [
              'purchasePrice',
              'purchase_price',
              'costPrice',
            ]),
            'maintenanceCost': first(row['maintenanceCost'], const [
              'maintenanceCost',
              'maintenance_cost',
            ]),
            'currency': first(row['currency'], const [
              'currency',
              'costCurrency',
              'cost_currency',
            ]),
            'carStatus': first(row['carStatus'], const ['status']),
          };
        })
        .toList(growable: false);
  }

  Future<Map<String, Object?>> createBatch({
    required List<Map<String, Object?>> transferLines,
    required String toWarehouseId,
    required String userName,
    required DateTime effectiveAt,
    String? notes,
  }) async {
    if (transferLines.isEmpty) {
      throw ArgumentError('يجب إضافة سيارة واحدة على الأقل');
    }
    final result = await Supabase.instance.client.rpc(
      'erp_r49_create_car_warehouse_transfer_batch',
      params: {
        'p_company_id': _companyId,
        'p_lines': transferLines,
        'p_to_warehouse_id': toWarehouseId,
        'p_user_name': userName,
        'p_notes': notes,
        'p_effective_at': effectiveAt.toUtc().toIso8601String(),
      },
    );
    if (result is Map) return Map<String, Object?>.from(result);
    throw StateError('لم تُرجع خدمة النقل رقم سند صالحاً');
  }

  Future<String> create({
    required String carId,
    required String toWarehouseId,
    required String userId,
    required String userName,
    DateTime? effectiveAt,
    String? notes,
  }) async {
    final result = await Supabase.instance.client.rpc(
      'erp_r49_create_car_warehouse_transfer',
      params: {
        'p_company_id': _companyId,
        'p_car_id': carId,
        'p_to_warehouse_id': toWarehouseId,
        'p_user_name': userName,
        'p_notes': notes,
        'p_effective_at': (effectiveAt ?? DateTime.now())
            .toUtc()
            .toIso8601String(),
      },
    );
    if (result is Map) {
      final id = result['id']?.toString();
      if (id != null && id.isNotEmpty) return id;
    }
    throw StateError('لم تُرجع خدمة النقل رقم سند صالحاً');
  }

  Future<void> update({
    required String id,
    required String carId,
    required String toWarehouseId,
    required String userId,
    required String userName,
    String? notes,
  }) async {
    await Supabase.instance.client.rpc(
      'erp_r49_edit_car_warehouse_transfer',
      params: {
        'p_company_id': _companyId,
        'p_transfer_id': id,
        'p_car_id': carId,
        'p_to_warehouse_id': toWarehouseId,
        'p_user_name': userName,
        'p_notes': notes,
      },
    );
  }

  Future<void> reverse({
    required String id,
    required String userId,
    required String userName,
  }) async {
    await Supabase.instance.client.rpc(
      'erp_r49_reverse_car_warehouse_transfer',
      params: {
        'p_company_id': _companyId,
        'p_transfer_id': id,
        'p_user_name': userName,
      },
    );
  }

  Future<void> delete({required String id, required String userName}) async {
    await Supabase.instance.client.rpc(
      'erp_delete_car_warehouse_transfer',
      params: {
        'p_company_id': _companyId,
        'p_transfer_id': id,
        'p_user_name': userName,
      },
    );
  }
}
