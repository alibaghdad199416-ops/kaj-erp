import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';
import 'package:quality_line_erp/features/accounting/cashbox/models/cash_transaction_model.dart';

/// Cashbox-specific adapter for the enterprise unified filter/query engine.
///
/// The page, cards, charts and exports can all reuse this adapter so search,
/// filters and sorting are resolved against one dataset contract.
abstract final class CashboxTransactionFilter {
  static final UnifiedFilterAdapter<CashTransactionModel> adapter =
      UnifiedFilterAdapter<CashTransactionModel>(
        searchableText: (transaction) => <Object?>[
          transaction.voucherNumber,
          transaction.category,
          transaction.currency,
          transaction.type,
          transaction.partyName,
          transaction.partyType,
          transaction.paymentMethod,
          transaction.referenceType,
          transaction.referenceId,
          transaction.notes,
          transaction.counterAccountId,
          transaction.journalEntryId,
          transaction.performedBy,
        ],
        type: (transaction) => transaction.type,
        partnerId: (transaction) => transaction.partyId,
        currency: (transaction) => transaction.currency,
        userId: (transaction) => transaction.performedBy,
        date: (transaction) => transaction.transactionDate,
        dimensions: <String, UnifiedValueReader<CashTransactionModel>>{
          'cashbox': (transaction) => transaction.cashAccountId,
          'reference': (transaction) => transaction.referenceId,
          'referenceType': (transaction) => transaction.referenceType,
          'sourceModule': (transaction) => _sourceModule(transaction),
          'paymentType': (transaction) => transaction.paymentMethod,
          'counterAccount': (transaction) => transaction.counterAccountId,
          'partyType': (transaction) => transaction.partyType,
          'category': (transaction) => transaction.category,
          'journalEntry': (transaction) => transaction.journalEntryId,
        },
        numericDimensions:
            <String, UnifiedNumericValueReader<CashTransactionModel>>{
              'amount': (transaction) => transaction.amount,
            },
        sortValues: <String, UnifiedValueReader<CashTransactionModel>>{
          'date': (transaction) => transaction.transactionDate,
          'amount': (transaction) => transaction.amount,
          'reference': (transaction) => transaction.voucherNumber,
          'party': (transaction) => transaction.partyName,
          'type': (transaction) => transaction.type,
          'currency': (transaction) => transaction.currency,
        },
      );

  static List<CashTransactionModel> apply(
    Iterable<CashTransactionModel> transactions,
    UnifiedFilterCriteria criteria,
  ) => UnifiedFilterEngine.apply<CashTransactionModel>(
    transactions,
    criteria: criteria,
    adapter: adapter,
  );

  static String _sourceModule(CashTransactionModel transaction) {
    final reference = (transaction.referenceType ?? '').trim().toLowerCase();
    final category = transaction.category.trim().toLowerCase();
    final combined = '$reference $category';
    if (combined.contains('purchase') || combined.contains('supplier')) {
      return 'purchases';
    }
    if (combined.contains('maintenance')) return 'maintenance';
    if (combined.contains('sale') || combined.contains('customer')) {
      return 'sales';
    }
    if (combined.contains('transfer')) return 'cashbox';
    if (combined.contains('journal')) return 'accounting';
    return reference.isEmpty ? category : reference;
  }
}
