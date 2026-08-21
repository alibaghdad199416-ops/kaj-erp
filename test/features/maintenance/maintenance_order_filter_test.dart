import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';
import 'package:quality_line_erp/features/maintenance/models/maintenance_order_filter.dart';
import 'package:quality_line_erp/features/maintenance/models/maintenance_order_model.dart';

MaintenanceOrderModel order({
  required String id,
  required String number,
  required String carId,
  required String carName,
  required String customerId,
  required String customerName,
  required String warehouseId,
  required String stage,
  required String currency,
  required double salePrice,
  required double totalCost,
  required String createdBy,
  required String createdByName,
  required String date,
}) => MaintenanceOrderModel(
  id: id,
  orderNumber: number,
  carId: carId,
  carName: carName,
  customerId: customerId,
  customerName: customerName,
  warehouseId: warehouseId,
  isSoldCar: true,
  pricingType: 'paid',
  status: 'active',
  laborCost: 10,
  partsCost: totalCost - 10,
  totalCost: totalCost,
  salePrice: salePrice,
  profit: salePrice - totalCost,
  carCostAdded: 0,
  maintenanceDate: date,
  currencyCode: currency,
  workflowStage: stage,
  createdBy: createdBy,
  createdByName: createdByName,
);

void main() {
  final orders = <MaintenanceOrderModel>[
    order(
      id: 'm1',
      number: 'MO-100',
      carId: 'car-1',
      carName: 'Toyota Land Cruiser',
      customerId: 'customer-1',
      customerName: 'أحمد علي',
      warehouseId: 'wh-1',
      stage: 'order_approved',
      currency: 'USD',
      salePrice: 250,
      totalCost: 150,
      createdBy: 'user-1',
      createdByName: 'Technician One',
      date: '2026-08-20T08:00:00Z',
    ),
    order(
      id: 'm2',
      number: 'MO-200',
      carId: 'car-2',
      carName: 'Kia Sportage',
      customerId: 'customer-2',
      customerName: 'Customer Two',
      warehouseId: 'wh-2',
      stage: 'invoice_approved',
      currency: 'IQD',
      salePrice: 900000,
      totalCost: 650000,
      createdBy: 'user-2',
      createdByName: 'Technician Two',
      date: '2026-08-21T09:00:00Z',
    ),
  ];

  test('maintenance query combines Arabic search, stage and currency', () {
    final result = MaintenanceOrderFilter.apply(
      orders,
      const UnifiedFilterCriteria(
        searchText: 'احمد',
        statuses: <String>{'order_approved'},
        currencies: <String>{'USD'},
      ),
    );

    expect(result.map((value) => value.id), <String>['m1']);
  });

  test('maintenance query supports vehicle warehouse creator and amount', () {
    final result = MaintenanceOrderFilter.apply(
      orders,
      const UnifiedFilterCriteria(
        warehouseIds: <String>{'wh-2'},
        userIds: <String>{'user-2'},
        dimensions: <String, Set<String>>{
          'vehicle': <String>{'car-2'},
        },
        numericRanges: <String, UnifiedNumericRange>{
          'salePrice': UnifiedNumericRange(min: 800000, max: 1000000),
        },
      ),
    );

    expect(result.map((value) => value.id), <String>['m2']);
  });

  test('maintenance query sorts the filtered operational dataset', () {
    final result = MaintenanceOrderFilter.apply(
      orders,
      const UnifiedFilterCriteria(
        sort: UnifiedSortSpec(
          'date',
          direction: UnifiedSortDirection.descending,
        ),
      ),
    );

    expect(result.map((value) => value.id), <String>['m2', 'm1']);
  });

  test('maintenance workspace delegates query state to the unified contract', () {
    final source = File(
      'lib/features/maintenance/pages/maintenance_page.dart',
    ).readAsStringSync();

    expect(source, contains('UnifiedFilterCriteria _criteria ='));
    expect(source, contains('MaintenanceOrderFilter.apply('));
    expect(source, isNot(contains('List<MaintenanceOrderModel> _visible')));
    expect(source, contains('onChanged: _setSearchCriteria'));
    expect(source, contains('onSelected: (_) => _setStageCriteria(stage)'));
    expect(source, contains('onSelectChanged: (_) => _openDetails(order)'));
    expect(
      source,
      contains('ErpDisplayFormatter.formatReference(\n                              order.orderNumber,'),
    );
    expect(source, contains('ErpDisplayFormatter.formatDateTime('));
    expect(source, contains('ErpDisplayFormatter.formatMoney('));
    expect(source, isNot(contains("package:intl/intl.dart")));
    expect(source, isNot(contains('core/utils/money_formatter.dart')));
  });
}
