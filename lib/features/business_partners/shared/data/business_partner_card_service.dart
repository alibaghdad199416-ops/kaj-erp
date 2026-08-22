import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';
import 'package:quality_line_erp/core/logging/app_logger.dart';

class BusinessPartnerCardService {
  const BusinessPartnerCardService();

  Future<Map<String, Object?>> load({
    required String kind,
    required String partnerId,
  }) async {
    final companyId = CloudTenantContext.instance.companyUuid;
    if (companyId == null || companyId.isEmpty) return const {};
    try {
      final result = await Supabase.instance.client.rpc(
        'erp_r56_business_partner_360',
        params: {
          'p_company_id': companyId,
          'p_partner_kind': kind,
          'p_partner_id': partnerId,
        },
      );
      return result is Map ? Map<String, Object?>.from(result) : const {};
    } catch (error, stackTrace) {
      AppLogger.debug('Partner card summary fallback: $error\n$stackTrace');
      return const {};
    }
  }

  static List<Map<String, Object?>> documents(Map<String, Object?> summary) {
    final raw = summary['recentDocuments'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }

  static String currencies(Map<String, Object?> summary) {
    final raw = summary['currencies'];
    if (raw is! List || raw.isEmpty) {
      return summary['defaultCurrency']?.toString() ?? '—';
    }
    return raw.map((value) => value.toString()).join(' / ');
  }
}
