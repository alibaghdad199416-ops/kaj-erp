class RoleModel {
  const RoleModel({
    required this.id,
    required this.name,
    required this.description,
    required this.isSystem,
    required this.isActive,
  });
  final String id, name, description;
  final bool isSystem, isActive;
  factory RoleModel.fromMap(Map<String, dynamic> m) => RoleModel(
    id: m['id'] as String,
    name: m['name'] as String,
    description: (m['description'] as String?) ?? '',
    isSystem: (m['isSystem'] as num?)?.toInt() == 1,
    isActive: (m['isActive'] as num?)?.toInt() != 0,
  );
}
