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
