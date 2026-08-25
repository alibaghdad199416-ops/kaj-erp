import 'package:quality_line_erp/features/accounting/models/account_statement_line_model.dart';

class AccountStatementResult {
  const AccountStatementResult({
    required this.openingBalance,
    required this.lines,
  });

  final double openingBalance;
  final List<AccountStatementLineModel> lines;

  double get closingBalance =>
      lines.isEmpty ? openingBalance : lines.last.runningBalance;
}
