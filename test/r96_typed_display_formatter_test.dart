import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/utils/erp_display_formatter.dart';

void main() {
  group('R96 typed display contract', () {
    test('identifier-like values are never decimal formatted', () {
      expect(ErpDisplayFormatter.formatYear(2026), '2026');
      expect(ErpDisplayFormatter.formatYear('2026.00'), '2026');
      expect(ErpDisplayFormatter.formatReference('INV-101.00'), 'INV-101.00');
      expect(ErpDisplayFormatter.formatReference('CAR-25.00'), 'CAR-25.00');
      expect(ErpDisplayFormatter.formatReference('VIN.001/2026'), 'VIN.001/2026');
      expect(ErpDisplayFormatter.formatReference(' 00964-770-100 '), '00964-770-100');
    });

    test('typed numeric values retain the correct semantic precision', () {
      expect(ErpDisplayFormatter.formatMoney(1500, 'IQD'), '1,500 IQD');
      expect(ErpDisplayFormatter.formatMoney(1500.5, 'USD'), '1,500.5 USD');
      expect(ErpDisplayFormatter.formatQuantity(12.125), '12.125');
      expect(ErpDisplayFormatter.formatRate(1.234567), '1.234567');
      expect(ErpDisplayFormatter.formatPercentage(12.5), '12.5%');
      expect(ErpDisplayFormatter.formatInteger(12000), '12,000');
    });

    test('legacy APIs stay compatible with the typed contract', () {
      expect(ErpDisplayFormatter.money(1500, 'DINAR'), '1,500 IQD');
      expect(ErpDisplayFormatter.accountCode('1000.05'), '100005');
      expect(ErpDisplayFormatter.number(1200.25), '1,200.25');
    });

    test('date and datetime formatting remain semantic', () {
      final date = DateTime(2026, 8, 21, 13, 45);
      expect(ErpDisplayFormatter.formatDate(date), '2026/08/21');
      expect(ErpDisplayFormatter.formatDateTime(date), '2026/08/21 13:45');
    });
  });
}
