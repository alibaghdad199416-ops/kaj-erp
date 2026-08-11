import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/features/business_partners/customers/controllers/customers_controller.dart';
import 'package:quality_line_erp/features/business_partners/customers/data/customer_repository.dart';
import 'package:quality_line_erp/features/business_partners/customers/models/customer_model.dart';
import 'package:quality_line_erp/features/business_partners/suppliers/controllers/suppliers_controller.dart';
import 'package:quality_line_erp/features/business_partners/suppliers/models/supplier_model.dart';
import 'package:quality_line_erp/features/business_partners/suppliers/repositories/supplier_repository.dart';

const _customerDraft = CustomerModel(
  id: 'customer-1',
  name: 'Local customer name',
  phone: '100',
  address: '',
  nationalId: '',
  notes: '',
  createdAt: '2026-08-10T08:00:00.000Z',
);

const _customerCanonical = CustomerModel(
  id: 'customer-1',
  name: 'Canonical customer name',
  phone: '100',
  address: '',
  nationalId: '',
  notes: '',
  createdAt: '2026-08-10T08:00:01.000Z',
);

class _CustomerRepository extends CustomerRepository {
  int reads = 0;

  @override
  Future<void> insertCustomer(CustomerModel customer) async {}

  @override
  Future<void> updateCustomer(CustomerModel customer) async {}

  @override
  Future<List<CustomerModel>> getCustomers() async {
    reads++;
    return const [_customerCanonical];
  }
}

final _supplierDraft = SupplierModel(
  id: 'supplier-1',
  name: 'Local supplier name',
  phone: '200',
  createdAt: DateTime.utc(2026, 8, 10, 8),
);

final _supplierCanonical = SupplierModel(
  id: 'supplier-1',
  name: 'Canonical supplier name',
  phone: '200',
  createdAt: DateTime.utc(2026, 8, 10, 8),
  updatedAt: DateTime.utc(2026, 8, 10, 8, 0, 1),
);

class _SupplierRepository extends SupplierRepository {
  int reads = 0;

  @override
  Future<bool> phoneExists({
    required String phone,
    String? excludeSupplierId,
  }) async => false;

  @override
  Future<void> addSupplier(SupplierModel supplier) async {}

  @override
  Future<void> updateSupplier(SupplierModel supplier) async {}

  @override
  Future<void> setSupplierActive({
    required String id,
    required bool isActive,
  }) async {}

  @override
  Future<List<SupplierModel>> getSuppliers() async {
    reads++;
    return [_supplierCanonical];
  }
}

void main() {
  group('authoritative master-data mutation read-back', () {
    test(
      'customer create and update display the canonical server row',
      () async {
        final repository = _CustomerRepository();
        final controller = CustomersController(repository: repository);

        await controller.addCustomer(_customerDraft);
        expect(controller.customers.single.name, _customerCanonical.name);
        expect(
          controller.customers.single.createdAt,
          _customerCanonical.createdAt,
        );

        await controller.updateCustomer(_customerDraft);
        expect(controller.customers.single.name, _customerCanonical.name);
        expect(repository.reads, 2);
      },
    );

    test(
      'supplier create, update, and status use canonical read-back',
      () async {
        final repository = _SupplierRepository();
        final controller = SuppliersController(repository: repository);

        await controller.addSupplier(_supplierDraft);
        expect(controller.suppliers.single.name, _supplierCanonical.name);
        expect(
          controller.suppliers.single.updatedAt,
          _supplierCanonical.updatedAt,
        );

        await controller.updateSupplier(_supplierDraft);
        await controller.toggleSupplierStatus(_supplierDraft);
        expect(controller.suppliers.single.name, _supplierCanonical.name);
        expect(repository.reads, 3);
      },
    );
  });
}
