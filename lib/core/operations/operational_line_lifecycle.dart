/// Canonical line-level lifecycle contract shared by operational modules.
///
/// Sales, purchases and maintenance historically expose the same business
/// quantities under different RPC field names. This model normalizes those
/// payloads without inventing values in the UI, so consumers can reason about
/// requested -> logistics -> invoiced progress through one typed contract.
class OperationalLineLifecycle {
  const OperationalLineLifecycle({
    required this.lineId,
    required this.itemId,
    required this.description,
    required this.requestedQuantity,
    required this.logisticsQuantity,
    required this.invoicedQuantity,
    required this.remainingLogisticsQuantity,
    required this.remainingInvoiceQuantity,
    required this.requiresLogistics,
    this.hasAuthoritativeReconciliation = false,
    required this.raw,
  });

  factory OperationalLineLifecycle.fromMap(Map<String, Object?> map) {
    final requiresLogistics = _requiresLogistics(map);
    final requested = _nonNegative(
      _number(map, const <String>[
        'requestedQuantity',
        'orderedQuantity',
        'requestedQty',
        'orderedQty',
        'quantity',
      ]),
    );
    const logisticsKeys = <String>[
      'logisticsQuantity',
      'operationalQuantity',
      'executedQuantity',
      'receivedQuantity',
      'deliveredQuantity',
      'issuedQuantity',
      'approvedQuantity',
      'executedQty',
      'receivedQty',
      'deliveredQty',
      'issuedQty',
    ];
    const remainingLogisticsKeys = <String>[
      'remainingLogisticsQuantity',
      'remainingLogistics',
      'remainingOperational',
      'remainingExecutionQuantity',
      'remainingQuantity',
    ];
    final parsedLogistics = _nullableNumber(map, logisticsKeys);
    final explicitRemainingLogistics = _nullableNumber(
      map,
      remainingLogisticsKeys,
    );
    final hasAuthoritativeReconciliation =
        requiresLogistics &&
        (parsedLogistics != null || explicitRemainingLogistics != null);
    final logistics = !requiresLogistics
        ? 0.0
        : _nonNegative(
            parsedLogistics ??
                (explicitRemainingLogistics == null
                    ? 0.0
                    : requested - explicitRemainingLogistics),
          );
    final invoiced = _nonNegative(
      _number(map, const <String>[
        'invoicedQuantity',
        'invoiceQuantity',
        'billedQuantity',
        'invoicedQty',
        'invoiceQty',
      ]),
    );

    final explicitRemainingInvoice = _nullableNumber(map, const <String>[
      'remainingInvoiceQuantity',
      'remainingInvoice',
      'remainingToInvoiceQuantity',
    ]);
    final invoiceable = !requiresLogistics || !hasAuthoritativeReconciliation
        ? requested
        : logistics;
    final remainingInvoice = !requiresLogistics
        ? requested - invoiced
        : explicitRemainingInvoice ?? (invoiceable - invoiced);

    return OperationalLineLifecycle(
      lineId: _text(map, const <String>[
        'lineId',
        'id',
        'orderLineId',
        'itemLineId',
      ]),
      itemId: _text(map, const <String>[
        'itemId',
        'productId',
        'partId',
        'carId',
      ]),
      description: _text(map, const <String>[
        'description',
        'itemName',
        'productName',
        'partName',
        'name',
      ]),
      requestedQuantity: requested,
      logisticsQuantity: logistics,
      invoicedQuantity: invoiced,
      remainingLogisticsQuantity: requiresLogistics
          ? _nonNegative(explicitRemainingLogistics ?? (requested - logistics))
          : 0,
      // Stock lines become invoiceable from approved logistics only when the
      // payload actually contains reconciliation data. Older draft/legacy rows
      // can legitimately omit those fields; in that case requested quantity is
      // the safe display fallback instead of treating an absent value as a
      // confirmed logistics quantity of zero. Service lines never require stock
      // logistics, so stale server-side remaining-invoice values based on zero
      // stock execution are ignored and requested - invoiced remains canonical.
      remainingInvoiceQuantity: _nonNegative(remainingInvoice),
      requiresLogistics: requiresLogistics,
      hasAuthoritativeReconciliation: hasAuthoritativeReconciliation,
      raw: Map<String, Object?>.unmodifiable(map),
    );
  }

