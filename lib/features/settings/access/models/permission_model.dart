class PermissionModel {
  const PermissionModel({
    required this.id,
    required this.code,
    required this.name,
    required this.module,
    required this.description,
  });
  final String id, code, name, module, description;
  factory PermissionModel.fromMap(Map<String, dynamic> m) => PermissionModel(
    id: m['id'] as String,
    code: m['code'] as String,
    name: m['name'] as String,
    module: m['module'] as String,
    description: (m['description'] as String?) ?? '',
  );
}
