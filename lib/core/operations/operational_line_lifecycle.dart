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
    required this.raw,
  });

  factory OperationalLineLifecycle.fromMap(Map<String, Object?> map) {
    final requiresLogistics = _requiresLogistics(map);
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
    final logistics = requiresLogistics
        ? _nonNegative(
            _number(
              map,
              const <String>[
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
              ],
            ),
          )
        : 0.0;
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
        'remainingOperational',
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
    final invoiceable = requiresLogistics ? logistics : requested;

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
      remainingLogisticsQuantity: requiresLogistics
          ? _nonNegative(
              explicitRemainingLogistics ?? (requested - logistics),
            )
          : 0,
      // Stock lines become invoiceable only after approved logistics. Service
      // lines have no inventory movement, so their requested quantity is the
      // invoiceable quantity and must never be reported as over-invoiced merely
      // because logisticsQuantity is intentionally zero.
      remainingInvoiceQuantity: _nonNegative(
        explicitRemainingInvoice ?? (invoiceable - invoiced),
      ),
      requiresLogistics: requiresLogistics,
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
  final Map<String, Object?> raw;

  static const double _epsilon = 0.000001;

  double get invoiceableQuantity =>
      requiresLogistics ? logisticsQuantity : requestedQuantity;

  bool get hasOverLogistics =>
      requiresLogistics && logisticsQuantity > requestedQuantity + _epsilon;

  bool get hasOverInvoice =>
      invoicedQuantity > invoiceableQuantity + _epsilon;

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
    if (explicitText == 'false' || explicitText == '0' || explicitText == 'no') {
      return false;
    }
    if (explicitText == 'true' || explicitText == '1' || explicitText == 'yes') {
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
