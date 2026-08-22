import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';
import 'package:quality_line_erp/core/events/app_data_change_bus.dart';

/// Supabase-only professional accounting operations.
class ProfessionalAccountingRepository {
  static const Uuid _uuid = Uuid();
  SupabaseClient get _client => Supabase.instance.client;

  String get _companyId {
    final id = CloudTenantContext.instance.companyUuid;
    if (id == null || id.isEmpty) {
      throw StateError('لم يتم تحديد شركة سحابية للمستخدم الحالي.');
    }
    return id;
  }

  Future<List<Map<String, Object?>>> getFiscalYears() =>
      _listProfessionalRecords('fiscal_years');

  Future<List<Map<String, Object?>>> getFiscalPeriods(String fiscalYearId) =>
      _listProfessionalRecords('fiscal_periods', parentId: fiscalYearId);

  Future<Map<String, Object?>> resolveOpenPeriod(DateTime entryDate) async {
    final result = await _client.rpc(
      'erp_resolve_cloud_open_period',
      params: {
        'p_company_id': _companyId,
        'p_entry_date': entryDate.toUtc().toIso8601String(),
      },
    );
    return Map<String, Object?>.from(result as Map);
  }

  Future<void> assignEntryDimensions({
    required String entryId,
    required DateTime entryDate,
    String? costCenterId,
    String? projectId,
  }) async {
    await _client.rpc(
      'erp_r49_assign_cloud_entry_dimensions',
      params: {
        'p_company_id': _companyId,
        'p_entry_id': entryId,
        'p_entry_date': entryDate.toUtc().toIso8601String(),
        'p_cost_center_id': costCenterId,
        'p_project_id': projectId,
      },
    );
    _publishAccounting('entry-dimensions');
  }

  Future<void> setPeriodStatus({
    required String periodId,
    required String status,
    required String userId,
  }) async {
    await _client.rpc(
      'erp_r49_change_cloud_fiscal_period_status',
      params: {
        'p_company_id': _companyId,
        'p_period_id': periodId,
        'p_new_status': status == 'locked' ? 'closed' : status,
        'p_performed_by': userId,
        'p_reason': status == 'open'
            ? 'إعادة فتح من مركز المحاسبة'
            : 'إغلاق من مركز المحاسبة',
      },
    );
    _publishAccounting('fiscal-period-status', settings: true);
  }

  Future<List<Map<String, Object?>>> getBranches() async {
    final result = await _client.rpc(
      'erp_r92_list_accounting_branches',
      params: {'p_company_id': _companyId},
    );
    return List<Map<String, Object?>>.from(
      (result as List).map((e) => Map<String, Object?>.from(e as Map)),
    );
  }

  Future<List<Map<String, Object?>>> getCostCenters() =>
      _listProfessionalRecords('cost_centers');
  Future<List<Map<String, Object?>>> getProjects() =>
      _listProfessionalRecords('accounting_projects');

  Future<List<Map<String, Object?>>> getCashFlowCashboxes() async {
    final result = await _client.rpc(
      'erp_r89_list_cashboxes_for_cash_flow',
      params: {'p_company_id': _companyId},
    );
    return List<Map<String, Object?>>.from(
      (result as List).map((row) => Map<String, Object?>.from(row as Map)),
    );
  }

