import 'package:quality_line_erp/core/models/model_value_reader.dart';

class AccountStatementLineModel {
  const AccountStatementLineModel({
    required this.entryId,
    required this.entryNumber,
    required this.entryDate,
    required this.description,
    required this.currency,
    required this.debit,
    required this.credit,
    required this.runningBalance,
  });

  final String entryId;
  final String entryNumber;
  final DateTime entryDate;
  final String description;
  final String currency;
  final double debit;
  final double credit;
  final double runningBalance;

  AccountStatementLineModel copyWith({double? runningBalance}) {
    return AccountStatementLineModel(
      entryId: entryId,
      entryNumber: entryNumber,
      entryDate: entryDate,
      description: description,
      currency: currency,
      debit: debit,
      credit: credit,
      runningBalance: runningBalance ?? this.runningBalance,
    );
  }

  factory AccountStatementLineModel.fromMap(Map<String, dynamic> map) {
    final lineDescription = ModelValueReader.string(map, 'lineDescription');
    return AccountStatementLineModel(
      entryId: ModelValueReader.string(map, 'entryId'),
      entryNumber: ModelValueReader.string(map, 'entryNumber'),
      entryDate: ModelValueReader.requiredDateTime(
        map,
        'entryDate',
        aliases: const ['transactionDate', 'effectiveAt', 'createdAt'],
      ),
      description: lineDescription.trim().isNotEmpty
          ? lineDescription
          : ModelValueReader.string(map, 'entryDescription'),
      currency: ModelValueReader.string(map, 'currency').toUpperCase(),
      debit: ModelValueReader.decimal(map, 'debit'),
      credit: ModelValueReader.decimal(map, 'credit'),
      runningBalance: 0,
    );
  }
}
