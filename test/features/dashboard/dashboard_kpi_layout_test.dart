import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/features/dashboard/pages/dashboard_page.dart';

void main() {
  test('KPI columns follow actual available content width', () {
    expect(dashboardKpiColumnCount(1648), 5);
    expect(dashboardKpiColumnCount(1320), 5);
    expect(dashboardKpiColumnCount(1290), 5);
    expect(dashboardKpiColumnCount(1200), 5);
    expect(dashboardKpiColumnCount(1148), 5);
    expect(dashboardKpiColumnCount(1147), 4);
    expect(dashboardKpiColumnCount(1000), 4);
    expect(dashboardKpiColumnCount(760), 3);
    expect(dashboardKpiColumnCount(500), 2);
    expect(dashboardKpiColumnCount(219), 1);
  });

  test('KPI rows stay balanced without orphan cards', () {
    expect(dashboardKpiRowSizes(9, 5), <int>[5, 4]);
    expect(dashboardKpiRowSizes(8, 5), <int>[4, 4]);
    expect(dashboardKpiRowSizes(7, 5), <int>[4, 3]);
    expect(dashboardKpiRowSizes(6, 5), <int>[3, 3]);
    expect(dashboardKpiRowSizes(5, 5), <int>[5]);
    expect(dashboardKpiRowSizes(3, 2), <int>[2, 1]);
    expect(dashboardKpiRowSizes(0, 5), isEmpty);
  });
}