  Future<String> addBranch({
    required String code,
    required String nameAr,
    required String nameEn,
    bool isMain = false,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.rpc(
      'erp_save_cloud_branch',
      params: {
        'p_id': id,
        'p_name': nameAr.trim(),
        'p_code': code.trim().toUpperCase(),
        'p_phone': '',
        'p_address': '',
        'p_is_main': isMain,
        'p_is_active': true,
        'p_created_at': now,
        'p_updated_at': now,
      },
    );
    _publishAccounting('branch-insert', settings: true, access: true);
    return id;
  }

  Future<String> addCostCenter({
    required String code,
    required String nameAr,
    required String nameEn,
    String? parentId,
  }) async {
    final id = _uuid.v4();
    await _client.rpc(
      'erp_r49_save_cloud_cost_center',
      params: {
        'p_company_id': _companyId,
        'p_cost_center': {
          'id': id,
          'code': code.trim().toUpperCase(),
          'nameAr': nameAr.trim(),
          'nameEn': nameEn.trim().isEmpty ? nameAr.trim() : nameEn.trim(),
          'parentId': parentId,
          'isActive': true,
        },
      },
    );
    _publishAccounting('cost-center-insert', settings: true);
    return id;
  }

  Future<String> addProject({
    required String code,
    required String nameAr,
    required String nameEn,
    required String currency,
    double budgetAmount = 0,
    String? customerId,
  }) async {
    final id = _uuid.v4();
    await _client.rpc(
      'erp_r49_save_cloud_accounting_project',
      params: {
        'p_company_id': _companyId,
        'p_project': {
          'id': id,
          'code': code.trim().toUpperCase(),
          'nameAr': nameAr.trim(),
          'nameEn': nameEn.trim(),
          'currency': currency,
          'budgetAmount': budgetAmount,
          'customerId': customerId,
          'status': 'active',
        },
      },
    );
    _publishAccounting('project-insert', settings: true);
    return id;
  }

  Future<String> postRecurringTemplate({
    required String templateId,
    required DateTime postingDate,
    required String userId,
  }) async {
    final result = await _client.rpc(
      'erp_r49_post_cloud_recurring_template',
      params: {
        'p_company_id': _companyId,
        'p_template_id': templateId,
        'p_posting_date': postingDate.toUtc().toIso8601String(),
        'p_user_id': userId,
      },
    );
    _publishAccounting('recurring-template-post');
    return result.toString();
  }

  Future<void> closeFiscalYear({
    required String fiscalYearId,
    required String retainedEarningsAccountId,
    required String userId,
  }) async {
    await _client.rpc(
      'erp_r49_close_cloud_fiscal_year',
      params: {
        'p_company_id': _companyId,
        'p_fiscal_year_id': fiscalYearId,
        'p_retained_earnings_account_id': retainedEarningsAccountId,
        'p_user_id': userId,
      },
    );
    _publishAccounting('fiscal-year-close', settings: true);
  }

  Future<List<Map<String, Object?>>> loadReport({
    required String type,
    String currency = 'ALL',
    String? cashAccountId,
    String? branchId,
    String? costCenterId,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    final toDateValue = toDate == null
        ? null
        : DateTime(
            toDate.year,
            toDate.month,
            toDate.day,
            23,
            59,
            59,
            999,
          ).toUtc().toIso8601String();
    final result = await _client
        .rpc(
          type == 'cashFlow'
              ? 'erp_r89_cloud_cash_flow_hierarchy'
              : 'erp_r22_cloud_detailed_accounting_report',
          params: type == 'cashFlow'
              ? {
                  'p_company_id': _companyId,
                  'p_currency': currency,
                  'p_cash_account_id': cashAccountId,
                  'p_branch_id': branchId,
                  'p_cost_center_id': costCenterId,
                  'p_from_date': fromDate?.toUtc().toIso8601String(),
                  'p_to_date': toDateValue,
                }
              : {
                  'p_company_id': _companyId,
                  'p_report_type': type,
                  'p_currency': currency,
                  'p_branch_id': branchId,
                  'p_cost_center_id': costCenterId,
                  'p_from_date': fromDate?.toUtc().toIso8601String(),
                  'p_to_date': toDateValue,
                },
        )
        .timeout(const Duration(seconds: 40));
    return List<Map<String, Object?>>.from(
      (result as List).map((e) => Map<String, Object?>.from(e as Map)),
    );
  }

  void _publishAccounting(
    String operation, {
    bool settings = false,
    bool access = false,
  }) {
    AppDataChangeBus.instance.publish('accounting', operation: operation);
    if (settings) {
      AppDataChangeBus.instance.publish('settings', operation: operation);
    }
    if (access) {
      AppDataChangeBus.instance.publish('access', operation: operation);
    }
  }

  Future<List<Map<String, Object?>>> _listProfessionalRecords(
    String kind, {
    String? parentId,
  }) async {
    final result = await _client.rpc(
      'erp_r92_list_professional_accounting_records',
      params: {
        'p_company_id': _companyId,
        'p_kind': kind,
        'p_parent_id': parentId,
      },
    );
    return List<Map<String, Object?>>.from(
      (result as List).map((e) => Map<String, Object?>.from(e as Map)),
    );
  }
}
