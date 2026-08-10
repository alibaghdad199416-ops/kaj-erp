import 'package:quality_line_erp/core/models/model_value_reader.dart';

class OperationalPeriod {
  const OperationalPeriod({
    required this.id,
    required this.module,
    required this.name,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    this.notes,
  });

  final String id;
  final String module;
  final String name;
  final DateTime startsAt;
  final DateTime endsAt;
  final String status;
  final String? notes;

  bool get isOpen => status == 'open';

  factory OperationalPeriod.fromMap(Map<String, dynamic> map) =>
      OperationalPeriod(
        id: map['id']?.toString() ?? '',
        module: map['module']?.toString() ?? 'all',
        name: map['period_name']?.toString() ?? '',
        startsAt: ModelValueReader.requiredDateTime(
          map,
          'starts_at',
          aliases: const ['startsAt'],
        ).toLocal(),
        endsAt: ModelValueReader.requiredDateTime(
          map,
          'ends_at',
          aliases: const ['endsAt'],
        ).toLocal(),
        status: ModelValueReader.string(map, 'status', fallback: 'unknown'),
        notes: map['notes']?.toString(),
      );
}
