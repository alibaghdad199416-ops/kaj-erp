import 'package:quality_line_erp/core/cloud/cloud_master_data_service.dart';
import 'package:quality_line_erp/features/business_partners/customers/models/customer_model.dart';

/// Supabase-only customer repository.
///
/// PostgreSQL is authoritative. Media is verified after every write so a field
/// permission mapper, stale migration, or payload regression can never silently
/// accept the customer while dropping the selected photo.
class CustomerRepository {
  static const String _table = 'erp_customers';

  Future<void> _saveAndVerify(CustomerModel customer) async {
    final cloud = CloudMasterDataService.instance;
    await cloud.upsert(_table, customer.id, customer.toCloudMap());
    final persisted = await cloud.getById(_table, customer.id);
    if (persisted == null) {
      throw StateError('تم إرسال بيانات العميل ولكن تعذر قراءتها بعد الحفظ.');
    }
    final expected = customer.photoBase64?.trim() ?? '';
    final actual = (persisted['photo_base64'] ?? persisted['photoBase64'] ?? '')
        .toString()
        .trim();
    if (actual != expected) {
      throw StateError(
        'لم يتم تثبيت صورة العميل في Supabase. تم إيقاف الحفظ لمنع نجاح شكلي بدون الصورة.',
      );
    }
  }

  Future<void> insertCustomer(CustomerModel customer) async {
    customer.validate();
    await _saveAndVerify(customer);
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
    await _saveAndVerify(customer);
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
