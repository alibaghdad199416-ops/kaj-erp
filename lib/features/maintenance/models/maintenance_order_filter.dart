import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';
import 'package:quality_line_erp/features/maintenance/models/maintenance_order_model.dart';

/// Maintenance order adapter for the enterprise unified query contract.
///
/// Search, stage, vehicle, customer, creator, currency, opportunity, warehouse,
/// pricing mode, date and amount filters are resolved through the same engine
/// used by other operational modules instead of widget-owned predicates.
abstract final class MaintenanceOrderFilter {
  static final UnifiedFilterAdapter<MaintenanceOrderModel> adapter =
      UnifiedFilterAdapter<MaintenanceOrderModel>(
        searchableText: (order) => <Object?>[
          order.orderNumber,
          order.carName,
          order.customerName,
          order.invoiceNumber,
          order.stockIssueNumber,
          order.opportunityNumber,
          order.createdByName,
          order.notes,
          order.currencyCode,
          order.workflowStage,
        ],
        status: (order) => order.workflowStage,
        partnerId: (order) => order.customerId,
        currency: (order) => order.currencyCode,
        userId: (order) => order.createdBy,
        warehouseId: (order) => order.warehouseId,
        date: (order) =>
            DateTime.tryParse(order.maintenanceDate) ?? order.createdAt,
        dimensions: <String, UnifiedValueReader<MaintenanceOrderModel>>{
          'vehicle': (order) => order.carId,
          'customer': (order) => order.customerId,
          'createdBy': (order) => order.createdBy,
          'opportunity': (order) => order.opportunityId,
          'pricingType': (order) => order.pricingType,
          'invoice': (order) => order.invoiceNumber,
          'stockIssue': (order) => order.stockIssueNumber,
        },
        numericDimensions:
            <String, UnifiedNumericValueReader<MaintenanceOrderModel>>{
              'salePrice': (order) => order.salePrice,
              'paidAmount': (order) => order.paidAmount,
              'laborCost': (order) => order.laborCost,
              'partsCost': (order) => order.partsCost,
              'totalCost': (order) => order.totalCost,
              'profit': (order) => order.profit,
            },
        sortValues: <String, UnifiedValueReader<MaintenanceOrderModel>>{
          'date': (order) =>
              DateTime.tryParse(order.maintenanceDate) ?? order.createdAt,
          'orderNumber': (order) => order.orderNumber,
          'vehicle': (order) => order.carName,
          'customer': (order) => order.customerName,
          'createdBy': (order) => order.createdByName,
          'currency': (order) => order.currencyCode,
          'stage': (order) => order.workflowStage,
          'salePrice': (order) => order.salePrice,
          'totalCost': (order) => order.totalCost,
        },
      );

  static List<MaintenanceOrderModel> apply(
    Iterable<MaintenanceOrderModel> orders,
    UnifiedFilterCriteria criteria,
  ) => UnifiedFilterEngine.apply<MaintenanceOrderModel>(
    orders,
    criteria: criteria,
    adapter: adapter,
  );
}
