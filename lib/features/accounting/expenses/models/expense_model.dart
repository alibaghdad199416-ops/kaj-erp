import 'package:quality_line_erp/core/models/model_value_reader.dart';

class ExpenseModel {
  const ExpenseModel({
    required this.id,
    required this.title,
    required this.category,
    required this.amount,
    required this.date,
    this.notes,
    this.accountId,
    this.expenseAccountId,
    this.branchId = 'branch-main',
    this.currency = 'USD',
    this.exchangeRate = 1,
    this.amountUsd = 0,
    this.amountIqd = 0,
    this.postingStatus = 'draft',
    this.journalEntryId,
    this.approvalStatus = 'approved',
  });

  final String id;
  final String title;
  final String category;
  final double amount;
  final String date;
  final String? notes;
  final String? accountId;
  final String? expenseAccountId;
  final String branchId;
  final String currency;
  final double exchangeRate;
  final double amountUsd;
  final double amountIqd;
  final String postingStatus;
  final String? journalEntryId;
  final String approvalStatus;

  factory ExpenseModel.fromMap(Map<String, dynamic> map) => ExpenseModel(
    id: ModelValueReader.string(map, 'id'),
    title: ModelValueReader.string(map, 'title'),
    category: ModelValueReader.string(map, 'category'),
    amount: ModelValueReader.decimal(map, 'amount'),
    date: ModelValueReader.string(map, 'date'),
    notes: ModelValueReader.nullableString(map, 'notes'),
    accountId: ModelValueReader.nullableString(map, 'accountId'),
    expenseAccountId: ModelValueReader.nullableString(map, 'expenseAccountId'),
    branchId: ModelValueReader.string(map, 'branchId', fallback: 'branch-main'),
    currency: ModelValueReader.string(map, 'currency').toUpperCase(),
    exchangeRate: ModelValueReader.decimal(map, 'exchangeRate', fallback: 1),
    amountUsd: ModelValueReader.decimal(map, 'amountUsd'),
    amountIqd: ModelValueReader.decimal(map, 'amountIqd'),
    postingStatus: ModelValueReader.string(
      map,
      'postingStatus',
      fallback: 'draft',
    ),
    journalEntryId: ModelValueReader.nullableString(map, 'journalEntryId'),
    approvalStatus: ModelValueReader.string(
      map,
      'approvalStatus',
      fallback: 'pending',
    ),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'category': category,
    'amount': amount,
    'date': date,
    'notes': notes,
    'accountId': accountId,
    'expenseAccountId': expenseAccountId,
    'branchId': branchId,
    'currency': currency,
    // Expenses remain in their selected document currency. Currency conversion
    // is recorded only by payment, settlement, and cash-transfer workflows.
    'exchangeRate': 1,
    'amountUsd': currency == 'USD' ? amount : 0,
    'amountIqd': currency == 'IQD' ? amount : 0,
    'postingStatus': postingStatus,
    'journalEntryId': journalEntryId,
    'approvalStatus': approvalStatus,
  };
}
