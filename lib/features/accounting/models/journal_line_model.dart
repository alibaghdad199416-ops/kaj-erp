class JournalLineModel {
  const JournalLineModel({
    required this.id,
    required this.entryId,
    required this.accountId,
    required this.accountCode,
    required this.accountName,
    required this.debit,
    required this.credit,
    this.description,
  });

  final String id;
  final String entryId;
  final String accountId;
  final String accountCode;
  final String accountName;
  final double debit;
  final double credit;
  final String? description;

  /// A journal line must never carry both debit and credit simultaneously.
  /// The database remains authoritative; this is a defensive model invariant.
  bool get isValidAmount =>
      debit >= 0 && credit >= 0 && (debit == 0 || credit == 0);

  Map<String, dynamic> toMap() => {
    'id': id,
    'entryId': entryId,
    'accountId': accountId,
    'accountCode': accountCode,
    'accountName': accountName,
    'debit': debit,
    'credit': credit,
    'description': description,
  };

  factory JournalLineModel.fromMap(Map<String, dynamic> map) {
    final description = _text(map['description']);
    return JournalLineModel(
      id: _text(map['id']),
      entryId: _text(map['entryId']),
      accountId: _text(map['accountId']),
      accountCode: _text(map['accountCode'], fallback: '-'),
      accountName: _text(map['accountName'], fallback: 'حساب غير معروف'),
      debit: _double(map['debit']),
      credit: _double(map['credit']),
      description: description.isEmpty ? null : description,
    );
  }

  static String _text(Object? value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static double _double(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString().trim() ?? '') ?? 0;
}
