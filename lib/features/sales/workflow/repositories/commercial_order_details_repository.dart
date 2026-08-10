import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';
import 'package:quality_line_erp/features/sales/workflow/models/commercial_order_details.dart';

class CommercialOrderDetailsRepository {
  CommercialOrderDetailsRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String get _companyId =>
      CloudTenantContext.instance.companyUuid ??
      (throw StateError('لم يتم تحديد شركة سحابية.'));

  Future<CommercialOrderDetails> loadComplete({
    required String orderId,
    required bool purchase,
  }) async {
    final normalizedOrderId = orderId.trim();
    if (normalizedOrderId.isEmpty) {
      throw ArgumentError.value(orderId, 'orderId', 'معرف الأمر مطلوب.');
    }

    final value = await _client.rpc(
      'erp_r28_get_commercial_order_complete_details',
      params: <String, Object?>{
        'p_company_id': _companyId,
        'p_order_id': normalizedOrderId,
        'p_purchase': purchase,
      },
    );
    return CommercialOrderDetails.fromRpc(value);
  }
}
