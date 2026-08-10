import 'package:quality_line_erp/core/models/model_value_reader.dart';

class BranchModel {
  const BranchModel({
    required this.id,
    required this.name,
    required this.code,
    required this.phone,
    required this.address,
    required this.isMain,
    required this.isActive,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String code;
  final String phone;
  final String address;
  final bool isMain;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'code': code,
    'phone': phone,
    'address': address,
    'isMain': isMain ? 1 : 0,
    'isActive': isActive ? 1 : 0,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };

  factory BranchModel.fromMap(Map<String, Object?> map) {
    final values = Map<String, dynamic>.from(map);
    return BranchModel(
      id: ModelValueReader.string(values, 'id'),
      name: ModelValueReader.string(values, 'name'),
      code: ModelValueReader.string(values, 'code'),
      phone: ModelValueReader.string(values, 'phone'),
      address: ModelValueReader.string(values, 'address'),
      isMain: ModelValueReader.boolean(values, 'isMain'),
      isActive: ModelValueReader.boolean(values, 'isActive', fallback: false),
      createdAt: ModelValueReader.requiredDateTime(
        values,
        'createdAt',
        aliases: const ['updatedAt', '_cloudUpdatedAt'],
      ),
      updatedAt: ModelValueReader.dateTime(values, 'updatedAt'),
    );
  }
}
