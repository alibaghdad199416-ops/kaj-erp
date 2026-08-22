import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/features/customer_service/models/opportunity_model.dart';

Map<String, dynamic> opportunityRow(double value, String currency) => {
  'id': 'r49-opportunity',
  'opportunityNumber': 'OPP0001',
  'customerId': 'customer-1',
  'customerName': 'عميل R49',
  'customerPhone': '07700000000',
  'title': 'R49 Expected Value',
  'source': 'runtime',
  'expectedValue': value,
  'currency': currency,
  'stage': 'proposal',
  'probability': 50,
  'status': 'pending',
  'assignedUserId': 'user-1',
  'assignedUserName': 'R49 User',
  'createdByUserId': 'user-1',
  'createdByUserName': 'R49 User',
  'createdAt': '2026-08-10T10:00:00.000Z',
  'updatedAt': '2026-08-10T10:01:00.000Z',
};

void main() {
  test('snake_case edit projection preserves stage and currency aliases', () {
    final decoded = OpportunityModel.fromMap(<String, dynamic>{
      'id': 'opportunity-snake',
      'opportunity_number': 'OPP-55',
      'customer_id': 'customer-55',
      'customer_name': 'R55 Customer',
      'customer_phone': '07700000055',
      'title': 'Fleet renewal',
      'source': 'Referral',
      'expected_value': '12500.50',
      'currency_code': 'IQD',
      'stage': 'qualified',
      'probability': '65',
      'status': 'pending',
      'assigned_user_id': 'user-55',
      'assigned_user_name': 'R55 Owner',
      'created_by_user_id': 'admin-55',
      'created_by_user_name': 'R55 Admin',
      'created_at': '2026-08-11T00:00:00Z',
      'follow_up_date': '2026-08-20T00:00:00Z',
      'updated_at': '2026-08-11T01:00:00Z',
    });

    expect(decoded.stage, 'qualified');
    expect(decoded.currency, 'IQD');
    expect(decoded.expectedValue, 12500.50);
    expect(decoded.customerId, 'customer-55');
    expect(decoded.assignedUserId, 'user-55');
    expect(decoded.followUpDate, DateTime.parse('2026-08-20T00:00:00Z'));
  });

  test(
    'Opportunity expected value and currency survive production model maps',
    () {
      for (final sample in <(double, String)>[
        (0, 'IQD'),
        (1234.56, 'USD'),
        (999999999.99, 'USD'),
      ]) {
        final decoded = OpportunityModel.fromMap(
          opportunityRow(sample.$1, sample.$2),
        );
        final payload = decoded.toMap();
        final rehydrated = OpportunityModel.fromMap(payload);

        expect(payload['expectedValue'], sample.$1);
        expect(payload['currency'], sample.$2);
        expect(rehydrated.expectedValue, sample.$1);
        expect(rehydrated.currency, sample.$2);
        expect(rehydrated.stage, 'proposal');
      }
    },
  );

  test('database numeric strings deserialize without alias or type loss', () {
    final decoded = OpportunityModel.fromMap({
      ...opportunityRow(0, 'USD'),
      'expectedValue': '1234.56',
      'currency': 'iqd',
    });

    expect(decoded.expectedValue, 1234.56);
    expect(decoded.currency, 'IQD');
  });
}
