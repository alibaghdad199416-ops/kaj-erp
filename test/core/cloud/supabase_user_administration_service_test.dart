import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';
import 'package:quality_line_erp/core/cloud/supabase_user_administration_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const companyB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  late List<({String functionName, Map<String, dynamic> body})> calls;
  late SupabaseUserAdministrationService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CloudTenantContext.instance.clearCloudSelection();
    await CloudTenantContext.instance.selectTenant(
      companyId: 'company-b',
      companyUuid: companyB,
      roleCode: 'owner',
      isSystemAdmin: true,
    );
    calls = [];
    service = SupabaseUserAdministrationService.forTesting(
      functionInvoker: (functionName, body) async {
        calls.add((functionName: functionName, body: body));
        return functionName == 'admin-create-user'
            ? {'ok': true, 'user_id': 'cloud-user'}
            : {'ok': true};
      },
    );
  });

  test('create request carries the canonical active company UUID', () async {
    await service.createUser(
      email: 'user@example.com',
      password: 'password1',
      fullName: 'User',
      localUserId: 'local-user',
      roleCode: 'user',
      erpUserPayload: {'id': 'local-user', 'roleId': 'role-user'},
    );

    expect(calls.single.functionName, 'admin-create-user');
    expect(calls.single.body['company_id'], companyB);
  });

  test('update request carries the canonical active company UUID', () async {
    await service.updateUser(
      cloudUserId: 'cloud-user',
      localUserId: 'local-user',
      email: 'user@example.com',
      fullName: 'User',
      roleCode: 'user',
      isActive: true,
      erpUserPayload: {'id': 'local-user', 'roleId': 'role-user'},
    );

    expect(calls.single.functionName, 'admin-manage-user');
    expect(calls.single.body['company_id'], companyB);
  });

  test('delete request carries the canonical active company UUID', () async {
    await service.deleteUser(
      cloudUserId: 'cloud-user',
      localUserId: 'local-user',
    );

    expect(calls.single.functionName, 'admin-manage-user');
    expect(calls.single.body['company_id'], companyB);
  });

  test('missing active tenant is rejected before remote invocation', () async {
    await CloudTenantContext.instance.clearCloudSelection();

    expect(
      () => service.deleteUser(
        cloudUserId: 'cloud-user',
        localUserId: 'local-user',
      ),
      throwsA(isA<StateError>()),
    );
    expect(calls, isEmpty);
  });

  test('missing hosted function reports the deployment boundary', () async {
    final unavailable = SupabaseUserAdministrationService.forTesting(
      functionInvoker: (_, _) async => throw const FunctionException(
        status: 404,
        details: 'Function not found',
        reasonPhrase: 'Not Found',
      ),
    );

    expect(
      () => unavailable.updateUser(
        cloudUserId: 'cloud-user',
        localUserId: 'local-user',
        email: 'user@example.com',
        fullName: 'User',
        roleCode: 'user',
        isActive: true,
        erpUserPayload: {'id': 'local-user', 'roleId': 'role-user'},
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Edge Function'),
        ),
      ),
    );
  });
}
