import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quality_line_erp/core/cloud/cloud_feature_command.dart';
import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';
import 'package:quality_line_erp/features/customer_service/models/opportunity_model.dart';

class OpportunityRepository {
  final CloudFeatureCommand _cloud = CloudFeatureCommand.instance;

  Future<List<OpportunityModel>> getOpportunities() async {
    final companyId = CloudTenantContext.instance.companyUuid?.trim() ?? '';
    if (companyId.isEmpty) {
      throw StateError('لا توجد شركة سحابية نشطة.');
    }
    final rows = await Supabase.instance.client.rpc(
      'erp_r84_list_opportunities',
      params: {'p_company_id': companyId},
    );
    if (rows is! List) {
      throw StateError('تعذر تحميل فرص خدمة العملاء من Supabase.');
    }
    return rows
        .whereType<Map>()
        .map((row) => OpportunityModel.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<void> add(OpportunityModel opportunity) => _cloud.call(
    'opportunity',
    'save',
    payload: {'record': opportunity.toMap(), 'create_only': true},
  );

  Future<void> update(OpportunityModel opportunity) => _cloud.call(
    'opportunity',
    'save',
    payload: {
      'record': opportunity.toMap(),
      'create_only': false,
      'expected_updated_at': opportunity.updatedAt?.toUtc().toIso8601String(),
    },
  );

  Future<void> delete(OpportunityModel opportunity) => _cloud.call(
    'opportunity',
    'delete',
    payload: {
      'id': opportunity.id,
      'expected_updated_at': opportunity.updatedAt?.toUtc().toIso8601String(),
    },
  );

  Future<void> markLost(OpportunityModel opportunity) => _cloud.call(
    'opportunity',
    'mark_lost',
    payload: {
      'id': opportunity.id,
      'expected_updated_at': opportunity.updatedAt?.toUtc().toIso8601String(),
    },
  );
}
