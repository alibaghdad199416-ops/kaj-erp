import 'package:quality_line_erp/core/models/model_value_reader.dart';

class BackupModel {
  const BackupModel({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.sizeBytes,
    required this.checksum,
    required this.schemaVersion,
    required this.recordCount,
    required this.status,
    this.lastVerifiedAt,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final int sizeBytes;
  final String checksum;
  final int schemaVersion;
  final int recordCount;
  final String status;
  final DateTime? lastVerifiedAt;

  bool get isVerified => status == 'verified';

  factory BackupModel.fromMap(Map<String, Object?> map) {
    final values = Map<String, dynamic>.from(map);
    return BackupModel(
      id: ModelValueReader.string(values, 'id'),
      name: ModelValueReader.string(values, 'name'),
      createdAt: ModelValueReader.requiredDateTime(
        values,
        'createdAt',
        aliases: const ['updatedAt', '_cloudUpdatedAt'],
      ),
      sizeBytes: ModelValueReader.integer(values, 'sizeBytes'),
      checksum: ModelValueReader.string(values, 'checksum'),
      schemaVersion: ModelValueReader.integer(values, 'schemaVersion'),
      recordCount: ModelValueReader.integer(values, 'recordCount'),
      status: ModelValueReader.string(values, 'status', fallback: 'legacy'),
      lastVerifiedAt: ModelValueReader.dateTime(values, 'lastVerifiedAt'),
    );
  }
}
