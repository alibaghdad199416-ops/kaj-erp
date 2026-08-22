import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:quality_line_erp/core/logging/app_logger.dart';

import 'cloud_tenant_context.dart';
import 'supabase_config.dart';

Map<String, dynamic> selectCloudMembershipRow({
  required List<Map<String, dynamic>> memberships,
  String? persistedCompanyId,
}) {
  if (memberships.isEmpty) {
    throw StateError('No active cloud company membership is available.');
  }
  final normalizedPersisted = persistedCompanyId?.trim();
  final matchingPersisted =
      normalizedPersisted == null || normalizedPersisted.isEmpty
      ? <Map<String, dynamic>>[]
      : memberships
            .where(
              (row) => row['company_id']?.toString() == normalizedPersisted,
            )
            .toList(growable: false);
  if (memberships.length > 1 && matchingPersisted.isEmpty) {
    throw StateError(
      'للحساب عضويات في أكثر من شركة. يجب اختيار شركة نشطة قبل متابعة تسجيل الدخول.',
    );
  }
  return matchingPersisted.isNotEmpty
      ? matchingPersisted.single
      : memberships.single;
}

class CloudMembership {
  const CloudMembership({
    required this.companyId,
    required this.companySlug,
    required this.companyName,
    required this.roleCode,
    this.branchId,
    this.isSystemAdmin = false,
  });

  final String companyId;
  final String companySlug;
  final String companyName;
  final String roleCode;
  final String? branchId;
  final bool isSystemAdmin;
}

CloudMembership cloudMembershipFromRow(Map<String, dynamic> row) {
  final company = Map<String, dynamic>.from(row['companies'] as Map);
  return CloudMembership(
    companyId: row['company_id'].toString(),
    companySlug: company['slug'].toString(),
    companyName: (company['name_ar'] ?? company['name_en'] ?? '').toString(),
    branchId: row['default_branch_id']?.toString(),
    roleCode: (row['role_code'] ?? 'user').toString(),
    isSystemAdmin: row['is_system_admin'] == true,
  );
}

/// Resolves the active Supabase Auth user to a company membership.
class CloudTenantMembershipService {
  CloudTenantMembershipService._();

  static final CloudTenantMembershipService instance =
      CloudTenantMembershipService._();

  Future<CloudMembership> activateForCurrentUser() async {
    if (!SupabaseConfig.isConfigured) {
      throw StateError('Supabase غير مضبوط في نسخة البناء الحالية.');
    }
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      throw StateError('لا توجد جلسة Supabase فعالة.');
    }

    final rows = await client
        .from('company_memberships')
        .select(
          'company_id, default_branch_id, role_code, is_system_admin, '
          'companies!inner(slug, name_ar, name_en, is_active)',
        )
        .eq('user_id', user.id)
        .eq('is_active', true)
        .eq('companies.is_active', true)
        .order('company_id');

    if (rows.isEmpty) {
      throw StateError(
        'الحساب السحابي غير مرتبط بشركة في Supabase. '
        'اربط Supabase Auth UID بجدول company_memberships ثم أعد تسجيل الدخول.',
      );
    }

    final memberships = rows
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
    final row = selectCloudMembershipRow(
      memberships: memberships,
      persistedCompanyId: CloudTenantContext.instance.authUserId == user.id
          ? CloudTenantContext.instance.companyUuid
          : null,
    );
    final membership = cloudMembershipFromRow(row);

    await CloudTenantContext.instance.selectTenant(
      authUserId: user.id,
      companyId: membership.companySlug,
      branchId: membership.branchId,
      companyUuid: membership.companyId,
      roleCode: membership.roleCode,
      isSystemAdmin: membership.isSystemAdmin,
    );

    // Prepare the authoritative company runtime once per authenticated session.
    // This is idempotent and creates only missing cloud defaults (main branch,
    // warehouse, chart of accounts and cashboxes); it never falls back to local
    // storage.
    final prepared = await client.rpc(
      'erp_prepare_company_runtime',
      params: {'p_company_id': membership.companyId},
    );
    final result = Map<String, dynamic>.from(prepared as Map);
    final preparedBranchId = result['branchId']?.toString();
    var resolvedMembership = membership;
    if ((membership.branchId == null || membership.branchId!.isEmpty) &&
        preparedBranchId != null &&
        preparedBranchId.isNotEmpty) {
      await CloudTenantContext.instance.selectTenant(
        authUserId: user.id,
        companyId: membership.companySlug,
        branchId: preparedBranchId,
        companyUuid: membership.companyId,
        roleCode: membership.roleCode,
        isSystemAdmin: membership.isSystemAdmin,
      );
      resolvedMembership = CloudMembership(
        companyId: membership.companyId,
        companySlug: membership.companySlug,
        companyName: membership.companyName,
        roleCode: membership.roleCode,
        branchId: preparedBranchId,
        isSystemAdmin: membership.isSystemAdmin,
      );
    }

    // Database-attested runtime identity: a stale browser tenant is not allowed
    // to survive merely because its UUID still exists in the same project.
    final identityRaw = await client.rpc(
      'erp_r74_runtime_identity',
      params: {'p_company_id': resolvedMembership.companyId},
    );
    final identity = Map<String, dynamic>.from(identityRaw as Map);
    final attestedUserId = identity['authUserId']?.toString();
    final attestedCompanyId = identity['companyId']?.toString();
    if (attestedUserId != user.id ||
        attestedCompanyId != resolvedMembership.companyId) {
      await CloudTenantContext.instance.clearCloudSelection();
      throw StateError('R74 runtime identity mismatch.');
    }

    AppLogger.debug(
      'R74 runtime identity: project=${SupabaseConfig.projectRef}; '
      'authUser=${user.id}; company=${resolvedMembership.companyId}; '
      'slug=${resolvedMembership.companySlug}; '
      'name=${resolvedMembership.companyName}; '
      'databaseContract=${identity['databaseContract']}',
    );
    return resolvedMembership;
  }
}
