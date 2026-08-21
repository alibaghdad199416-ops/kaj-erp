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
    required this.raw,
  });

  factory OperationalLineLifecycle.fromMap(Map<String, Object?> map) {
    final requested = _nonNegative(
      _number(
        map,
        const <String>[
          'requestedQuantity',
          'orderedQuantity',
          'requestedQty',
          'orderedQty',
          'quantity',
        ],
      ),
    );
    final logistics = _nonNegative(
      _number(
        map,
        const <String>[
          'logisticsQuantity',
          'executedQuantity',
          'receivedQuantity',
          'deliveredQuantity',
          'issuedQuantity',
          'approvedQuantity',
          'executedQty',
          'receivedQty',
          'deliveredQty',
          'issuedQty',
        ],
      ),
    );
    final invoiced = _nonNegative(
      _number(
        map,
        const <String>[
          'invoicedQuantity',
          'invoiceQuantity',
          'billedQuantity',
          'invoicedQty',
          'invoiceQty',
        ],
      ),
    );

    final explicitRemainingLogistics = _nullableNumber(
      map,
      const <String>[
        'remainingLogisticsQuantity',
        'remainingLogistics',
        'remainingExecutionQuantity',
      ],
    );
    final explicitRemainingInvoice = _nullableNumber(
      map,
      const <String>[
        'remainingInvoiceQuantity',
        'remainingInvoice',
        'remainingToInvoiceQuantity',
      ],
    );

    return OperationalLineLifecycle(
      lineId: _text(
        map,
        const <String>['lineId', 'id', 'orderLineId', 'itemLineId'],
      ),
      itemId: _text(
        map,
        const <String>['itemId', 'productId', 'partId', 'carId'],
      ),
      description: _text(
        map,
        const <String>[
          'description',
          'itemName',
          'productName',
          'partName',
          'name',
        ],
      ),
      requestedQuantity: requested,
      logisticsQuantity: logistics,
      invoicedQuantity: invoiced,
      remainingLogisticsQuantity: _nonNegative(
        explicitRemainingLogistics ?? (requested - logistics),
      ),
      // Invoice eligibility follows executed logistics, not unexecuted order
      // quantity. This keeps draft stock quantities from being presented as
      // invoiceable value.
      remainingInvoiceQuantity: _nonNegative(
        explicitRemainingInvoice ?? (logistics - invoiced),
      ),
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
  final Map<String, Object?> raw;

  static const double _epsilon = 0.000001;

  bool get hasOverLogistics =>
      logisticsQuantity > requestedQuantity + _epsilon;

  bool get hasOverInvoice => invoicedQuantity > logisticsQuantity + _epsilon;

  bool get hasIntegrityViolation => hasOverLogistics || hasOverInvoice;

  bool get logisticsComplete =>
      requestedQuantity > _epsilon &&
      !hasOverLogistics &&
      logisticsQuantity + _epsilon >= requestedQuantity;

  bool get invoiceComplete =>
      logisticsQuantity > _epsilon &&
      !hasOverInvoice &&
      invoicedQuantity + _epsilon >= logisticsQuantity;

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

  static String _text(Map<String, Object?> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return '';
  }

  static double _number(Map<String, Object?> map, List<String> keys) =>
      _nullableNumber(map, keys) ?? 0;

  static double? _nullableNumber(
    Map<String, Object?> map,
    List<String> keys,
  ) {
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
