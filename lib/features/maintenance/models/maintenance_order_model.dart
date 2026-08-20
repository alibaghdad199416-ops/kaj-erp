class MaintenanceOrderModel {
  const MaintenanceOrderModel({
    required this.id,
    required this.orderNumber,
    required this.carId,
    required this.carName,
    required this.warehouseId,
    required this.isSoldCar,
    required this.pricingType,
    required this.status,
    required this.laborCost,
    required this.partsCost,
    required this.totalCost,
    required this.salePrice,
    required this.profit,
    required this.carCostAdded,
    required this.maintenanceDate,
    this.customerId,
    this.customerName,
    this.notes,
    this.currencyCode = 'USD',
    this.exchangeRate = 1,
    this.workflowStage = 'order_draft',
    this.paidAmount = 0,
    this.invoiceNumber,
    this.stockIssueNumber,
    this.cancelReason,
    this.maintenanceExpenseAccountId,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.createdByName,
    this.invoiceCreatedBy,
    this.invoiceCreatedAt,
    this.invoiceApprovedBy,
    this.invoiceApprovedAt,
    this.opportunityId,
    this.opportunityNumber,
    this.materialCostTotalsByCurrency = const <String, double>{},
  });

  final String id;
  final String orderNumber;
  final String carId;
  final String carName;
  final String? customerId;
  final String? customerName;
  final String warehouseId;
  final bool isSoldCar;
  final String pricingType;
  final String status;
  final double laborCost;
  final double partsCost;
  final double totalCost;
  final double salePrice;
  final double profit;
  final double carCostAdded;
  final String maintenanceDate;
  final String? notes;
  final String currencyCode;
  final double exchangeRate;
  final String workflowStage;
  final double paidAmount;
  final String? invoiceNumber;
  final String? stockIssueNumber;
  final String? cancelReason;
  final String? maintenanceExpenseAccountId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? createdByName;
  final String? invoiceCreatedBy;
  final DateTime? invoiceCreatedAt;
  final String? invoiceApprovedBy;
  final DateTime? invoiceApprovedAt;
  final String? opportunityId;
  final String? opportunityNumber;
  final Map<String, double> materialCostTotalsByCurrency;

  Map<String, double> get operationalCostTotalsByCurrency {
    final totals = <String, double>{...materialCostTotalsByCurrency};
    final documentCurrency = currencyCode.trim().toUpperCase();
    if (documentCurrency.isNotEmpty && laborCost != 0) {
      totals.update(
        documentCurrency,
        (value) => value + laborCost,
        ifAbsent: () => laborCost,
      );
    }
    return Map<String, double>.unmodifiable(totals);
  }

  bool get isCancelled => workflowStage == 'cancelled';
  bool get canEdit => workflowStage != 'cancelled';

  String workflowLabel(bool isArabic) {
    const labels = <String, List<String>>{
      'order_draft': ['مسودة أمر صيانة', 'Maintenance Order Draft'],
      'order_approved': ['أمر صيانة معتمد', 'Approved Maintenance Order'],
      'stock_issue_draft': [
        'مسودة إذن صرف صيانة',
        'Maintenance Stock Issue Draft',
      ],
      'stock_issue_approved': [
        'إذن صرف صيانة معتمد',
        'Approved Maintenance Stock Issue',
      ],
      'invoice_draft': ['مسودة فاتورة صيانة', 'Maintenance Invoice Draft'],
      'invoice_approved': [
        'فاتورة صيانة معتمدة',
        'Approved Maintenance Invoice',
      ],
      'paid': ['مدفوع', 'Paid'],
      'completed': ['مكتمل', 'Completed'],
      'cancelled': ['ملغي', 'Cancelled'],
    };
    final pair =
        labels[workflowStage] ??
        labels['order_draft'] ??
        const <String>['مسودة الأمر', 'Order draft'];
    return pair[isArabic ? 0 : 1];
  }

  String pricingLabelFor(bool isArabic) {
    switch (pricingType) {
      case 'paid':
        return isArabic ? 'صيانة مدفوعة' : 'Paid maintenance';
      case 'free':
        return isArabic ? 'صيانة مجانية' : 'Free maintenance';
      default:
        return isArabic ? 'صيانة سيارة مخزون' : 'Inventory-car maintenance';
    }
  }

  String get pricingLabel {
    switch (pricingType) {
      case 'paid':
        return 'صيانة مدفوعة';
      case 'free':
        return 'صيانة مجانية';
      default:
        return 'صيانة سيارة مخزون';
    }
  }

  static Map<String, double> _currencyTotals(Object? value) {
    if (value is! Map) return const <String, double>{};
    final totals = <String, double>{};
    for (final entry in value.entries) {
      final currency = entry.key.toString().trim().toUpperCase();
      final amount = entry.value is num
          ? (entry.value as num).toDouble()
          : double.tryParse(entry.value?.toString() ?? '');
      if (currency.isNotEmpty && amount != null) totals[currency] = amount;
    }
    return Map<String, double>.unmodifiable(totals);
  }

  static bool _asBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().trim().toLowerCase() ?? '';
    return const {'1', 'true', 'yes', 'on'}.contains(text);
  }

  factory MaintenanceOrderModel.fromMap(
    Map<String, dynamic> map,
  ) => MaintenanceOrderModel(
    id: map['id']?.toString() ?? '',
    orderNumber: map['orderNumber']?.toString() ?? '',
    carId: map['carId']?.toString() ?? '',
    carName: map['carName']?.toString() ?? '',
    customerId: map['customerId']?.toString(),
    customerName: map['customerName']?.toString(),
    warehouseId: map['warehouseId']?.toString() ?? '',
    isSoldCar: _asBool(map['isSoldCar']),
    pricingType: map['pricingType']?.toString() ?? 'internal',
    status: (map['status']?.toString().trim().isNotEmpty ?? false)
        ? map['status'].toString()
        : 'draft',
    laborCost: (map['laborCost'] as num?)?.toDouble() ?? 0,
    partsCost: (map['partsCost'] as num?)?.toDouble() ?? 0,
    totalCost: (map['totalCost'] as num?)?.toDouble() ?? 0,
    salePrice: (map['salePrice'] as num?)?.toDouble() ?? 0,
    profit: (map['profit'] as num?)?.toDouble() ?? 0,
    carCostAdded: (map['carCostAdded'] as num?)?.toDouble() ?? 0,
    maintenanceDate: map['maintenanceDate']?.toString() ?? '',
    notes: map['notes']?.toString(),
    currencyCode: map['currencyCode']?.toString().trim().toUpperCase() ?? '',
    exchangeRate: (map['exchangeRate'] as num?)?.toDouble() ?? 1,
    workflowStage:
        map['workflowStage']?.toString() ??
        (map['status']?.toString() == 'completed'
            ? 'completed'
            : 'order_draft'),
    paidAmount: (map['paidAmount'] as num?)?.toDouble() ?? 0,
    invoiceNumber: map['invoiceNumber']?.toString(),
    stockIssueNumber: map['stockIssueNumber']?.toString(),
    cancelReason: map['cancelReason']?.toString(),
    maintenanceExpenseAccountId: map['maintenanceExpenseAccountId']?.toString(),
    createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? ''),
    updatedAt: DateTime.tryParse(map['updatedAt']?.toString() ?? ''),
    createdBy: map['createdBy']?.toString(),
    createdByName: map['createdByName']?.toString(),
    invoiceCreatedBy: map['invoiceCreatedBy']?.toString(),
    invoiceCreatedAt: DateTime.tryParse(
      map['invoiceCreatedAt']?.toString() ?? '',
    ),
    invoiceApprovedBy: map['invoiceApprovedBy']?.toString(),
    invoiceApprovedAt: DateTime.tryParse(
      map['invoiceApprovedAt']?.toString() ?? '',
    ),
    opportunityId: map['opportunityId']?.toString(),
    opportunityNumber: map['opportunityNumber']?.toString(),
    materialCostTotalsByCurrency: _currencyTotals(
      map['materialCostTotalsByCurrency'],
    ),
  );
}

