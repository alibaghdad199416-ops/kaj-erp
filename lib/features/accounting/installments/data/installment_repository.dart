import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';
import 'package:quality_line_erp/features/accounting/installments/models/installment_model.dart';

/// Supabase-only installment repository.
class InstallmentRepository {
  SupabaseClient get _client => Supabase.instance.client;

  String get _companyId {
    final value = CloudTenantContext.instance.companyUuid;
    if (value == null || value.isEmpty) {
      throw StateError('لم يتم تحديد شركة سحابية للمستخدم الحالي.');
    }
    return value;
  }

  Future<List<InstallmentModel>> getInstallments() async {
    final rows = await _client.rpc(
      'erp_r49_list_installments',
      params: {'p_company_id': _companyId},
    );
    return (rows as List)
        .map(
          (row) =>
              InstallmentModel.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);
  }

  Future<List<InstallmentModel>> getInstallmentsBySale(String saleId) async {
    final rows = await getInstallments();
    return rows.where((item) => item.saleId == saleId).toList(growable: false)
      ..sort((a, b) => a.installmentNo.compareTo(b.installmentNo));
  }

  // Installment schedules are sales-workflow owned. Collections are posted
  // through canonical payment operations; this repository intentionally exposes
  // read-only schedule access.
}
