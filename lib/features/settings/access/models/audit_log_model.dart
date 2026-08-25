import 'package:quality_line_erp/core/models/model_value_reader.dart';

class AuditLogModel {
  const AuditLogModel({
    required this.id,
    required this.userName,
    required this.action,
    required this.module,
    required this.description,
    required this.createdAt,
    required this.entityType,
    required this.entityId,
    required this.severity,
    required this.outcome,
    required this.source,
    this.metadataJson,
    this.correlationId,
  });

  final String id;
  final String userName;
  final String action;
  final String module;
  final String description;
  final String entityType;
  final String? entityId;
  final String severity;
  final String outcome;
  final String source;
  final String? metadataJson;
  final String? correlationId;
  final DateTime createdAt;

  bool get isDenied => outcome == 'denied' || action == 'denied';
  bool get isFailure => outcome == 'failure';

  factory AuditLogModel.fromMap(Map<String, dynamic> map) {
    final action = ModelValueReader.string(map, 'action');
    return AuditLogModel(
      id: ModelValueReader.string(map, 'id'),
      userName: ModelValueReader.string(map, 'userName', fallback: 'System'),
      action: action,
      module: ModelValueReader.string(map, 'module'),
      description: ModelValueReader.string(map, 'description'),
      entityType: ModelValueReader.string(map, 'entityType'),
      entityId: ModelValueReader.nullableString(map, 'entityId'),
      severity: ModelValueReader.string(map, 'severity', fallback: 'info'),
      outcome: ModelValueReader.string(
        map,
        'outcome',
        fallback: action == 'denied' ? 'denied' : 'unknown',
      ),
      source: ModelValueReader.string(map, 'source', fallback: 'application'),
      metadataJson: ModelValueReader.nullableString(map, 'metadataJson'),
      correlationId: ModelValueReader.nullableString(map, 'correlationId'),
      createdAt: ModelValueReader.requiredDateTime(
        map,
        'createdAt',
        aliases: const ['performedAt', 'updatedAt', '_cloudUpdatedAt'],
      ),
    );
  }
}
