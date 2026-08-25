class CommercialOrderDetails {
  const CommercialOrderDetails({
    required this.order,
    required this.items,
    required this.logistics,
    required this.invoices,
    required this.payments,
    required this.movements,
    required this.journalEntries,
    required this.auditTrail,
  });

  factory CommercialOrderDetails.fromRpc(Object? value) {
    final payload = value is Map
        ? Map<String, Object?>.from(value)
        : <String, Object?>{};

    List<Map<String, Object?>> rows(String key) =>
        ((payload[key] as List?) ?? const <Object?>[])
            .whereType<Map>()
            .map((row) => Map<String, Object?>.from(row))
            .toList(growable: true);

    final logistics = rows('logistics');
    final invoices = rows('invoices');
    final payments = rows('payments');
    final movements = rows('movements');

    // Older workflow rows can have complete payloads while the legacy summary
    // arrays are empty. Build deterministic read-only detail rows from those
    // payloads so Receipt/Delivery, Invoice, Payment and Movement tabs never
    // show "No linked data" when the approved document actually exists.
    if (payments.isEmpty) {
      for (final invoice in invoices) {
        final invoicePayload = invoice['payload'];
        if (invoicePayload is! Map) continue;
        final rawPayments = invoicePayload['payments'];
        if (rawPayments is! List) continue;
        for (final raw in rawPayments.whereType<Map>()) {
          payments.add(<String, Object?>{
            ...Map<String, Object?>.from(raw),
            'invoiceId': invoice['id'],
            'invoiceNumber': invoice['invoiceNumber'],
          });
        }
      }
    }
    if (movements.isEmpty) {
      for (final logisticsRow in logistics) {
        final payloadRow = logisticsRow['payload'];
        if (payloadRow is! Map) continue;
        final allocations = payloadRow['allocations'];
        if (allocations is! List) continue;
        for (final raw in allocations.whereType<Map>()) {
          final allocation = Map<String, Object?>.from(raw);
          movements.add(<String, Object?>{
            'id': '${logisticsRow['id']}:${allocation['itemId']}',
            'movementNumber':
                logisticsRow['receiptNumber'] ??
                logisticsRow['deliveryNumber'] ??
                logisticsRow['id'],
            'productId': allocation['itemId'],
            'productName': allocation['description'],
            'warehouseId': allocation['warehouseId'],
            'warehouseName':
                logisticsRow['warehouseName'] ?? allocation['warehouseId'],
            'sourceName': logisticsRow['sourceName'],
            'destinationName':
                logisticsRow['destinationName'] ??
                logisticsRow['warehouseName'] ??
                allocation['warehouseId'],
            'performedBy':
                logisticsRow['approvedBy'] ?? logisticsRow['performedBy'],
            'referenceDocumentNumber':
                logisticsRow['receiptNumber'] ??
                logisticsRow['deliveryNumber'] ??
                logisticsRow['id'],
            'quantity': allocation['quantity'],
            'movementType': logisticsRow['receiptNumber'] != null
                ? 'purchase_in'
                : 'sale_out',
            'movementDate':
                logisticsRow['receiptDate'] ??
                logisticsRow['deliveryDate'] ??
                logisticsRow['effectiveAt'] ??
                logisticsRow['createdAt'],
            'referenceType': logisticsRow['receiptNumber'] != null
                ? 'purchase_receipt'
                : 'sales_delivery',
            'referenceId': logisticsRow['id'],
            'rawData': allocation,
          });
        }
      }
    }

    return CommercialOrderDetails(
      order: payload['order'] is Map
          ? Map<String, Object?>.unmodifiable(
              Map<String, Object?>.from(payload['order'] as Map),
            )
          : null,
      items: List<Map<String, Object?>>.unmodifiable(rows('items')),
      logistics: List<Map<String, Object?>>.unmodifiable(logistics),
      invoices: List<Map<String, Object?>>.unmodifiable(invoices),
      payments: List<Map<String, Object?>>.unmodifiable(payments),
      movements: List<Map<String, Object?>>.unmodifiable(movements),
      journalEntries: List<Map<String, Object?>>.unmodifiable(
        rows('journalEntries'),
      ),
      auditTrail: List<Map<String, Object?>>.unmodifiable(rows('auditTrail')),
    );
  }

  final Map<String, Object?>? order;
  final List<Map<String, Object?>> items;
  final List<Map<String, Object?>> logistics;
  final List<Map<String, Object?>> invoices;
  final List<Map<String, Object?>> payments;
  final List<Map<String, Object?>> movements;
  final List<Map<String, Object?>> journalEntries;
  final List<Map<String, Object?>> auditTrail;
}
