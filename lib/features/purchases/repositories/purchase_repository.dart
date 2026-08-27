import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:quality_line_erp/core/cloud/cloud_master_data_service.dart';
import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';
import 'package:quality_line_erp/features/purchases/models/purchase_item_model.dart';
import 'package:quality_line_erp/features/purchases/models/purchase_model.dart';

/// Supabase-only purchases repository.
///
/// Purchase headers, items and related car state changes are committed in one
/// PostgreSQL transaction through RPC functions.
class PurchaseRepository {
  final CloudMasterDataService _cloud = CloudMasterDataService.instance;

  SupabaseClient get _client => Supabase.instance.client;

  String get _companyId {
    final value = CloudTenantContext.instance.companyUuid;
    if (value == null || value.isEmpty) {
      throw StateError('لم يتم تحديد شركة سحابية للمستخدم الحالي.');
    }
    return value;
  }

  static const String purchasesTable = 'erp_purchases';
  static const String purchaseItemsTable = 'erp_purchase_items';

  Future<List<PurchaseModel>> getPurchases() async {
    final rows = await _cloud.list(purchasesTable);
    rows.sort(
      (a, b) => (b['purchaseDate']?.toString() ?? '').compareTo(
        a['purchaseDate']?.toString() ?? '',
      ),
    );
    return rows.map(PurchaseModel.fromMap).toList(growable: false);
  }

  Future<PurchaseModel?> getPurchaseById(String purchaseId) async {
    final row = await _cloud.getById(purchasesTable, purchaseId);
    return row == null ? null : PurchaseModel.fromMap(row);
  }

  Future<List<PurchaseModel>> getPurchasesBySupplier(String supplierId) async {
    final rows = await _cloud.listWhere(
      purchasesTable,
      field: 'supplierId',
      value: supplierId,
    );
    rows.sort(
      (a, b) => (b['purchaseDate']?.toString() ?? '').compareTo(
        a['purchaseDate']?.toString() ?? '',
      ),
    );
    return rows.map(PurchaseModel.fromMap).toList(growable: false);
  }

  Future<List<PurchaseItemModel>> getPurchaseItems(String purchaseId) async {
    final rows = await _cloud.listWhere(
      purchaseItemsTable,
      field: 'purchaseId',
      value: purchaseId,
    );
    rows.sort(
      (a, b) => (a['createdAt']?.toString() ?? '').compareTo(
        b['createdAt']?.toString() ?? '',
      ),
    );
    return rows.map(PurchaseItemModel.fromMap).toList(growable: false);
  }

  Future<PurchaseItemModel?> getPurchaseItemById(String itemId) async {
    final row = await _cloud.getById(purchaseItemsTable, itemId);
    return row == null ? null : PurchaseItemModel.fromMap(row);
  }

  Future<void> addPurchase({
    required PurchaseModel purchase,
    required List<PurchaseItemModel> items,
  }) async {
    _validatePurchase(purchase: purchase, items: items);
    await _client.rpc(
      'erp_r49_create_cloud_purchase',
      params: {
        'p_company_id': _companyId,
        'p_purchase': purchase.toMap(),
        'p_items': items.map((item) => item.toMap()).toList(),
      },
    );
  }

  Future<void> updatePurchase({
    required PurchaseModel purchase,
    required List<PurchaseItemModel> items,
  }) async {
    _validatePurchase(purchase: purchase, items: items);
    await _client.rpc(
      'erp_r49_update_cloud_purchase',
      params: {
        'p_company_id': _companyId,
        'p_purchase': purchase.toMap(),
        'p_items': items.map((item) => item.toMap()).toList(),
      },
    );
  }

  Future<void> deletePurchase(String purchaseId) async {
    await _client.rpc(
      'erp_delete_cloud_purchase',
      params: {'p_company_id': _companyId, 'p_purchase_id': purchaseId},
    );
  }

  Future<bool> invoiceNumberExists(
    String invoiceNumber, {
    String? excludePurchaseId,
  }) async {
    final rows = await _cloud.list(purchasesTable);
    final normalized = invoiceNumber.trim().toLowerCase();
    return rows.any(
      (row) =>
          row['id']?.toString() != excludePurchaseId &&
          (row['invoiceNumber']?.toString().trim().toLowerCase() ?? '') ==
              normalized,
    );
  }

  Future<int> getPurchasesCount() async => (await getPurchases()).length;

  void _validatePurchase({
    required PurchaseModel purchase,
    required List<PurchaseItemModel> items,
  }) {
    if (purchase.id.trim().isEmpty || purchase.invoiceNumber.trim().isEmpty) {
      throw ArgumentError('معرف ورقم فاتورة الشراء مطلوبان.');
    }
    if (purchase.supplierId.trim().isEmpty) {
      throw ArgumentError('يجب اختيار المورد.');
    }
    if (purchase.totalAmount < 0 ||
        purchase.paidAmount < 0 ||
        purchase.remainingAmount < 0) {
      throw ArgumentError('قيم فاتورة الشراء لا يمكن أن تكون سالبة.');
    }
    if (purchase.paidAmount > purchase.totalAmount) {
      throw ArgumentError('المبلغ المدفوع لا يمكن أن يتجاوز الإجمالي.');
    }
    if (items.isEmpty) {
      throw ArgumentError('يجب إضافة سيارة واحدة على الأقل إلى الفاتورة.');
    }
    final itemIds = <String>{};
    final carIds = <String>{};
    for (final item in items) {
      if (item.purchaseId != purchase.id) {
        throw ArgumentError('يوجد عنصر غير مرتبط بفاتورة الشراء الحالية.');
      }
      if (!itemIds.add(item.id) || !carIds.add(item.carId)) {
        throw ArgumentError('يوجد عنصر أو سيارة مكررة داخل الفاتورة.');
      }
      if (item.purchasePrice < 0 ||
          item.additionalCosts < 0 ||
          item.totalCost < 0) {
        throw ArgumentError('قيم تكلفة السيارة يجب ألا تكون سالبة.');
      }
    }
    final calculatedTotal = items.fold<double>(
      0,
      (total, item) => total + item.totalCost,
    );
    if ((calculatedTotal - purchase.totalAmount).abs() > 0.01) {
      throw ArgumentError('إجمالي الفاتورة لا يطابق إجمالي السيارات.');
    }
    if ((purchase.totalAmount - purchase.paidAmount - purchase.remainingAmount)
            .abs() >
        0.01) {
      throw ArgumentError('المبلغ المتبقي في الفاتورة غير صحيح.');
    }
  }
}