class MaintenancePartRequest {
  const MaintenancePartRequest({
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    this.warehouseId,
  });

  final String productId;
  final int quantity;
  final double unitPrice;
  final String? warehouseId;
}

class MaintenanceLineModel {
  const MaintenanceLineModel({
    required this.id,
    required this.productId,
    required this.productName,
    this.description = '',
    required this.quantity,
    required this.unitCost,
    required this.unitPrice,
    required this.lineType,
    this.warehouseId,
    this.warehouseName,
  });

  final String id;
  final String productId;
  final String productName;
  final String description;
  final String? warehouseId;
  final String? warehouseName;
  final int quantity;
  final double unitCost;
  final double unitPrice;
  final String lineType;

  bool get isService => lineType == 'service';

  factory MaintenanceLineModel.fromMap(Map<String, dynamic> map) =>
      MaintenanceLineModel(
        id: map['id']?.toString() ?? '',
        productId: map['productId']?.toString() ?? '',
        productName: map['productName']?.toString() ?? '',
        description: map['description']?.toString() ?? '',
        warehouseId: map['warehouseId']?.toString(),
        warehouseName: map['warehouseName']?.toString(),
        quantity: (map['quantity'] as num?)?.toInt() ?? 0,
        unitCost: (map['unitCost'] as num?)?.toDouble() ?? 0,
        unitPrice: (map['unitPrice'] as num?)?.toDouble() ?? 0,
        lineType: map['lineType']?.toString() ?? 'stock',
      );
}

