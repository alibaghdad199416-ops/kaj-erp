import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/app/route_names.dart';
import 'package:quality_line_erp/app/routes.dart';
import 'package:quality_line_erp/features/inventory/pages/stock_catalog_page.dart';

void main() {
  test('products and inventory keep distinct route identities', () {
    expect(AppRouteNames.products, isNot(AppRouteNames.inventory));
    expect(AppRoutes.routes, contains(AppRouteNames.products));
    expect(AppRoutes.routes, contains(AppRouteNames.inventory));
  });

  testWidgets('products route opens the products tab', (tester) async {
    final productRoute = AppRoutes.routes[AppRouteNames.products]!;
    final widget = productRoute(const RouteSettings(name: AppRouteNames.products));

    expect(widget, isA<Widget>());
    await tester.pumpWidget(MaterialApp(home: widget));
    await tester.pump();

    final controller = tester.widget<DefaultTabController>(
      find.byType(DefaultTabController),
    );
    expect(controller.initialIndex, 2);
  });

  test('all canonical business module routes are registered exactly once', () {
    final expectedModules = <String>{
      AppRouteNames.dashboard,
      AppRouteNames.globalSearch,
      AppRouteNames.notifications,
      AppRouteNames.inventory,
      AppRouteNames.maintenance,
      AppRouteNames.businessPartners,
      AppRouteNames.customerService,
      AppRouteNames.sales,
      AppRouteNames.purchases,
      AppRouteNames.accounting,
      AppRouteNames.settings,
    };

    expect(AppRoutes.businessModuleRoutes, equals(expectedModules));
    expect(AppRoutes.routes.keys, containsAll(expectedModules));
    expect(AppRoutes.routes.keys, contains(AppRouteNames.products));
  });
}
