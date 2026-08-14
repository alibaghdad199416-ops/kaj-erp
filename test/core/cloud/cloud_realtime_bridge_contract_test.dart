import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/cloud/cloud_realtime_bridge.dart';

void main() {
  final bindings = {
    for (final binding in CloudRealtimeBridge.bindingContracts)
      binding.table: binding,
  };

  test('Realtime tenant filters preserve special scope semantics', () {
    expect(bindings['erp_accounts']?.tenantColumn, 'organization_id');
    expect(bindings['erp_accounts']?.usesCompanySlug, isFalse);
    expect(bindings['erp_records']?.tenantColumn, 'company_id');
    expect(bindings['erp_records']?.usesCompanySlug, isTrue);
  });

  test('notification binding still refreshes unread state', () {
    final binding = bindings['erp_enterprise_notifications'];
    expect(binding?.sources, contains('notifications'));
    expect(binding?.refreshesUnreadNotifications, isTrue);
  });

  test('retained R57 bindings preserve their invalidation sources', () {
    expect(bindings, isNot(contains('branches')));
    expect(
      bindings['company_memberships']?.sources,
      containsAll(<String>['users', 'access', 'settings']),
    );
    expect(
      bindings['erp_maintenance_orders']?.sources,
      containsAll(<String>[
        'maintenance',
        'inventory',
        'accounting',
        'cashbox',
      ]),
    );
    expect(bindings['erp_fixed_assets']?.sources, contains('accounting'));
    expect(
      bindings['erp_permission_roles']?.sources,
      containsAll(<String>['users', 'access', 'settings']),
    );
  });
}
