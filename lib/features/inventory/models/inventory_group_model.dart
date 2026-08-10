class InventoryGroupModel {
  const InventoryGroupModel({
    required this.id,
    required this.code,
    required this.name,
    this.description,
  });

  final String id;
  final String code;
  final String name;
  final String? description;

  factory InventoryGroupModel.fromMap(Map<String, dynamic> map) =>
      InventoryGroupModel(
        id: map['id']?.toString() ?? '',
        code: map['code']?.toString() ?? '',
        name: map['name']?.toString() ?? '',
        description: map['description']?.toString(),
      );

  Map<String, dynamic> toMap() => {
    'id': id,
    'code': code,
    'name': name,
    'description': description,
    'isActive': true,
    'createdAt': DateTime.now().toIso8601String(),
  };
}
