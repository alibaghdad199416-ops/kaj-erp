class JournalEntryModel {
  const JournalEntryModel({
    required this.id,
    required this.entryNumber,
    required this.entryDate,
    required this.description,
    required this.currency,
    this.referenceType,
    this.referenceId,
    required this.totalDebit,
    required this.totalCredit,
    required this.status,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String entryNumber;
  final DateTime entryDate;
  final String description;
  final String currency;
  final String? referenceType;
  final String? referenceId;
  final double totalDebit;
  final double totalCredit;
  final String status;
  final DateTime createdAt;
  final DateTime? updatedAt;

  bool get isBalanced => (totalDebit - totalCredit).abs() <= 0.01;
  String get sourceReferenceLabel => [
    referenceType?.trim(),
    referenceId?.trim(),
  ].whereType<String>().where((value) => value.isNotEmpty).join(' • ');

  Map<String, dynamic> toMap() => {
    'id': id,
    'entryNumber': entryNumber,
    'entryDate': entryDate.toIso8601String(),
    'description': description,
    'currency': currency,
    'referenceType': referenceType,
    'referenceId': referenceId,
    'totalDebit': totalDebit,
    'totalCredit': totalCredit,
    'status': status,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };

  factory JournalEntryModel.fromMap(Map<String, dynamic> map) {
    final rawCurrency = _text(map['currency']).toUpperCase();
    final referenceType = _text(map['referenceType']);
    final referenceId = _text(map['referenceId']);
    return JournalEntryModel(
      id: _text(map['id']),
      entryNumber: _text(map['entryNumber'], fallback: '-'),
      entryDate: _requiredDate(map, 'entryDate'),
      description: _text(map['description']),
      currency: rawCurrency,
      referenceType: referenceType.isEmpty ? null : referenceType,
      referenceId: referenceId.isEmpty ? null : referenceId,
      totalDebit: _double(map['totalDebit']),
      totalCredit: _double(map['totalCredit']),
      status: _text(map['status']),
      createdAt: _requiredDate(map, 'createdAt', fallbackKey: 'entryDate'),
      updatedAt: _date(map['updatedAt']),
    );
  }

  static String _text(Object? value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static double _double(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString().trim() ?? '') ?? 0;
  static DateTime _requiredDate(
    Map<String, dynamic> map,
    String key, {
    String? fallbackKey,
  }) {
    final direct = _date(map[key]);
    if (direct != null) return direct;
    if (fallbackKey != null) {
      final fallback = _date(map[fallbackKey]);
      if (fallback != null) return fallback;
    }
    throw FormatException('Missing or invalid required timestamp: $key');
  }

  static DateTime? _date(Object? value) => value is DateTime
      ? value
      : DateTime.tryParse(value?.toString().trim() ?? '');
}
