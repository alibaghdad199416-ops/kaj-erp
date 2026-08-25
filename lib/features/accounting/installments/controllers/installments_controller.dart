import 'package:flutter/material.dart';

import 'package:quality_line_erp/features/accounting/installments/data/installment_repository.dart';
import 'package:quality_line_erp/features/accounting/installments/models/installment_model.dart';

class InstallmentsController extends ChangeNotifier {
  final InstallmentRepository _repository = InstallmentRepository();

  List<InstallmentModel> _installments = [];

  List<InstallmentModel> get installments => List.unmodifiable(_installments);

  bool _isLoading = false;

  bool get isLoading => _isLoading;

  Future<void> loadInstallments() async {
    _isLoading = true;
    notifyListeners();

    _installments = await _repository.getInstallments();

    _isLoading = false;
    notifyListeners();
  }

  Future<List<InstallmentModel>> loadInstallmentsBySale(String saleId) async {
    return await _repository.getInstallmentsBySale(saleId);
  }

  int get totalInstallments => _installments.length;

  Map<String, double> get totalAmountByCurrency =>
      _sumByCurrency((item) => item.amount);

  Map<String, double> get totalPaidByCurrency =>
      _sumByCurrency((item) => item.paidAmount);

  Map<String, double> get totalRemainingByCurrency =>
      _sumByCurrency((item) => item.remainingAmount);

  Map<String, double> _sumByCurrency(
    double Function(InstallmentModel item) valueOf,
  ) {
    final totals = <String, double>{};
    for (final item in _installments) {
      final currency = item.currencyCode.trim().toUpperCase();
      if (currency.isEmpty) continue;
      totals.update(
        currency,
        (value) => value + valueOf(item),
        ifAbsent: () => valueOf(item),
      );
    }
    return Map.unmodifiable(totals);
  }

  int get paidCount {
    return _installments.where((e) => e.status == 'مدفوع').length;
  }

  int get unpaidCount {
    return _installments.where((e) => e.status == 'غير مدفوع').length;
  }

  int get partialCount {
    return _installments.where((e) => e.status == 'مدفوع جزئياً').length;
  }
}
