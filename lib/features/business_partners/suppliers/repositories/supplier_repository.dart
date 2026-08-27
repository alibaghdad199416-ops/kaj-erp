import 'package:quality_line_erp/core/cloud/cloud_master_data_service.dart';
import 'package:quality_line_erp/features/business_partners/suppliers/models/supplier_model.dart';

/// Supabase-only supplier repository.
///
/// Supabase is the sole source of truth for supplier master data on every device.
class SupplierRepository {
  static const String _table = 'erp_suppliers';

  Future<List<SupplierModel>> getSuppliers() async {
    final rows = await CloudMasterDataService.instance.list(_table);
    return rows.map(SupplierModel.fromCloudMap).toList(growable: false);
  }

  Future<List<SupplierModel>> getActiveSuppliers() async {
    final suppliers = await getSuppliers();
    final active = suppliers.where((supplier) => supplier.isActive).toList();
    active.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return active;
  }

  Future<SupplierModel?> getSupplierById(String id) async {
    final row = await CloudMasterDataService.instance.getById(_table, id);
    return row == null ? null : SupplierModel.fromCloudMap(row);
  }

  Future<void> addSupplier(SupplierModel supplier) async {
    supplier.validate();
    await CloudMasterDataService.instance.upsert(
      _table,
      supplier.id,
      supplier.toCloudMap(),
    );
  }

  Future<void> updateSupplier(SupplierModel supplier) async {
    supplier.validate();
    final existing = await getSupplierById(supplier.id);
    if (existing == null) {
      throw StateError('تعذر العثور على المورد المطلوب تحديثه.');
    }
    final updated = supplier.copyWith(updatedAt: DateTime.now().toUtc());
    await CloudMasterDataService.instance.upsert(
      _table,
      updated.id,
      updated.toCloudMap(),
    );
  }

  Future<void> deleteSupplier(String id) async {
    final existing = await getSupplierById(id);
    if (existing == null) {
      throw StateError('تعذر العثور على المورد المطلوب حذفه.');
    }
    await CloudMasterDataService.instance.delete(_table, id);
  }

  Future<void> setSupplierActive({
    required String id,
    required bool isActive,
  }) async {
    final supplier = await getSupplierById(id);
    if (supplier == null) throw StateError('تعذر العثور على المورد.');
    await updateSupplier(supplier.copyWith(isActive: isActive));
  }

  Future<bool> phoneExists({
    required String phone,
    String? excludeSupplierId,
  }) async {
    final normalized = phone.trim();
    if (normalized.isEmpty) return false;
    final suppliers = await getSuppliers();
    return suppliers.any(
      (supplier) =>
          supplier.id != excludeSupplierId &&
          supplier.phone.trim() == normalized,
    );
  }

  Future<int> getSuppliersCount() async => (await getSuppliers()).length;

  Future<int> getActiveSuppliersCount() async =>
      (await getActiveSuppliers()).length;
}
