import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';
import 'package:quality_line_erp/features/inventory/asset_history/models/asset_history_event.dart';

class AssetHistoryRepository {
  SupabaseClient get _client => Supabase.instance.client;

  String get _companyId {
    final value = CloudTenantContext.instance.companyUuid;
    if (value == null || value.isEmpty) {
      throw StateError('لم يتم تحديد شركة سحابية للمستخدم الحالي.');
    }
    return value;
  }

  Future<List<AssetHistoryEvent>> carHistory(String carId) async {
    final result = await _client.rpc(
      'erp_cloud_car_history',
      params: {'p_company_id': _companyId, 'p_car_id': carId},
    );
    return (result as List)
        .map((raw) {
          final row = Map<String, Object?>.from(raw as Map);
          final before = '${row['statusBefore'] ?? ''}'.trim();
          final after = '${row['statusAfter'] ?? ''}'.trim();
          final fromWarehouse = '${row['warehouseBeforeName'] ?? ''}'.trim();
          final toWarehouse = '${row['warehouseAfterName'] ?? ''}'.trim();
          final parts = <String>[];
          if (before.isNotEmpty || after.isNotEmpty) {
            parts.add(
              'الحالة: ${before.isEmpty ? '—' : before} ← ${after.isEmpty ? '—' : after}',
            );
          }
          if (fromWarehouse.isNotEmpty || toWarehouse.isNotEmpty) {
            parts.add(
              'المخزن: ${fromWarehouse.isEmpty ? '—' : fromWarehouse} ← ${toWarehouse.isEmpty ? '—' : toWarehouse}',
            );
          }
          final notes = '${row['notes'] ?? ''}'.trim();
          if (notes.isNotEmpty) parts.add(notes);
          final refType = '${row['referenceType'] ?? ''}'.trim();
          final refId = '${row['referenceId'] ?? ''}'.trim();
          final eventType = '${row['eventType'] ?? ''}';
          return AssetHistoryEvent(
            title: _carEventLabel(eventType),
            date: DateTime.tryParse('${row['eventDate']}'),
            details: parts.isEmpty ? 'لا توجد تفاصيل إضافية' : parts.join('\n'),
            reference: refType.isEmpty && refId.isEmpty
                ? null
                : '${_referenceLabel(refType)} • $refId',
            eventType: eventType,
            statusBefore: before.isEmpty ? null : before,
            statusAfter: after.isEmpty ? null : after,
            warehouseBefore: fromWarehouse.isEmpty ? null : fromWarehouse,
            warehouseAfter: toWarehouse.isEmpty ? null : toWarehouse,
          );
        })
        .toList(growable: false);
  }

  Future<List<AssetHistoryEvent>> productHistory(String productId) async {
    final result = await _client.rpc(
      'erp_r28_inventory_movement_log',
      params: {'p_company_id': _companyId, 'p_product_id': productId},
    );
    return (result as List)
        .map((raw) {
          final row = Map<String, Object?>.from(raw as Map);
          final movementType =
              '${row['movementType'] ?? row['movement_type'] ?? ''}';
          num? number(Object? value) =>
              value is num ? value : num.tryParse('${value ?? ''}');
          final quantity = number(row['quantity']);
          final unitCost = number(row['unitCost'] ?? row['unit_cost']);
          final totalCost = number(row['totalCost'] ?? row['total_cost']);
          final warehouse = '${row['warehouseName'] ?? ''}'.trim();
          final source = '${row['sourceName'] ?? ''}'.trim();
          final destination = '${row['destinationName'] ?? ''}'.trim();
          final performedBy = '${row['performedBy'] ?? ''}'.trim();
          final reference =
              '${row['referenceDocumentNumber'] ?? row['movementNumber'] ?? ''}'
                  .trim();
          final details = <String>[
            'النوع: ${_movementLabel(movementType)}',
            'الكمية: ${quantity ?? 0}',
            if (source.isNotEmpty) 'من: $source',
            if (destination.isNotEmpty) 'إلى: $destination',
            if (performedBy.isNotEmpty) 'المنفذ: $performedBy',
            if (unitCost != null) 'كلفة الوحدة: $unitCost',
            if (totalCost != null) 'الكلفة الإجمالية: $totalCost',
          ];
          return AssetHistoryEvent(
            title: _movementLabel(movementType),
            date: DateTime.tryParse(
              '${row['movementDate'] ?? row['operationalAt'] ?? ''}',
            ),
            details: details.join('\n'),
            reference: reference.isEmpty ? null : reference,
            eventType: movementType,
            warehouseAfter: warehouse.isEmpty ? null : warehouse,
            productName: '${row['productName'] ?? ''}'.trim(),
            quantity: quantity,
            unitCost: unitCost,
            totalCost: totalCost,
            sourceName: source.isEmpty ? null : source,
            destinationName: destination.isEmpty ? null : destination,
            performedBy: performedBy.isEmpty ? null : performedBy,
            referenceDocumentNumber: reference.isEmpty ? null : reference,
          );
        })
        .toList(growable: false);
  }

  static String _carEventLabel(String value) => switch (value) {
    'created' => 'إنشاء السيارة',
    'purchase_confirmed' => 'اعتماد شراء السيارة',
    'purchase_cancelled' => 'إلغاء شراء السيارة',
    'reserved' => 'حجز السيارة',
    'reservation_cancelled' => 'إلغاء حجز السيارة',
    'sale_confirmed' => 'بيع السيارة',
    'sale_cancelled' => 'إلغاء بيع السيارة',
    'transferred' => 'نقل السيارة',
    _ => 'تحديث دورة السيارة',
  };

  static String _movementLabel(String value) => switch (value) {
    'opening' => 'رصيد افتتاحي',
    'purchase' => 'استلام شراء',
    'purchase_cancel' => 'عكس استلام شراء',
    'sale' => 'صرف بيع',
    'sale_cancel' => 'عكس صرف بيع',
    'transfer_in' => 'نقل وارد',
    'transfer_out' => 'نقل صادر',
    'maintenance_out' => 'صرف صيانة',
    'maintenance_return' => 'عكس صرف صيانة',
    'adjustment_in' => 'تسوية زيادة',
    'adjustment_out' => 'تسوية نقص',
    _ => 'حركة مخزنية',
  };

  static String _referenceLabel(String value) => switch (value) {
    'sale' => 'بيع',
    'purchase' => 'شراء',
    'transfer' => 'نقل',
    'adjustment' => 'تسوية',
    'maintenance_order' => 'أمر صيانة',
    _ => value,
  };
}
