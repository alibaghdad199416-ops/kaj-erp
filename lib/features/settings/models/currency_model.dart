class CurrencyModel {
  const CurrencyModel({
    required this.code,
    required this.name,
    required this.symbol,
    required this.exchangeRate,
    required this.isBase,
    required this.isActive,
  });

  final String code;
  final String name;
  final String symbol;
  final double exchangeRate;
  final bool isBase;
  final bool isActive;

  Map<String, Object?> toMap() => {
    'code': code,
    'name': name,
    'symbol': symbol,
    'exchangeRate': exchangeRate,
    'isBase': isBase ? 1 : 0,
    'isActive': isActive ? 1 : 0,
  };

  factory CurrencyModel.fromMap(Map<String, Object?> map) {
    bool readBool(Object? value) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      final normalized = value?.toString().toLowerCase();
      return normalized == 'true' || normalized == '1';
    }

    return CurrencyModel(
      code: map['code']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      symbol: map['symbol']?.toString() ?? '',
      exchangeRate:
          ((map['exchangeRate'] ?? map['exchange_rate']) as num?)?.toDouble() ??
          1,
      isBase: readBool(map['isBase'] ?? map['is_base']),
      isActive: readBool(map['isActive'] ?? map['is_active']),
    );
  }
}
