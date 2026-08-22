enum PartnerRecordDestination {
  opportunity,
  maintenance,
  salesOrder,
  purchaseOrder,
}

class PartnerRecordRoute {
  const PartnerRecordRoute({required this.destination, required this.id});

  final PartnerRecordDestination destination;
  final String id;

  static PartnerRecordRoute? resolve(Map<String, Object?> record) {
    final type = record['entityType']?.toString().trim().toLowerCase() ?? '';
    final id = record['id']?.toString().trim() ?? '';
    final parentId = record['parentId']?.toString().trim() ?? '';

    if (type == 'opportunity' && id.isNotEmpty) {
      return PartnerRecordRoute(
        destination: PartnerRecordDestination.opportunity,
        id: id,
      );
    }
    if (type == 'maintenance' && id.isNotEmpty) {
      return PartnerRecordRoute(
        destination: PartnerRecordDestination.maintenance,
        id: id,
      );
    }
    if (type == 'sales_order' && id.isNotEmpty) {
      return PartnerRecordRoute(
        destination: PartnerRecordDestination.salesOrder,
        id: id,
      );
    }
    if (type.startsWith('sales_') && parentId.isNotEmpty) {
      return PartnerRecordRoute(
        destination: PartnerRecordDestination.salesOrder,
        id: parentId,
      );
    }
    if (type == 'purchase_order' && id.isNotEmpty) {
      return PartnerRecordRoute(
        destination: PartnerRecordDestination.purchaseOrder,
        id: id,
      );
    }
    if ((type.startsWith('purchase_') || type.startsWith('purchases_')) &&
        parentId.isNotEmpty) {
      return PartnerRecordRoute(
        destination: PartnerRecordDestination.purchaseOrder,
        id: parentId,
      );
    }
    return null;
  }
}
