class DashboardModel {
  const DashboardModel({
    required this.totalCars,
    required this.availableCars,
    required this.reservedCars,
    required this.soldCars,
    required this.totalCustomers,
    required this.totalSuppliers,
    required this.totalSales,
    required this.todaySales,
    required this.totalPurchases,
    required this.totalExpenses,
    required this.netProfit,
    required this.cashBalanceUsd,
    required this.cashBalanceIqd,
    required this.inventoryValue,
    required this.totalReceivables,
    required this.totalPayables,
    required this.totalSalesByCurrency,
    required this.todaySalesByCurrency,
    required this.totalPurchasesByCurrency,
    required this.totalExpensesByCurrency,
    required this.netProfitByCurrency,
    required this.inventoryValueByCurrency,
    required this.totalReceivablesByCurrency,
    required this.totalPayablesByCurrency,
    required this.salesCollectionsByCurrency,
    required this.purchasePaymentsByCurrency,
    required this.maintenanceRevenueByCurrency,
    required this.maintenancePaidByCurrency,
    required this.maintenanceOutstandingByCurrency,
    required this.maintenanceActualCostByCurrency,
    required this.customerAdvancesByCurrency,
    required this.supplierAdvancesByCurrency,
    required this.recognizedRevenueByCurrency,
    required this.cashBalanceByCurrency,
    required this.pendingPurchaseCars,
    required this.lowStockItems,
    required this.carsWithoutWarehouse,
    required this.activeReservations,
    required this.overdueInstallments,
    required this.dueSoonInstallments,
    required this.outstandingInstallmentsByCurrency,
    required this.pendingSyncOperations,
    required this.salesTrend,
    required this.recentActivities,
    required this.recentDocuments,
    required this.upcomingInstallments,
    required this.generatedAt,
    required this.filter,
    required this.statusCounts,
  });

  final int totalCars;
  final int availableCars;
  final int reservedCars;
  final int soldCars;
  final int totalCustomers;
  final int totalSuppliers;
  final double totalSales;
  final double todaySales;
  final double totalPurchases;
  final double totalExpenses;
  final double netProfit;
  final double cashBalanceUsd;
  final double cashBalanceIqd;
  final double inventoryValue;
  final double totalReceivables;
  final double totalPayables;
  final Map<String, double> totalSalesByCurrency;
  final Map<String, double> todaySalesByCurrency;
  final Map<String, double> totalPurchasesByCurrency;
  final Map<String, double> totalExpensesByCurrency;
  final Map<String, double> netProfitByCurrency;
  final Map<String, double> inventoryValueByCurrency;
  final Map<String, double> totalReceivablesByCurrency;
  final Map<String, double> totalPayablesByCurrency;
  final Map<String, double> salesCollectionsByCurrency;
  final Map<String, double> purchasePaymentsByCurrency;
  final Map<String, double> maintenanceRevenueByCurrency;
  final Map<String, double> maintenancePaidByCurrency;
  final Map<String, double> maintenanceOutstandingByCurrency;
  final Map<String, double> maintenanceActualCostByCurrency;
  final Map<String, double> customerAdvancesByCurrency;
  final Map<String, double> supplierAdvancesByCurrency;
  final Map<String, double> recognizedRevenueByCurrency;
  final Map<String, double> cashBalanceByCurrency;
  final int pendingPurchaseCars;
  final int lowStockItems;
  final int carsWithoutWarehouse;
  final int activeReservations;
  final int overdueInstallments;
  final int dueSoonInstallments;
  final Map<String, double> outstandingInstallmentsByCurrency;
  final int pendingSyncOperations;
  final List<DashboardSalesPoint> salesTrend;
  final List<DashboardActivity> recentActivities;
  final List<DashboardDocument> recentDocuments;
  final List<DashboardInstallment> upcomingInstallments;
  final DateTime generatedAt;
  final DashboardFilter filter;
  final Map<String, Map<String, int>> statusCounts;

  factory DashboardModel.empty({DateTime? generatedAt}) => DashboardModel(
    totalCars: 0,
    availableCars: 0,
    reservedCars: 0,
    soldCars: 0,
    totalCustomers: 0,
    totalSuppliers: 0,
    totalSales: 0,
    todaySales: 0,
    totalPurchases: 0,
    totalExpenses: 0,
    netProfit: 0,
    cashBalanceUsd: 0,
    cashBalanceIqd: 0,
    inventoryValue: 0,
    totalReceivables: 0,
    totalPayables: 0,
    totalSalesByCurrency: const {},
    todaySalesByCurrency: const {},
    totalPurchasesByCurrency: const {},
    totalExpensesByCurrency: const {},
    netProfitByCurrency: const {},
    inventoryValueByCurrency: const {},
    totalReceivablesByCurrency: const {},
    totalPayablesByCurrency: const {},
    salesCollectionsByCurrency: const {},
    purchasePaymentsByCurrency: const {},
    maintenanceRevenueByCurrency: const {},
    maintenancePaidByCurrency: const {},
    maintenanceOutstandingByCurrency: const {},
    maintenanceActualCostByCurrency: const {},
    customerAdvancesByCurrency: const {},
    supplierAdvancesByCurrency: const {},
    recognizedRevenueByCurrency: const {},
    cashBalanceByCurrency: const {},
    pendingPurchaseCars: 0,
    lowStockItems: 0,
    carsWithoutWarehouse: 0,
    activeReservations: 0,
    overdueInstallments: 0,
    dueSoonInstallments: 0,
    outstandingInstallmentsByCurrency: const {},
    pendingSyncOperations: 0,
    salesTrend: const [],
    recentActivities: const [],
    recentDocuments: const [],
    upcomingInstallments: const [],
    generatedAt: generatedAt ?? DateTime.now(),
    filter: DashboardFilter(toDate: generatedAt ?? DateTime.now()),
    statusCounts: const {},
  );
}

class DashboardSalesPoint {
  const DashboardSalesPoint({required this.date, required this.amounts});
  final DateTime date;
  final Map<String, double> amounts;

  double get amount => amounts.values.fold(0, (sum, value) => sum + value);
}

class DashboardFilter {
  const DashboardFilter({this.fromDate, required this.toDate});
  final DateTime? fromDate;
  final DateTime toDate;
}

class DashboardDocument {
  const DashboardDocument({
    required this.module,
    required this.documentType,
    required this.reference,
    required this.status,
    required this.partner,
    required this.currencyCode,
    required this.amount,
    required this.occurredAt,
  });
  final String module;
  final String documentType;
  final String reference;
  final String status;
  final String partner;
  final String currencyCode;
  final double amount;
  final DateTime occurredAt;
}

class DashboardActivity {
  const DashboardActivity({
    required this.action,
    required this.module,
    required this.description,
    required this.userName,
    required this.createdAt,
  });

  final String action;
  final String module;
  final String description;
  final String userName;
  final DateTime createdAt;
}

class DashboardInstallment {
  const DashboardInstallment({
    required this.customerName,
    required this.installmentNo,
    required this.dueDate,
    required this.remainingAmount,
    required this.currencyCode,
    required this.isOverdue,
  });

  final String customerName;
  final int installmentNo;
  final DateTime dueDate;
  final double remainingAmount;
  final String currencyCode;
  final bool isOverdue;
}
