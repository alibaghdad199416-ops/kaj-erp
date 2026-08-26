import 'package:quality_line_erp/core/cloud/cloud_master_data_service.dart';

/// Unified partner access layer used by ERP flows that address customers and suppliers together.
/// PostgreSQL/Supabase remains the authoritative source of truth.
class PartnersRepository {
  Future<List<Map<String, dynamic>>> listCustomers() async =>
      CloudMasterDataService.instance.list('erp_customers');

  Future<List<Map<String, dynamic>>> listSuppliers() async =>
      CloudMasterDataService.instance.list('erp_suppliers');

  Future<Map<String, dynamic>?> getCustomer(String id) =>
      CloudMasterDataService.instance.getById('erp_customers', id);

  Future<Map<String, dynamic>?> getSupplier(String id) =>
      CloudMasterDataService.instance.getById('erp_suppliers', id);
}
