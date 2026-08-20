class MaintenanceCostReconciliation {
  const MaintenanceCostReconciliation({
    required this.currency,
    required this.workflowStage,
    required this.hasApprovedInvoice,
    required this.requestedCostAvailable,
    required this.requestedMaterialsCost,
    required this.issuedMaterialsActualCost,
    required this.laborCost,
    required this.additionalServicesCost,
    required this.totalOperationalCost,
    required this.materialsInvoiced,
    required this.laborInvoiced,
    required this.servicesInvoiced,
    required this.totalInvoiced,
    required this.paid,
    required this.outstanding,
    required this.issuedNotInvoicedCost,
    required this.invoicedNotIssuedValue,
    required this.materialDiscrepancy,
    required this.laborDiscrepancy,
    required this.lines,
    required this.warehouses,
    this.requestedMaterialsCostByCurrency = const <String, double>{},
    this.issuedMaterialsActualCostByCurrency = const <String, double>{},
    this.crossCurrencyMaterials = false,
    this.issueEvents = const <Map<String, Object?>>[],
    this.issueDraft = const <String, Object?>{},
    this.discount,
    this.tax,
  });

  factory MaintenanceCostReconciliation.fromMap(Map<String, Object?> map) {
    double number(String key) => (map[key] as num?)?.toDouble() ?? 0;
    Map<String, double> totals(String key) {
      final value = map[key];
      if (value is! Map) return const <String, double>{};
      final result = <String, double>{};
      for (final entry in value.entries) {
        final currency = entry.key.toString().trim().toUpperCase();
        final amount = entry.value is num
            ? (entry.value as num).toDouble()
            : double.tryParse(entry.value?.toString() ?? '');
        if (currency.isNotEmpty && amount != null) result[currency] = amount;
      }
      return Map<String, double>.unmodifiable(result);
    }

    List<Map<String, Object?>> rows(String key) =>
        ((map[key] as List?) ?? const <Object?>[])
            .whereType<Map>()
            .map(
              (row) => Map<String, Object?>.unmodifiable(
                Map<String, Object?>.from(row),
              ),
            )
            .toList(growable: false);

    return MaintenanceCostReconciliation(
      currency: map['currency']?.toString().trim().toUpperCase() ?? '',
      workflowStage: map['workflowStage']?.toString() ?? '',
      hasApprovedInvoice: map['hasApprovedInvoice'] == true,
      requestedCostAvailable: map['requestedCostAvailable'] != false,
      requestedMaterialsCost: (map['requestedMaterialsCost'] as num?)
          ?.toDouble(),
      issuedMaterialsActualCost: number('issuedMaterialsActualCost'),
      laborCost: number('laborCost'),
      additionalServicesCost: number('additionalServicesCost'),
      totalOperationalCost: number('totalOperationalCost'),
      materialsInvoiced: number('materialsInvoiced'),
      laborInvoiced: number('laborInvoiced'),
      servicesInvoiced: number('servicesInvoiced'),
      discount: (map['discount'] as num?)?.toDouble(),
      tax: (map['tax'] as num?)?.toDouble(),
      totalInvoiced: number('totalInvoiced'),
      paid: number('paid'),
      outstanding: number('outstanding'),
      issuedNotInvoicedCost: number('issuedNotInvoicedCost'),
      invoicedNotIssuedValue: number('invoicedNotIssuedValue'),
      materialDiscrepancy: map['materialDiscrepancy'] == true,
      laborDiscrepancy: map['laborDiscrepancy'] == true,
      lines: rows('lines'),
      warehouses: rows('warehouses'),
      requestedMaterialsCostByCurrency: totals(
        'requestedMaterialsCostByCurrency',
      ),
      issuedMaterialsActualCostByCurrency: totals(
        'issuedMaterialsActualCostByCurrency',
      ),
      crossCurrencyMaterials: map['crossCurrencyMaterials'] == true,
      issueEvents: rows('issueEvents'),
      issueDraft: map['issueDraft'] is Map
          ? Map<String, Object?>.unmodifiable(
              Map<String, Object?>.from(map['issueDraft'] as Map),
            )
          : const <String, Object?>{},
    );
  }

  final String currency;
  final String workflowStage;
  final bool hasApprovedInvoice;
  final bool requestedCostAvailable;
  final double? requestedMaterialsCost;
  final double issuedMaterialsActualCost;
  final double laborCost;
  final double additionalServicesCost;
  final double totalOperationalCost;
  final double materialsInvoiced;
  final double laborInvoiced;
  final double servicesInvoiced;
  final double? discount;
  final double? tax;
  final double totalInvoiced;
  final double paid;
  final double outstanding;
  final double issuedNotInvoicedCost;
  final double invoicedNotIssuedValue;
  final bool materialDiscrepancy;
  final bool laborDiscrepancy;
  final List<Map<String, Object?>> lines;
  final List<Map<String, Object?>> warehouses;
  final Map<String, double> requestedMaterialsCostByCurrency;
  final Map<String, double> issuedMaterialsActualCostByCurrency;
  final bool crossCurrencyMaterials;
  final List<Map<String, Object?>> issueEvents;
  final Map<String, Object?> issueDraft;
}

MaintenanceCostReconciliation mergeMaintenanceReconciliationPayloads({
  required Map<String, Object?> reconciliation,
  required Map<String, Object?> issueState,
}) {
  final base = Map<String, Object?>.from(reconciliation);
  final issueLines = <String, Map<String, Object?>>{
    for (final row in (issueState['lines'] as List? ?? const []))
      if (row is Map) row['lineId'].toString(): Map<String, Object?>.from(row),
  };
  base['lines'] = (base['lines'] as List? ?? const [])
      .whereType<Map>()
      .map((row) {
        final current = Map<String, Object?>.from(row);
        return <String, Object?>{
          ...current,
          ...?issueLines[current['lineId'].toString()],
        };
      })
      .toList(growable: false);
  final issued =
      (issueState['issuedMaterialsActualCost'] as num?)?.toDouble() ?? 0;
  base['issuedMaterialsActualCost'] = issued;
  if (issueState['issuedMaterialsActualCostByCurrency'] is Map) {
    base['issuedMaterialsActualCostByCurrency'] =
        issueState['issuedMaterialsActualCostByCurrency'];
  }
  base['totalOperationalCost'] =
      issued +
      ((base['laborCost'] as num?)?.toDouble() ?? 0) +
      ((base['additionalServicesCost'] as num?)?.toDouble() ?? 0);
  base['warehouses'] = issueState['warehouses'];
  base['issueEvents'] = issueState['events'];
  base['issueDraft'] = issueState['issueDraft'];

  final draftedByPart = <String, double>{};
  final draftState = issueState['issueDraft'];
  if (draftState is Map) {
    for (final row
        in (draftState['draftLines'] as List? ?? const <Object?>[])) {
      if (row is! Map) continue;
      final partId = row['partId']?.toString() ?? '';
      final quantity = (row['quantity'] as num?)?.toDouble() ?? 0;
      if (partId.isNotEmpty) {
        draftedByPart[partId] = (draftedByPart[partId] ?? 0) + quantity;
      }
    }
  }
  base['lines'] = (base['lines'] as List? ?? const <Object?>[])
      .whereType<Map>()
      .map((row) {
        final current = Map<String, Object?>.from(row);
        current['draftedQuantity'] =
            draftedByPart[current['lineId']?.toString()] ?? 0;
        return current;
      })
      .toList(growable: false);
  return MaintenanceCostReconciliation.fromMap(base);
}
