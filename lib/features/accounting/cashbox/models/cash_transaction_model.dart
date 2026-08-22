import 'package:quality_line_erp/core/models/model_value_reader.dart';

class CashTransactionModel {
  const CashTransactionModel({
    required this.id,
    required this.voucherNumber,
    required this.type,
    required this.category,
    required this.amount,
    required this.currency,
    required this.transactionDate,
    required this.partyType,
    this.partyId,
    this.partyName,
    required this.paymentMethod,
    this.referenceType,
    this.referenceId,
    this.notes,
    required this.createdAt,
    this.updatedAt,
    this.cashAccountId,
    this.counterAccountId,
    this.journalEntryId,
    this.performedBy,
  });

  final String id;
  final String voucherNumber;

  /// receipt or payment
  final String type;
  final String category;
  final double amount;
  final String currency;
  final DateTime transactionDate;

  /// customer, supplier, employee or other
  final String partyType;
  final String? partyId;
  final String? partyName;

  /// cash, bank_transfer, card or cheque
  final String paymentMethod;
  final String? referenceType;
  final String? referenceId;
  final String? notes;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? cashAccountId;
  final String? counterAccountId;
  final String? journalEntryId;
  final String? performedBy;

  bool get isReceipt => type == 'receipt';
  bool get isPayment => type == 'payment';

  CashTransactionModel copyWith({
    String? id,
    String? voucherNumber,
    String? type,
    String? category,
    double? amount,
    String? currency,
    DateTime? transactionDate,
    String? partyType,
    String? partyId,
    String? partyName,
    String? paymentMethod,
    String? referenceType,
    String? referenceId,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? cashAccountId,
    String? counterAccountId,
    String? journalEntryId,
    String? performedBy,
  }) {
    return CashTransactionModel(
      id: id ?? this.id,
      voucherNumber: voucherNumber ?? this.voucherNumber,
      type: type ?? this.type,
      category: category ?? this.category,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      transactionDate: transactionDate ?? this.transactionDate,
      partyType: partyType ?? this.partyType,
      partyId: partyId ?? this.partyId,
      partyName: partyName ?? this.partyName,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      referenceType: referenceType ?? this.referenceType,
      referenceId: referenceId ?? this.referenceId,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      cashAccountId: cashAccountId ?? this.cashAccountId,
      counterAccountId: counterAccountId ?? this.counterAccountId,
      journalEntryId: journalEntryId ?? this.journalEntryId,
      performedBy: performedBy ?? this.performedBy,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'voucherNumber': voucherNumber,
      'type': type,
      'category': category,
      'amount': amount,
      'currency': currency,
      'transactionDate': transactionDate.toIso8601String(),
      'partyType': partyType,
      'partyId': partyId,
      'partyName': partyName,
      'paymentMethod': paymentMethod,
      'referenceType': referenceType,
      'referenceId': referenceId,
      'notes': notes,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'cashAccountId': cashAccountId,
      'counterAccountId': counterAccountId,
      'journalEntryId': journalEntryId,
      'performedBy': performedBy,
    };
  }

  Map<String, dynamic> toCloudMap() => {
    'id': id,
    'voucherNumber': voucherNumber,
    'type': type,
    'category': category,
    'amount': amount,
    'currency': currency,
    'transactionDate': transactionDate.toUtc().toIso8601String(),
    'partyType': partyType,
    'partyId': partyId,
    'partyName': partyName,
    'paymentMethod': paymentMethod,
    'referenceType': referenceType,
    'referenceId': referenceId,
    'notes': notes,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
    'cashAccountId': cashAccountId,
    'counterAccountId': counterAccountId,
    'journalEntryId': journalEntryId,
  };

  factory CashTransactionModel.fromMap(Map<String, dynamic> map) {
    return CashTransactionModel(
      id: ModelValueReader.string(map, 'id'),
      voucherNumber: ModelValueReader.string(map, 'voucherNumber'),
      type: ModelValueReader.string(map, 'type'),
      category: ModelValueReader.string(map, 'category'),
      amount: ModelValueReader.decimal(map, 'amount'),
      currency: ModelValueReader.string(map, 'currency').toUpperCase(),
      transactionDate: ModelValueReader.requiredDateTime(
        map,
        'transactionDate',
        aliases: const ['createdAt'],
      ),
      partyType: ModelValueReader.string(map, 'partyType'),
      partyId: ModelValueReader.nullableString(map, 'partyId'),
      partyName: ModelValueReader.nullableString(map, 'partyName'),
      paymentMethod: ModelValueReader.string(map, 'paymentMethod'),
      referenceType: ModelValueReader.nullableString(map, 'referenceType'),
      referenceId: ModelValueReader.nullableString(map, 'referenceId'),
      notes: ModelValueReader.nullableString(map, 'notes'),
      createdAt: ModelValueReader.requiredDateTime(
        map,
        'createdAt',
        aliases: const ['transactionDate'],
      ),
      updatedAt: ModelValueReader.dateTime(map, 'updatedAt'),
      cashAccountId: ModelValueReader.nullableString(map, 'cashAccountId'),
      counterAccountId: ModelValueReader.nullableString(
        map,
        'counterAccountId',
      ),
      journalEntryId: ModelValueReader.nullableString(map, 'journalEntryId'),
      performedBy: ModelValueReader.nullableString(map, 'performedBy'),
    );
  }
}
