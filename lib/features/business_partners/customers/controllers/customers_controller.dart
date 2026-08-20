import 'package:flutter/material.dart';

import 'package:quality_line_erp/features/business_partners/customers/data/customer_repository.dart';
import 'package:quality_line_erp/features/business_partners/customers/models/customer_model.dart';
import 'package:quality_line_erp/core/events/app_data_change_bus.dart';

class CustomersController extends ChangeNotifier {
  CustomersController({CustomerRepository? repository})
    : _repository = repository ?? CustomerRepository();

  final CustomerRepository _repository;

  List<CustomerModel> _customers = [];
  bool _hasLoaded = false;
  Future<void>? _loadInFlight;

  List<CustomerModel> get customers => List.unmodifiable(_customers);
  bool get hasLoaded => _hasLoaded;

  Future<void> loadCustomers({bool force = false}) {
    if (!force && _hasLoaded) return Future<void>.value();
    final active = _loadInFlight;
    if (active != null) return active;
    final future = _loadCustomers();
    _loadInFlight = future;
    return future.whenComplete(() {
      if (identical(_loadInFlight, future)) _loadInFlight = null;
    });
  }

  Future<void> _loadCustomers() async {
    _customers = await _repository.getCustomers();
    _hasLoaded = true;
    notifyListeners();
  }

  Future<void> addCustomer(CustomerModel customer) async {
    await _repository.insertCustomer(customer);
    await loadCustomers(force: true);
    AppDataChangeBus.instance.publish(
      'customers',
      operation: 'insert',
      entityId: customer.id,
    );
  }

  Future<void> updateCustomer(CustomerModel customer) async {
    await _repository.updateCustomer(customer);
    await loadCustomers(force: true);
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
