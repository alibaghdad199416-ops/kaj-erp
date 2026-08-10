class ErpTestFixtures {
  ErpTestFixtures._();

  static const companyA = '00000000-0000-4000-8000-000000000001';
  static const companyB = '00000000-0000-4000-8000-000000000002';
  static const ownerUser = '10000000-0000-4000-8000-000000000001';
  static const restrictedUser = '10000000-0000-4000-8000-000000000002';

  static Map<String, Object?> customer({
    String companyId = companyA,
    String id = '20000000-0000-4000-8000-000000000001',
  }) => <String, Object?>{
    'id': id,
    'company_id': companyId,
    'name': 'عميل اختباري',
    'phone': '07700000000',
    'is_active': true,
  };
}
