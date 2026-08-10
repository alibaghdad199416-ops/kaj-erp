import 'package:flutter/material.dart';

import 'package:quality_line_erp/features/accounting/installments/models/installment_model.dart';
import 'package:quality_line_erp/features/sales/data/sale_repository.dart';
import 'package:quality_line_erp/features/sales/models/sale_model.dart';
import 'package:quality_line_erp/core/events/app_data_change_bus.dart';

class SalesController extends ChangeNotifier {
  final SaleRepository _repository = SaleRepository();

  List<SaleModel> _sales = [];
  bool _isSaving = false;
  bool _hasLoaded = false;

  List<SaleModel> get sales => List.unmodifiable(_sales);
  bool get isSaving => _isSaving;
  bool get hasLoaded => _hasLoaded;

  Future<void> loadSales() async {
    _sales = await _repository.getSales();
    _hasLoaded = true;
    notifyListeners();
  }

  Future<void> addSale(SaleModel sale) async {
    try {
      await _repository.insertSale(sale);
      AppDataChangeBus.instance.publish(
        'sales',
        operation: 'insert',
        entityId: sale.id,
      );
    } finally {
      await loadSales();
    }
  }

  Future<void> createSale({
    required SaleModel sale,
    List<InstallmentModel> installments = const [],
  }) async {
    _isSaving = true;
    notifyListeners();

    try {
      await _repository.createSaleWithInstallments(
        sale: sale,
        installments: installments,
      );
      AppDataChangeBus.instance.publish('sales', operation: 'insert');
      await loadSales();
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> createResale(SaleModel sale) async {
    _isSaving = true;
    notifyListeners();
    try {
      await _repository.createResale(sale);
      AppDataChangeBus.instance.publish('sales', operation: 'resale');
      await loadSales();
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> updateSale(SaleModel sale) async {
    await _repository.updateSale(sale);
    AppDataChangeBus.instance.publish('sales', operation: 'update');
    await loadSales();
  }

  Future<void> removeSale(String id) async {
    await _repository.deleteSale(id);
    AppDataChangeBus.instance.publish('sales', operation: 'delete');
    await loadSales();
  }

  SaleModel? getSaleById(String id) {
    try {
      return _sales.firstWhere((sale) => sale.id == id);
    } catch (_) {
      return null;
    }
  }

  int get totalSales => _sales.length;

  Map<String, double> get revenueByCurrency =>
      _sumByCurrency((sale) => sale.salePrice);

  Map<String, double> get paidByCurrency =>
      _sumByCurrency((sale) => sale.paidAmount);

  Map<String, double> get remainingByCurrency =>
      _sumByCurrency((sale) => sale.remainingAmount);

  Map<String, double> _sumByCurrency(double Function(SaleModel sale) valueOf) {
    final totals = <String, double>{};
    for (final sale in _sales) {
      final currency = sale.currencyCode.trim().toUpperCase();
      if (currency.isEmpty) continue;
      totals.update(
        currency,
        (value) => value + valueOf(sale),
        ifAbsent: () => valueOf(sale),
      );
    }
    return Map.unmodifiable(totals);
  }
}
