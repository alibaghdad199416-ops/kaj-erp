class ExecutionAuditRow {
  const ExecutionAuditRow({
    required this.userName,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.createdAt,
  });

  final String userName;
  final String action;
  final String entityType;
  final String? entityId;
  final DateTime createdAt;
}
