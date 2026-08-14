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
    this.issueEvents = const <Map<String, Object?>>[],
    this.discount,
    this.tax,
  });

  factory MaintenanceCostReconciliation.fromMap(Map<String, Object?> map) {
    double number(String key) => (map[key] as num?)?.toDouble() ?? 0;
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
      issueEvents: rows('issueEvents'),
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
  final List<Map<String, Object?>> issueEvents;
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
  base['totalOperationalCost'] =
      issued +
      ((base['laborCost'] as num?)?.toDouble() ?? 0) +
      ((base['additionalServicesCost'] as num?)?.toDouble() ?? 0);
  base['warehouses'] = issueState['warehouses'];
  base['issueEvents'] = issueState['events'];
  return MaintenanceCostReconciliation.fromMap(base);
}
