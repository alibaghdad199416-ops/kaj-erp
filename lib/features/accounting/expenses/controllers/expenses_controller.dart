import 'package:flutter/foundation.dart';

import 'package:quality_line_erp/features/accounting/expenses/data/expense_repository.dart';
import 'package:quality_line_erp/features/accounting/expenses/models/expense_model.dart';
import 'package:quality_line_erp/core/events/app_data_change_bus.dart';

class ExpensesController extends ChangeNotifier {
  final ExpenseRepository repository = ExpenseRepository();

  List<ExpenseModel> expenses = [];

  double totalAmount = 0;

  bool isLoading = false;
  String? loadError;

  Future<void> loadExpenses() async {
    if (isLoading) return;
    isLoading = true;
    loadError = null;
    notifyListeners();
    try {
      final results = await Future.wait<Object>([
        repository.getExpenses(),
        repository.totalExpenses(),
      ]).timeout(const Duration(seconds: 20));
      expenses = results[0] as List<ExpenseModel>;
      totalAmount = results[1] as double;
    } catch (error) {
      loadError = error.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addExpense(ExpenseModel expense) async {
    await repository.addExpense(expense);
    AppDataChangeBus.instance.publish('expenses', operation: 'insert');

    await loadExpenses();
  }

  Future<void> deleteExpense(String id) async {
    await repository.deleteExpense(id);
    AppDataChangeBus.instance.publish('expenses', operation: 'delete');

    await loadExpenses();
  }

  Future<void> refresh() async {
    await loadExpenses();
  }
}
