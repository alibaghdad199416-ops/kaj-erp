import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:quality_line_erp/core/cloud/cloud_master_data_service.dart';
import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';
import 'package:quality_line_erp/features/accounting/installments/models/installment_model.dart';
import 'package:quality_line_erp/features/sales/models/sale_model.dart';
import 'package:quality_line_erp/features/sales/models/sales_workflow_order_model.dart';

/// Supabase-only sales repository.
///
/// PostgreSQL is authoritative. Sale creation/deletion and car lifecycle
/// changes are executed atomically through RPC functions.
class SaleRepository {
  final CloudMasterDataService _cloud = CloudMasterDataService.instance;

  SupabaseClient get _client => Supabase.instance.client;

  String get _companyId {
    final value = CloudTenantContext.instance.companyUuid;
    if (value == null || value.isEmpty) {
      throw StateError('لم يتم تحديد شركة سحابية للمستخدم الحالي.');
    }
    return value;
  }

  Future<void> insertSale(SaleModel sale) =>
      createSaleWithInstallments(sale: sale, installments: const []);

  Future<void> createSaleWithInstallments({
    required SaleModel sale,
    required List<InstallmentModel> installments,
  }) async {
    _validateSale(sale, installments);
    await _client.rpc(
      'erp_r49_create_cloud_sale',
      params: {
        'p_company_id': _companyId,
        'p_sale': sale.toMap(),
        'p_installments': installments.map((item) => item.toMap()).toList(),
      },
    );
  }

  Future<void> createResale(SaleModel sale) async {
    if (!sale.isResale ||
        sale.previousSaleId == null ||
        sale.sellerCustomerId == null) {
      throw ArgumentError('بيانات إعادة البيع غير مكتملة.');
    }
    _validateSale(sale, const []);
    await _client.rpc(
      'erp_r49_create_cloud_resale',
      params: {'p_company_id': _companyId, 'p_sale': sale.toMap()},
    );
  }

  Future<SaleModel?> getLatestSaleForCar(String carId) async {
    final rows = await _cloud.listWhere(
      'erp_sales',
      field: 'carId',
      value: carId,
    );
    if (rows.isEmpty) return null;
    rows.sort((a, b) {
      final aSequence = (a['saleSequence'] as num?)?.toInt() ?? 1;
      final bSequence = (b['saleSequence'] as num?)?.toInt() ?? 1;
      final sequence = bSequence.compareTo(aSequence);
      if (sequence != 0) return sequence;
      return (b['saleDate']?.toString() ?? '').compareTo(
        a['saleDate']?.toString() ?? '',
      );
    });
    return SaleModel.fromMap(rows.first);
  }

  Future<void> updateSale(SaleModel sale) async {
    _validateSale(sale, const []);
    await _client.rpc(
      'erp_r49_update_cloud_sale',
      params: {'p_company_id': _companyId, 'p_sale': sale.toMap()},
    );
  }

  Future<void> deleteSale(String id) async {
    await _client.rpc(
      'erp_r92_delete_cloud_sale',
      params: {'p_company_id': _companyId, 'p_sale_id': id},
    );
  }

  Future<List<SaleModel>> getSales() async {
    final rows = await _cloud.list('erp_sales');
    rows.sort(
      (a, b) => (b['saleDate']?.toString() ?? '').compareTo(
        a['saleDate']?.toString() ?? '',
      ),
    );
    return rows.map(SaleModel.fromMap).toList(growable: false);
  }

  Future<List<SalesWorkflowOrder>> getSalesWorkflowOrders() async {
    final rows = await _client.rpc(
      'erp_list_cloud_sales_workflow_orders',
      params: {'p_company_id': _companyId},
    );
    rows.sort(
      (a, b) => (b['createdAt']?.toString() ?? '').compareTo(
        a['createdAt']?.toString() ?? '',
      ),
    );
    return rows.map(SalesWorkflowOrder.fromMap).toList(growable: false);
  }

  void _validateSale(SaleModel sale, List<InstallmentModel> installments) {
    if (sale.id.trim().isEmpty || sale.carId.trim().isEmpty) {
      throw ArgumentError('مرجع الفاتورة والسيارة غير صالح.');
    }
    if (sale.customerId.trim().isEmpty) {
      throw ArgumentError('يجب اختيار العميل.');
    }
    if (sale.salePrice < 0 || sale.paidAmount < 0 || sale.remainingAmount < 0) {
      throw ArgumentError('قيم فاتورة البيع لا يمكن أن تكون سالبة.');
    }
    if ((sale.paidAmount + sale.remainingAmount - sale.salePrice).abs() >
        0.01) {
      throw ArgumentError('مجموع المدفوع والمتبقي لا يطابق سعر البيع.');
    }
    final installmentTotal = installments.fold<double>(
      0,
      (total, item) => total + item.amount,
    );
    if (installments.isNotEmpty &&
        (installmentTotal - sale.remainingAmount).abs() > 0.01) {
      throw ArgumentError('إجمالي الأقساط لا يطابق المبلغ المتبقي.');
    }
  }
}
