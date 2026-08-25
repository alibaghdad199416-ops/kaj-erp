import 'package:quality_line_erp/core/models/model_value_reader.dart';

class CustomerModel {
  const CustomerModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.address,
    required this.nationalId,
    required this.notes,
    required this.createdAt,
    this.photoBase64,
  });

  final String id;
  final String name;
  final String phone;
  final String address;
  final String nationalId;
  final String notes;
  final String createdAt;
  final String? photoBase64;

  DateTime? get createdAtDate => DateTime.tryParse(createdAt);

  void validate() {
    if (id.trim().isEmpty) throw ArgumentError('مرجع العميل غير صالح');
    if (name.trim().isEmpty) throw ArgumentError('اسم العميل مطلوب');
    if (phone.trim().isEmpty) throw ArgumentError('رقم هاتف العميل مطلوب');
  }

  CustomerModel copyWith({
    String? id,
    String? name,
    String? phone,
    String? address,
    String? nationalId,
    String? notes,
    String? createdAt,
    String? photoBase64,
    bool clearPhoto = false,
  }) {
    return CustomerModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      nationalId: nationalId ?? this.nationalId,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      photoBase64: clearPhoto ? null : photoBase64 ?? this.photoBase64,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'phone': phone,
    'address': address,
    'nationalId': nationalId,
    'notes': notes,
    'createdAt': createdAt,
    'photoBase64': photoBase64,
  };

  Map<String, dynamic> toCloudMap() => {
    'id': id,
    'name': name,
    'phone': phone,
    'address': address,
    'national_id': nationalId,
    'notes': notes,
    'created_at': createdAt,
    'photo_base64': photoBase64,
    'schema_version': 3,
  };

  factory CustomerModel.fromMap(Map<String, dynamic> map) => CustomerModel(
    id: ModelValueReader.string(map, 'id'),
    name: ModelValueReader.string(map, 'name'),
    phone: ModelValueReader.string(map, 'phone'),
    address: ModelValueReader.string(map, 'address'),
    nationalId: ModelValueReader.string(
      map,
      'nationalId',
      aliases: const ['national_id'],
    ),
    notes: ModelValueReader.string(map, 'notes'),
    createdAt: ModelValueReader.string(
      map,
      'createdAt',
      aliases: const ['created_at'],
      fallback: '',
    ),
    photoBase64: ModelValueReader.nullableString(
      map,
      'photoBase64',
      aliases: const ['photo_base64'],
    ),
  );

  factory CustomerModel.fromCloudMap(Map<String, dynamic> map) =>
      CustomerModel.fromMap(map);

  @override
  bool operator ==(Object other) => other is CustomerModel && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
