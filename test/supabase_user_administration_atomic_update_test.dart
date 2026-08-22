import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';
import 'package:quality_line_erp/core/cloud/supabase_user_administration_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await CloudTenantContext.instance.clearCloudSelection();
    await CloudTenantContext.instance.selectTenant(
      authUserId: 'auth-user-1',
      companyId: 'quality-line',
      companyUuid: '11111111-1111-4111-8111-111111111111',
      roleCode: 'admin',
      isSystemAdmin: true,
    );
  });

  tearDown(() async {
    await CloudTenantContext.instance.clearCloudSelection();
  });

  test(
    'profile and avatar update cross one admin-manage-user request',
    () async {
      final calls = <(String, Map<String, dynamic>)>[];
      final service = SupabaseUserAdministrationService.forTesting(
        functionInvoker: (functionName, body) async {
          calls.add((functionName, Map<String, dynamic>.from(body)));
          return <String, dynamic>{'ok': true, 'action': 'update'};
        },
      );

      await service.updateUser(
        cloudUserId: 'cloud-user-1',
        localUserId: 'local-user-1',
        email: 'ALI@Example.COM',
        fullName: 'Ali Updated',
        roleCode: 'user',
        isActive: true,
        erpUserPayload: <String, dynamic>{
          'id': 'local-user-1',
          'roleId': 'role-user',
          'phone': '07700000000',
          'avatarBase64': 'compressed-image-payload',
        },
      );

      expect(calls, hasLength(1));
      expect(calls.single.$1, 'admin-manage-user');
      final body = calls.single.$2;
      expect(body['action'], 'update');
      expect(body['company_id'], '11111111-1111-4111-8111-111111111111');
      expect(body['email'], 'ali@example.com');
      expect(body['full_name'], 'Ali Updated');
      expect(body['avatar_base64'], 'compressed-image-payload');

      final erpUser = Map<String, dynamic>.from(body['erp_user'] as Map);
      expect(erpUser['id'], 'local-user-1');
      expect(erpUser['phone'], '07700000000');
      expect(erpUser.containsKey('avatarBase64'), isFalse);
    },
  );

  test('clearing avatar remains part of the same update request', () async {
    final calls = <Map<String, dynamic>>[];
    final service = SupabaseUserAdministrationService.forTesting(
      functionInvoker: (_, body) async {
        calls.add(Map<String, dynamic>.from(body));
        return <String, dynamic>{'ok': true, 'action': 'update'};
      },
    );

    await service.updateUser(
      cloudUserId: 'cloud-user-1',
      localUserId: 'local-user-1',
      email: 'ali@example.com',
      fullName: 'Ali',
      roleCode: 'user',
      isActive: true,
      erpUserPayload: <String, dynamic>{
        'id': 'local-user-1',
        'roleId': 'role-user',
        'avatarBase64': null,
      },
    );

    expect(calls, hasLength(1));
    expect(calls.single.containsKey('avatar_base64'), isTrue);
    expect(calls.single['avatar_base64'], isNull);
  });
}
