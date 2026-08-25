class AccountModel {
  const AccountModel({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    this.parentId,
    required this.currency,
    required this.openingBalance,
    required this.isActive,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String code;
  final String name;
  final String type;
  final String? parentId;
  final String currency;
  final double openingBalance;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'code': code,
    'name': name,
    'type': type,
    'parentId': parentId,
    'currency': currency,
    'openingBalance': openingBalance,
    'isActive': isActive,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };

  factory AccountModel.fromMap(Map<String, dynamic> map) {
    final rawType = _text(map['type']).toLowerCase();
    final type = rawType;
    final currency = _text(map['currency']).toUpperCase();
    final parent = _text(map['parentId']);

    return AccountModel(
      id: _text(map['id']),
      code: _accountCode(map['code']),
      name: _text(map['name']),
      type: type,
      parentId: parent.isEmpty ? null : parent,
      currency: currency,
      openingBalance: _double(map['openingBalance']),
      isActive: _asBool(map['isActive'], fallback: false),
      createdAt: _requiredDate(map, const [
        'createdAt',
        'created_at',
        'updatedAt',
        'updated_at',
        '_cloudUpdatedAt',
      ]),
      updatedAt: _date(map['updatedAt']),
    );
  }

  static String _accountCode(Object? value) {
    final raw = _text(value);
    if (raw.isEmpty) return raw;
    // Account codes are database text identifiers. Preserve their hierarchy
    // and punctuation exactly; formatting belongs to monetary values only.
    return raw;
  }

  static String _text(Object? value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static double _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().trim() ?? '') ?? 0;
  }

  static DateTime _requiredDate(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = _date(map[key]);
      if (value != null) return value;
    }
    throw const FormatException(
      'Missing or invalid required timestamp: account.createdAt',
    );
  }

  static DateTime? _date(Object? value) {
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString().trim() ?? '');
  }

  static bool _asBool(Object? value, {bool fallback = false}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value.toString().trim().toLowerCase();
    if (const {'1', 'true', 'yes', 'on'}.contains(text)) return true;
    if (const {'0', 'false', 'no', 'off'}.contains(text)) return false;
    return fallback;
  }
}
