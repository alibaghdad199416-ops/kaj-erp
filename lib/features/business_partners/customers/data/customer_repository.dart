import 'package:quality_line_erp/core/cloud/cloud_master_data_service.dart';
import 'package:quality_line_erp/features/business_partners/customers/models/customer_model.dart';

/// Supabase-only customer repository.
///
/// PostgreSQL is authoritative. A failed cloud request is surfaced to the UI;
/// customer data is read from and written to Supabase only.
class CustomerRepository {
  static const String _table = 'erp_customers';

  Future<void> insertCustomer(CustomerModel customer) async {
    customer.validate();
    await CloudMasterDataService.instance.upsert(
      _table,
      customer.id,
      customer.toCloudMap(),
    );
  }

  Future<void> updateCustomer(CustomerModel customer) async {
    customer.validate();
    final existing = await CloudMasterDataService.instance.getById(
      _table,
      customer.id,
    );
    if (existing == null) {
      throw StateError('تعذر العثور على العميل المطلوب تحديثه.');
    }
    await CloudMasterDataService.instance.upsert(
      _table,
      customer.id,
      customer.toCloudMap(),
    );
  }

  Future<void> deleteCustomer(String id) async {
    final existing = await CloudMasterDataService.instance.getById(_table, id);
    if (existing == null) {
      throw StateError('تعذر العثور على العميل المطلوب حذفه.');
    }
    await CloudMasterDataService.instance.delete(_table, id);
  }

  Future<List<CustomerModel>> getCustomers() async {
    final rows = await CloudMasterDataService.instance.list(_table);
    return rows.map(CustomerModel.fromCloudMap).toList(growable: false);
  }
}
