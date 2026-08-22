import 'package:quality_line_erp/features/maintenance/models/maintenance_cost_reconciliation.dart';
import 'package:quality_line_erp/features/maintenance/models/maintenance_order_model.dart';

class MaintenanceOrderSnapshot {
  const MaintenanceOrderSnapshot({
    required this.order,
    required this.lines,
    required this.reconciliation,
    required this.snapshotAt,
  });

  factory MaintenanceOrderSnapshot.fromRpc(Object? value) {
    if (value is! Map) {
      throw StateError('maintenance_order_snapshot_invalid');
    }
    final map = Map<String, Object?>.from(value);
    final order = map['order'];
    if (order is! Map) {
      throw StateError('maintenance_order_snapshot_order_missing');
    }
    final reconciliation = map['reconciliation'];
    final issueState = map['issueState'];
    if (reconciliation is! Map || issueState is! Map) {
      throw StateError('maintenance_order_snapshot_reconciliation_missing');
    }
    final lines = (map['lines'] as List? ?? const <Object?>[])
        .whereType<Map>()
        .map(
          (row) => MaintenanceLineModel.fromMap(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
    return MaintenanceOrderSnapshot(
      order: MaintenanceOrderModel.fromMap(Map<String, dynamic>.from(order)),
      lines: List<MaintenanceLineModel>.unmodifiable(lines),
      reconciliation: mergeMaintenanceReconciliationPayloads(
        reconciliation: Map<String, Object?>.from(reconciliation),
        issueState: Map<String, Object?>.from(issueState),
      ),
      snapshotAt: DateTime.tryParse(
        map['snapshotAt']?.toString() ?? '',
      )?.toUtc(),
    );
  }

  final MaintenanceOrderModel order;
  final List<MaintenanceLineModel> lines;
  final MaintenanceCostReconciliation reconciliation;
  final DateTime? snapshotAt;
}
