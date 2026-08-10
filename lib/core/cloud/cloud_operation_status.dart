class CloudOperationResult {
  const CloudOperationResult({
    required this.success,
    required this.message,
    this.uploaded = 0,
    this.downloaded = 0,
  });

  final bool success;
  final String message;
  final int uploaded;
  final int downloaded;
}

class CloudRuntimeStatus {
  CloudOperationResult? lastResult;
  DateTime? lastOperationStartedAt;
  DateTime? lastOperationCompletedAt;

  bool get isInitialized => true;
  bool get automaticSyncEnabled => false;
  String get realtimeStatus => 'cloud-direct';
}
