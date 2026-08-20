import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/widgets/app_pill_tab_bar.dart';
import 'package:quality_line_erp/core/widgets/app_lazy_tab_view.dart';
import 'package:quality_line_erp/features/inventory/cars/pages/cars_page.dart';
import 'inventory_page.dart';
import 'warehouse_management_page.dart';

/// Unified stock catalog without an inner Scaffold/AppBar.
///
/// The application shell owns the module header and navigation. Keeping the
/// catalog itself as plain content prevents duplicated chrome and ensures all
/// product, warehouse and car pages share the full available area.
class StockCatalogPage extends StatelessWidget {
  const StockCatalogPage({super.key, this.initialIndex = 0, this.initialCarId});

  final int initialIndex;
  final String? initialCarId;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    initialIndex: initialIndex.clamp(0, 2).toInt(),
    length: 3,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsetsDirectional.fromSTEB(12, 4, 12, 4),
          child: Material(
            color: Colors.transparent,
            child: AppPillTabBar(
              tabs: [
                AppPillTab('السيارات', Icons.directions_car_filled_rounded),
                AppPillTab('المخازن', Icons.warehouse_rounded),
                AppPillTab('المنتجات', Icons.inventory_2_rounded),
              ],
            ),
          ),
        ),
        Expanded(
          child: AppLazyTabView(
            children: [
              CarsPage(initialCarId: initialCarId),
              const WarehouseManagementPage(),
              const InventoryPage(),
            ],
          ),
        ),
      ],
    ),
  );
}
