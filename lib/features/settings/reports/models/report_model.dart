class MonthlyReportPoint {
  const MonthlyReportPoint({
    required this.label,
    required this.sales,
    required this.expenses,
    required this.purchases,
  });

  final String label;
  final double sales;
  final double expenses;
  final double purchases;
}

class ReportModel {
  const ReportModel({
    required this.totalCars,
    required this.availableCars,
    required this.reservedCars,
    required this.soldCars,
    required this.totalCustomers,
    required this.totalSuppliers,
    required this.totalInventoryItems,
    required this.totalSales,
    required this.totalPaidSales,
    required this.totalReceivables,
    required this.totalPurchases,
    required this.totalPurchaseDebt,
    required this.totalExpenses,
    required this.inventoryValue,
    required this.cashBalanceUsd,
    required this.cashBalanceIqd,
    required this.activeReservations,
    required this.overdueInstallments,
    required this.netProfit,
    required this.totalSalesByCurrency,
    required this.totalPaidSalesByCurrency,
    required this.totalReceivablesByCurrency,
    required this.totalPurchasesByCurrency,
    required this.totalPurchaseDebtByCurrency,
    required this.totalExpensesByCurrency,
    required this.inventoryValueByCurrency,
    required this.netProfitByCurrency,
    required this.monthlyPoints,
  });

  final int totalCars;
  final int availableCars;
  final int reservedCars;
  final int soldCars;
  final int totalCustomers;
  final int totalSuppliers;
  final int totalInventoryItems;
  final double totalSales;
  final double totalPaidSales;
  final double totalReceivables;
  final double totalPurchases;
  final double totalPurchaseDebt;
  final double totalExpenses;
  final double inventoryValue;
  final double cashBalanceUsd;
  final double cashBalanceIqd;
  final int activeReservations;
  final int overdueInstallments;
  final double netProfit;
  final Map<String, double> totalSalesByCurrency;
  final Map<String, double> totalPaidSalesByCurrency;
  final Map<String, double> totalReceivablesByCurrency;
  final Map<String, double> totalPurchasesByCurrency;
  final Map<String, double> totalPurchaseDebtByCurrency;
  final Map<String, double> totalExpensesByCurrency;
  final Map<String, double> inventoryValueByCurrency;
  final Map<String, double> netProfitByCurrency;
  final List<MonthlyReportPoint> monthlyPoints;

  factory ReportModel.empty() => const ReportModel(
    totalCars: 0,
    availableCars: 0,
    reservedCars: 0,
    soldCars: 0,
    totalCustomers: 0,
    totalSuppliers: 0,
    totalInventoryItems: 0,
    totalSales: 0,
    totalPaidSales: 0,
    totalReceivables: 0,
    totalPurchases: 0,
    totalPurchaseDebt: 0,
    totalExpenses: 0,
    inventoryValue: 0,
    cashBalanceUsd: 0,
    cashBalanceIqd: 0,
    activeReservations: 0,
    overdueInstallments: 0,
    netProfit: 0,
    totalSalesByCurrency: {},
    totalPaidSalesByCurrency: {},
    totalReceivablesByCurrency: {},
    totalPurchasesByCurrency: {},
    totalPurchaseDebtByCurrency: {},
    totalExpensesByCurrency: {},
    inventoryValueByCurrency: {},
    netProfitByCurrency: {},
    monthlyPoints: [],
  );
}