class MaintenanceVehicleOption {
  const MaintenanceVehicleOption({
    required this.carId,
    required this.displayName,
    required this.customerId,
    required this.customerName,
    required this.saleSequence,
    this.brand,
    this.model,
    this.year,
    this.chassis,
    this.plateNumber,
    this.carNumber,
    this.color,
  });

  final String carId;
  final String displayName;
  final String customerId;
  final String customerName;
  final int saleSequence;
  final String? brand;
  final String? model;
  final int? year;
  final String? chassis;
  final String? plateNumber;
  final String? carNumber;
  final String? color;

  factory MaintenanceVehicleOption.fromMap(Map<String, dynamic> map) {
    String text(String key) => map[key]?.toString().trim() ?? '';

    final carId = [
      text('carId'),
      text('car_id'),
      text('vehicleId'),
      text('vehicle_id'),
      text('id'),
    ].firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final brand = text('brand');
    final model = text('model');
    final yearText = text('year');
    final chassis = [
      text('chassis'),
      text('vin'),
    ].firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final carNumber = [
      text('carNumber'),
      text('car_number'),
      text('vehicleNumber'),
    ].firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final generatedName = [
      brand,
      model,
      yearText,
    ].where((value) => value.isNotEmpty).join(' ');
    final displayName = [
      text('displayName'),
      text('display_name'),
      text('name'),
      generatedName,
      carNumber,
      chassis,
      carId,
    ].firstWhere((value) => value.isNotEmpty, orElse: () => '—');

    return MaintenanceVehicleOption(
      carId: carId,
      displayName: displayName,
      customerId: [
        text('customerId'),
        text('customer_id'),
        text('clientId'),
        text('client_id'),
        text('buyerId'),
        text('buyer_id'),
      ].firstWhere((value) => value.isNotEmpty, orElse: () => ''),
      customerName: [
        text('customerName'),
        text('customer_name'),
        text('clientName'),
        text('buyerName'),
      ].firstWhere((value) => value.isNotEmpty, orElse: () => '—'),
      saleSequence:
          (map['saleSequence'] as num?)?.toInt() ??
          (map['sale_sequence'] as num?)?.toInt() ??
          int.tryParse(text('saleSequence')) ??
          int.tryParse(text('sale_sequence')) ??
          0,
      brand: brand.isEmpty ? null : brand,
      model: model.isEmpty ? null : model,
      year: (map['year'] as num?)?.toInt() ?? int.tryParse(yearText),
      chassis: chassis.isEmpty ? null : chassis,
      plateNumber: [
        text('plateNumber'),
        text('plate_number'),
        text('plate'),
      ].firstWhere((value) => value.isNotEmpty, orElse: () => '').nullIfEmpty,
      carNumber: carNumber.isEmpty ? null : carNumber,
      color: text('color').nullIfEmpty,
    );
  }
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
