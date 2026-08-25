import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/security/security.dart';

void main() {
  const employee = AccessSubject(
    userId: 'u-1',
    roleIds: {'sales'},
    permissionCodes: {'customers.view', 'customers.update'},
    tenantId: 'tenant-a',
    companyId: 'company-a',
  );

  const foreignCustomer = AccessResource(
    type: 'customer',
    id: 'c-2',
    tenantId: 'tenant-b',
    companyId: 'company-b',
  );

  const ownCompanyCustomer = AccessResource(
    type: 'customer',
    id: 'c-1',
    tenantId: 'tenant-a',
    companyId: 'company-a',
  );

  test('default deny blocks unmatched operations', () {
    final engine = AccessPolicyEngine();
    final decision = engine.evaluate(
      const AccessRequest(
        subject: employee,
        resource: ownCompanyCustomer,
        operation: AccessOperation.read,
      ),
    );
    expect(decision.allowed, isFalse);
    expect(decision.reason, 'default_deny');
  });

  test('tenant and company record rules isolate business data', () {
    final engine = AccessPolicyEngine(
      policies: const [
        AccessPolicy(
          id: 'customer-read-own-company',
          resourceType: 'customer',
          operations: {AccessOperation.read},
          effect: PolicyEffect.allow,
          requiredPermissions: {'customers.view'},
          condition: RecordRules.sameCompany,
        ),
      ],
    );

    expect(
      engine
          .evaluate(
            const AccessRequest(
              subject: employee,
              resource: ownCompanyCustomer,
              operation: AccessOperation.read,
            ),
          )
          .allowed,
      isTrue,
    );
    expect(
      engine
          .evaluate(
            const AccessRequest(
              subject: employee,
              resource: foreignCustomer,
              operation: AccessOperation.read,
            ),
          )
          .allowed,
      isFalse,
    );
  });

  test('explicit deny overrides allow and field security filters values', () {
    final engine = AccessPolicyEngine(
      policies: const [
        AccessPolicy(
          id: 'customer-update',
          resourceType: 'customer',
          operations: {AccessOperation.update},
          effect: PolicyEffect.allow,
          requiredPermissions: {'customers.update'},
          hiddenFields: {'creditCardToken'},
          readOnlyFields: {'creditLimit'},
        ),
        AccessPolicy(
          id: 'protect-foreign-tenant',
          resourceType: 'customer',
          operations: {AccessOperation.update},
          effect: PolicyEffect.deny,
          condition: _foreignTenant,
          priority: 100,
        ),
      ],
    );

    final denied = engine.evaluate(
      const AccessRequest(
        subject: employee,
        resource: foreignCustomer,
        operation: AccessOperation.update,
      ),
    );
    expect(denied.allowed, isFalse);
    expect(denied.reason, 'explicit_deny');

    final request = const AccessRequest(
      subject: employee,
      resource: ownCompanyCustomer,
      operation: AccessOperation.update,
    );
    final writable = engine.filterWritableFields(request, const {
      'name': 'Customer',
      'creditLimit': 5000,
      'creditCardToken': 'secret',
    });
    expect(writable, {'name': 'Customer'});
  });

  test('system administrator bypass remains explicit', () {
    const admin = AccessSubject(
      userId: 'admin',
      roleIds: {'role-admin'},
      permissionCodes: {},
      isSystemAdmin: true,
    );
    final engine = AccessPolicyEngine();
    final decision = engine.evaluate(
      const AccessRequest(
        subject: admin,
        resource: foreignCustomer,
        operation: AccessOperation.delete,
      ),
    );
    expect(decision.allowed, isTrue);
    expect(decision.reason, 'system_admin');
  });
}

bool _foreignTenant(AccessRequest request) {
  return request.resource.tenantId != null &&
      request.resource.tenantId != request.subject.tenantId;
}
