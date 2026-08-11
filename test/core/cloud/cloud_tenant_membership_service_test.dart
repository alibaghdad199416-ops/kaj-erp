import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/cloud/cloud_tenant_membership_service.dart';

void main() {
  const companyA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const companyB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  const companyC = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  final memberships = <Map<String, dynamic>>[
    {'company_id': companyA},
    {'company_id': companyB},
  ];

  test('retains persisted Company B even when Company A is returned first', () {
    final selected = selectCloudMembershipRow(
      memberships: memberships,
      persistedCompanyId: companyB,
    );

    expect(selected['company_id'], companyB);
  });

  test(
    'does not select an arbitrary company when no selection is persisted',
    () {
      expect(
        () => selectCloudMembershipRow(memberships: memberships),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('rejects persisted Company C when caller only belongs to A and B', () {
    expect(
      () => selectCloudMembershipRow(
        memberships: memberships,
        persistedCompanyId: companyC,
      ),
      throwsA(isA<StateError>()),
    );
  });
}
