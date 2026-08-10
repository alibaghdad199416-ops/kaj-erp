import 'package:quality_line_erp/core/models/model_value_reader.dart';

class SupplierModel {
  const SupplierModel({
    required this.id,
    required this.name,
    required this.phone,
    this.alternativePhone,
    this.address,
    this.companyName,
    this.taxNumber,
    this.notes,
    this.openingBalance = 0,
    this.currency = 'USD',
    required this.createdAt,
    this.updatedAt,
    this.isActive = true,
    this.photoBase64,
  });

  final String id;
  final String name;
  final String phone;
  final String? alternativePhone;
  final String? address;
  final String? companyName;
  final String? taxNumber;
  final String? notes;
  final double openingBalance;
  final String currency;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isActive;
  final String? photoBase64;

  void validate() {
    if (id.trim().isEmpty) throw ArgumentError('مرجع المورد غير صالح');
    if (name.trim().isEmpty) throw ArgumentError('اسم المورد مطلوب');
    if (phone.trim().isEmpty) throw ArgumentError('رقم هاتف المورد مطلوب');
    if (openingBalance < 0) throw ArgumentError('الرصيد الافتتاحي غير صحيح');
    if (currency != 'USD' && currency != 'IQD') {
      throw ArgumentError('عملة المورد غير مدعومة');
    }
  }

  SupplierModel copyWith({
    String? id,
    String? name,
    String? phone,
    String? alternativePhone,
    String? address,
    String? companyName,
    String? taxNumber,
    String? notes,
    double? openingBalance,
    String? currency,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isActive,
    String? photoBase64,
    bool clearPhoto = false,
  }) => SupplierModel(
    id: id ?? this.id,
    name: name ?? this.name,
    phone: phone ?? this.phone,
    alternativePhone: alternativePhone ?? this.alternativePhone,
    address: address ?? this.address,
    companyName: companyName ?? this.companyName,
    taxNumber: taxNumber ?? this.taxNumber,
    notes: notes ?? this.notes,
    openingBalance: openingBalance ?? this.openingBalance,
    currency: currency ?? this.currency,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    isActive: isActive ?? this.isActive,
    photoBase64: clearPhoto ? null : photoBase64 ?? this.photoBase64,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'phone': phone,
    'alternative_phone': alternativePhone,
    'address': address,
    'company_name': companyName,
    'tax_number': taxNumber,
    'notes': notes,
    'opening_balance': openingBalance,
    'currency': currency,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
    'is_active': isActive ? 1 : 0,
    'photoBase64': photoBase64,
  };

  Map<String, dynamic> toCloudMap() => {
    ...toMap(),
    'is_active': isActive,
    'photo_base64': photoBase64,
    'schema_version': 3,
  };

  factory SupplierModel.fromMap(Map<String, dynamic> map) => SupplierModel(
    id: ModelValueReader.string(map, 'id'),
    name: ModelValueReader.string(map, 'name'),
    phone: ModelValueReader.string(map, 'phone'),
    alternativePhone: ModelValueReader.nullableString(
      map,
      'alternative_phone',
      aliases: const ['alternativePhone'],
    ),
    address: ModelValueReader.nullableString(map, 'address'),
    companyName: ModelValueReader.nullableString(
      map,
      'company_name',
      aliases: const ['companyName'],
    ),
    taxNumber: ModelValueReader.nullableString(
      map,
      'tax_number',
      aliases: const ['taxNumber'],
    ),
    notes: ModelValueReader.nullableString(map, 'notes'),
    openingBalance: ModelValueReader.decimal(
      map,
      'opening_balance',
      aliases: const ['openingBalance'],
    ),
    currency: ModelValueReader.string(map, 'currency').toUpperCase(),
    createdAt: ModelValueReader.requiredDateTime(
      map,
      'created_at',
      aliases: const ['createdAt'],
    ),
    updatedAt: ModelValueReader.dateTime(
      map,
      'updated_at',
      aliases: const ['updatedAt'],
    ),
    isActive: ModelValueReader.boolean(
      map,
      'is_active',
      aliases: const ['isActive'],
      fallback: false,
    ),
    photoBase64: ModelValueReader.nullableString(
      map,
      'photoBase64',
      aliases: const ['photo_base64'],
    ),
  );

  factory SupplierModel.fromCloudMap(Map<String, dynamic> map) =>
      SupplierModel.fromMap(map);

  @override
  bool operator ==(Object other) => other is SupplierModel && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'SupplierModel(id: $id, name: $name, phone: $phone)';
}