  static List<OperationalLineLifecycle> fromRows(
    Iterable<Map<String, Object?>> rows,
  ) => List<OperationalLineLifecycle>.unmodifiable(
    rows.map(OperationalLineLifecycle.fromMap),
  );

  final String lineId;
  final String itemId;
  final String description;
  final double requestedQuantity;
  final double logisticsQuantity;
  final double invoicedQuantity;
  final double remainingLogisticsQuantity;
  final double remainingInvoiceQuantity;
  final bool requiresLogistics;

  /// True only when this stock/logistics line supplied an executed or remaining
  /// logistics value. This distinguishes an authoritative zero execution from
  /// a draft/legacy payload where reconciliation fields are absent entirely.
  final bool hasAuthoritativeReconciliation;
  final Map<String, Object?> raw;

  static const double _epsilon = 0.000001;

  double get invoiceableQuantity =>
      !requiresLogistics || !hasAuthoritativeReconciliation
      ? requestedQuantity
      : logisticsQuantity;

  bool get hasOverLogistics =>
      requiresLogistics && logisticsQuantity > requestedQuantity + _epsilon;

  bool get hasOverInvoice => invoicedQuantity > invoiceableQuantity + _epsilon;

  bool get hasIntegrityViolation => hasOverLogistics || hasOverInvoice;

  bool get logisticsComplete =>
      !requiresLogistics ||
      (requestedQuantity > _epsilon &&
          !hasOverLogistics &&
          logisticsQuantity + _epsilon >= requestedQuantity);

  bool get invoiceComplete =>
      invoiceableQuantity > _epsilon &&
      !hasOverInvoice &&
      invoicedQuantity + _epsilon >= invoiceableQuantity;

  OperationalLineProgress get progress {
    if (hasIntegrityViolation) return OperationalLineProgress.invalid;
    if (invoiceComplete && logisticsComplete) {
      return OperationalLineProgress.complete;
    }
    if (invoicedQuantity > _epsilon) {
      return OperationalLineProgress.partiallyInvoiced;
    }
    if (logisticsComplete) return OperationalLineProgress.readyToInvoice;
    if (logisticsQuantity > _epsilon) {
      return OperationalLineProgress.partialLogistics;
    }
    return OperationalLineProgress.pending;
  }

  static bool _requiresLogistics(Map<String, Object?> map) {
    final explicit = map['requiresLogistics'] ?? map['requires_logistics'];
    if (explicit is bool) return explicit;
    if (explicit is num) return explicit != 0;
    final explicitText = explicit?.toString().trim().toLowerCase();
    if (explicitText == 'false' ||
        explicitText == '0' ||
        explicitText == 'no') {
      return false;
    }
    if (explicitText == 'true' ||
        explicitText == '1' ||
        explicitText == 'yes') {
      return true;
    }
    final isService = map['isService'] ?? map['is_service'];
    if (isService == true || isService == 1 || isService?.toString() == '1') {
      return false;
    }
    final lineType = (map['lineType'] ?? map['line_type'])
        ?.toString()
        .trim()
        .toLowerCase();
    return lineType != 'service';
  }

  static String _text(Map<String, Object?> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return '';
  }

  static double _number(Map<String, Object?> map, List<String> keys) =>
      _nullableNumber(map, keys) ?? 0;

  static double? _nullableNumber(Map<String, Object?> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is num) return value.toDouble();
      final parsed = double.tryParse(value?.toString().trim() ?? '');
      if (parsed != null) return parsed;
    }
    return null;
  }

  static double _nonNegative(double value) => value < 0 ? 0 : value;
}

enum OperationalLineProgress {
  pending,
  partialLogistics,
  readyToInvoice,
  partiallyInvoiced,
  complete,
  invalid,
}
