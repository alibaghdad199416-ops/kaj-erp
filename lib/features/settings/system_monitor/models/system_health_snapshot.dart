class SystemHealthSnapshot {
  const SystemHealthSnapshot({
    required this.generatedAt,
    required this.databaseTableCount,
    required this.totalLocalRecords,
    required this.pendingSyncOperations,
    required this.failedSyncOperations,
    required this.activeSessions,
    required this.backupCount,
    required this.auditLogCount,
    this.oldestPendingAt,
    this.lastBackupAt,
    this.lastBackupStatus,
  });

  final DateTime generatedAt;
  final int databaseTableCount;
  final int totalLocalRecords;
  final int pendingSyncOperations;
  final int failedSyncOperations;
  final int activeSessions;
  final int backupCount;
  final int auditLogCount;
  final DateTime? oldestPendingAt;
  final DateTime? lastBackupAt;
  final String? lastBackupStatus;
}
