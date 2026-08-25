import 'package:flutter/material.dart';

import 'package:quality_line_erp/features/business_partners/customers/data/customer_repository.dart';
import 'package:quality_line_erp/features/business_partners/customers/models/customer_model.dart';
import 'package:quality_line_erp/core/events/app_data_change_bus.dart';

class CustomersController extends ChangeNotifier {
  final CustomerRepository _repository = CustomerRepository();

  List<CustomerModel> _customers = [];
  bool _hasLoaded = false;

  List<CustomerModel> get customers => List.unmodifiable(_customers);
  bool get hasLoaded => _hasLoaded;

  Future<void> loadCustomers() async {
    _customers = await _repository.getCustomers();
    _hasLoaded = true;
    notifyListeners();
  }

  Future<void> addCustomer(CustomerModel customer) async {
    await _repository.insertCustomer(customer);
    _customers = <CustomerModel>[customer, ..._customers];
    notifyListeners();
    AppDataChangeBus.instance.publish(
      'customers',
      operation: 'insert',
      entityId: customer.id,
    );
  }

  Future<void> updateCustomer(CustomerModel customer) async {
    await _repository.updateCustomer(customer);
    final index = _customers.indexWhere((value) => value.id == customer.id);
    if (index >= 0) {
      _customers = List<CustomerModel>.from(_customers)..[index] = customer;
    } else {
      _customers = <CustomerModel>[customer, ..._customers];
    }
    notifyListeners();
    AppDataChangeBus.instance.publish(
      'customers',
      operation: 'update',
      entityId: customer.id,
    );
  }

  Future<void> removeCustomer(String id) async {
    await _repository.deleteCustomer(id);
    _customers = _customers
        .where((value) => value.id != id)
        .toList(growable: false);
    notifyListeners();
    AppDataChangeBus.instance.publish(
      'customers',
      operation: 'delete',
      entityId: id,
    );
  }
}
