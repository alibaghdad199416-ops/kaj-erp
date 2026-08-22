import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/features/sales/widgets/sales_search.dart';
import 'package:quality_line_erp/features/sales/widgets/sales_statistics.dart';

void main() {
  test(
    'legacy Sales widgets remain explicit non-runtime regression fixtures',
    () {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      final search = SalesSearch(controller: controller, onChanged: (_) {});
      const statistics = SalesStatistics(
        totalSales: 3,
        revenueByCurrency: <String, double>{'USD': 1200, 'IQD': 1500000},
        paidByCurrency: <String, double>{'USD': 700, 'IQD': 500000},
        remainingByCurrency: <String, double>{'USD': 500, 'IQD': 1000000},
      );

      expect(search.controller, same(controller));
      expect(statistics.revenueByCurrency['USD'], 1200);
      expect(statistics.revenueByCurrency['IQD'], 1500000);
    },
  );
}
