import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';
import 'package:quality_line_erp/features/accounting/cashbox/models/cash_transaction_filter.dart';
import 'package:quality_line_erp/features/accounting/cashbox/models/cash_transaction_model.dart';

CashTransactionModel tx({
  required String id,
  required String voucher,
  required String type,
  required String category,
  required double amount,
  required String currency,
  required DateTime date,
  String? cashbox,
  String? partyId,
  String? partyName,
  String? referenceType,
  String? referenceId,
  String? performedBy,
  String paymentMethod = 'cash',
}) => CashTransactionModel(
  id: id,
  voucherNumber: voucher,
  type: type,
  category: category,
  amount: amount,
  currency: currency,
  transactionDate: date,
  partyType: 'customer',
  partyId: partyId,
  partyName: partyName,
  paymentMethod: paymentMethod,
  referenceType: referenceType,
  referenceId: referenceId,
  createdAt: date,
  cashAccountId: cashbox,
  performedBy: performedBy,
);

void main() {
  final rows = <CashTransactionModel>[
    tx(
      id: '1',
      voucher: 'RC-100',
      type: 'receipt',
      category: 'sales_invoice_payment',
      amount: 150,
      currency: 'USD',
      date: DateTime(2026, 8, 1),
      cashbox: 'cash-usd',
      partyId: 'customer-1',
      partyName: 'أحمد',
      referenceType: 'sales_payment',
      referenceId: 'invoice-1',
      performedBy: 'user-1',
    ),
    tx(
      id: '2',
      voucher: 'PY-200',
      type: 'payment',
      category: 'purchase_invoice_settlement',
      amount: 900000,
      currency: 'IQD',
      date: DateTime(2026, 8, 2),
      cashbox: 'cash-iqd',
      partyId: 'supplier-1',
      partyName: 'Supplier One',
      referenceType: 'purchases_payment',
      referenceId: 'invoice-2',
      performedBy: 'user-2',
      paymentMethod: 'bank_transfer',
    ),
    tx(
      id: '3',
      voucher: 'MP-300',
      type: 'receipt',
      category: 'maintenance_invoice_payment',
      amount: 75,
      currency: 'USD',
      date: DateTime(2026, 8, 3),
      cashbox: 'cash-usd',
      partyId: 'customer-2',
      partyName: 'Maintenance Customer',
      referenceType: 'maintenance_payment',
      referenceId: 'maintenance-invoice-1',
      performedBy: 'user-1',
    ),
  ];

  test('cashbox adapter combines text, currency, type and cashbox filters', () {
    final result = CashboxTransactionFilter.apply(
      rows,
      const UnifiedFilterCriteria(
        searchText: 'احمد',
        currencies: <String>{'USD'},
        types: <String>{'receipt'},
        dimensions: <String, Set<String>>{
          'cashbox': <String>{'cash-usd'},
        },
      ),
    );

    expect(result.map((item) => item.id), <String>['1']);
  });

  test('cashbox adapter filters source module, payment method and amount', () {
    final result = CashboxTransactionFilter.apply(
      rows,
      const UnifiedFilterCriteria(
        dimensions: <String, Set<String>>{
          'sourceModule': <String>{'purchases'},
          'paymentType': <String>{'bank_transfer'},
        },
        numericRanges: <String, UnifiedNumericRange>{
          'amount': UnifiedNumericRange(min: 800000, max: 1000000),
        },
      ),
    );

    expect(result.map((item) => item.id), <String>['2']);
  });

  test('cashbox adapter sorts one filtered dataset deterministically', () {
    final result = CashboxTransactionFilter.apply(
      rows,
      const UnifiedFilterCriteria(
        currencies: <String>{'USD'},
        sort: UnifiedSortSpec(
          'date',
          direction: UnifiedSortDirection.descending,
        ),
      ),
    );

    expect(result.map((item) => item.id), <String>['3', '1']);
  });
}
