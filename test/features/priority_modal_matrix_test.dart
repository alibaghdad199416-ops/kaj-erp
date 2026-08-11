import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/core/finance/invoice_payment_batch_dialog.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/features/accounting/cashbox/controllers/cashbox_controller.dart';
import 'package:quality_line_erp/features/accounting/cashbox/models/cash_account_model.dart';
import 'package:quality_line_erp/features/accounting/cashbox/pages/cash_account_form.dart';
import 'package:quality_line_erp/features/accounting/controllers/accounting_controller.dart';
import 'package:quality_line_erp/features/accounting/models/account_model.dart';
import 'package:quality_line_erp/features/business_partners/customers/controllers/customers_controller.dart';
import 'package:quality_line_erp/features/customer_service/controllers/opportunities_controller.dart';
import 'package:quality_line_erp/features/customer_service/models/opportunity_model.dart';
import 'package:quality_line_erp/features/customer_service/pages/add_opportunity_page.dart';
import 'package:quality_line_erp/features/inventory/cars/pages/add_car_page.dart';
import 'package:quality_line_erp/features/inventory/controllers/inventory_controller.dart';
import 'package:quality_line_erp/features/inventory/models/inventory_group_model.dart';
import 'package:quality_line_erp/features/inventory/models/warehouse_model.dart';
import 'package:quality_line_erp/features/inventory/pages/add_inventory_page.dart';
import 'package:quality_line_erp/features/inventory/pages/warehouse_management_page.dart';
import 'package:quality_line_erp/features/maintenance/models/maintenance_order_model.dart';
import 'package:quality_line_erp/features/maintenance/pages/maintenance_order_details_dialog.dart';
import 'package:quality_line_erp/features/sales/workflow/models/commercial_order_details.dart';
import 'package:quality_line_erp/features/sales/workflow/pages/order_details_dialog.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';
import 'package:quality_line_erp/features/settings/access/models/user_model.dart';

final _createdAt = DateTime.utc(2026, 8, 10);

final _admin = UserModel(
  id: 'visual-admin',
  username: 'visual-admin',
  fullName: 'Visual Matrix Administrator',
  email: 'visual@example.test',
  phone: '',
  roleId: 'role-admin',
  roleName: 'Administrator',
  passwordHash: '',
  isActive: true,
  createdAt: _createdAt,
);

final _ledger = AccountModel(
  id: 'cash-usd-ledger',
  code: '001.02-A',
  name: 'Operational cash and settlement account with a long name',
  type: 'asset',
  currency: 'USD',
  openingBalance: 0,
  isActive: true,
  createdAt: _createdAt,
);

final _cashAccount = CashAccountModel(
  id: 'cash-usd',
  name: 'Main operational cashbox',
  type: 'cash',
  currency: 'USD',
  openingBalance: 999999999.99,
  isActive: true,
  accountId: _ledger.id,
  createdAt: _createdAt,
);

class _AllowedAccessController extends AccessController {
  @override
  UserModel get currentUser => _admin;

  @override
  List<UserModel> get users => <UserModel>[_admin];

  @override
  bool hasPermission(String code) => true;

  @override
  bool canViewField(String resource, String field, {String? viewPermission}) =>
      true;

  @override
  bool canEditField(
    String resource,
    String field, {
    String? writePermission,
    String? viewPermission,
  }) => true;
}

class _MatrixAccountingController extends AccountingController {
  @override
  List<AccountModel> get accounts => <AccountModel>[_ledger];

  @override
  Future<void> ensureAccountsLoaded({bool force = false}) async {}
}

class _MatrixCashboxController extends CashboxController {
  @override
  List<AccountModel> get ledgerAccounts => <AccountModel>[_ledger];

  @override
  List<CashAccountModel> get cashAccounts => <CashAccountModel>[_cashAccount];
}

class _MatrixInventoryController extends InventoryController {
  @override
  List<WarehouseModel> get warehouses => const <WarehouseModel>[
    WarehouseModel(
      id: 'warehouse-1',
      code: 'WH-001',
      name: 'Central warehouse',
      address: 'A deliberately long warehouse address for responsive testing',
      isActive: true,
    ),
  ];

  @override
  List<WarehouseModel> get allWarehouses => warehouses;

  @override
  List<InventoryGroupModel> get groups => const <InventoryGroupModel>[
    InventoryGroupModel(
      id: 'group-1',
      code: 'GRP-001',
      name: 'General inventory products',
    ),
  ];
}

class _EmptyCustomersController extends CustomersController {}

class _EmptyOpportunitiesController extends OpportunitiesController {}

CommercialOrderDetails _commercialDetails({required bool purchase}) {
  final logisticsName = purchase ? 'REC0001' : 'DEL0001';
  return CommercialOrderDetails(
    order: <String, Object?>{
      'id': purchase ? 'purchase-order-1' : 'sales-order-1',
      'orderNumber': purchase ? 'PO0001' : 'SO0001',
      'opportunityId': purchase ? null : 'opportunity-1',
      'customerName': purchase
          ? null
          : 'Customer with a deliberately long enterprise display name',
      'supplierName': purchase
          ? 'Supplier with a deliberately long enterprise display name'
          : null,
      'status': 'completed',
      'currency': 'USD',
      'subtotal': 1000000000.99,
      'discount': 0,
      'total': 1000000000.99,
      'paidAmount': 1000000000.99,
      'remainingAmount': 0,
      'effectiveAt': '2026-08-10T10:30:00.000Z',
    },
    items: <Map<String, Object?>>[
      <String, Object?>{
        'id': 'item-1',
        'itemType': 'product',
        'description':
            'A long inventory item description used to exercise wrapping safely',
        'quantity': 25,
        purchase ? 'unitCost' : 'unitPrice': 40000000.0396,
        'lineTotal': 1000000000.99,
      },
    ],
    logistics: <Map<String, Object?>>[
      <String, Object?>{
        'id': 'logistics-1',
        purchase ? 'receiptNumber' : 'deliveryNumber': logisticsName,
        'warehouseName': 'Central warehouse with a long display name',
        'status': 'approved',
      },
    ],
    invoices: <Map<String, Object?>>[
      <String, Object?>{
        'id': 'invoice-1',
        'invoiceNumber': 'INV0001',
        'status': 'approved',
        'currency': 'USD',
        'total': 1000000000.99,
        'paidAmount': 1000000000.99,
        'remainingAmount': 0,
      },
    ],
    payments: <Map<String, Object?>>[
      <String, Object?>{
        'id': 'payment-1',
        'cashAccountName': 'Main operational cashbox',
        'cashAmount': 1000000000.99,
        'invoiceAmount': 1000000000.99,
        'paymentCurrency': 'USD',
        'settlementMode': 'full',
        'paymentDate': '2026-08-10T11:00:00.000Z',
      },
    ],
    movements: const <Map<String, Object?>>[],
    journalEntries: const <Map<String, Object?>>[],
    auditTrail: const <Map<String, Object?>>[],
  );
}

final _opportunity = OpportunityModel(
  id: 'opportunity-1',
  opportunityNumber: 'OPP0001',
  customerId: 'customer-1',
  customerName: 'عميل ذو اسم طويل لاختبار التفاف النص في النموذج',
  customerPhone: '07700000000',
  title: 'Enterprise opportunity with a long descriptive title',
  source: 'referral',
  expectedValue: 123456789.99,
  currency: 'USD',
  stage: 'proposal',
  probability: 65,
  description: 'Long optional opportunity description',
  status: OpportunityStatus.pending,
  assignedUserId: _admin.id,
  assignedUserName: _admin.fullName,
  createdByUserId: _admin.id,
  createdByUserName: _admin.fullName,
  createdAt: _createdAt,
  notes: null,
);

final _maintenance = MaintenanceOrderModel(
  id: 'maintenance-1',
  orderNumber: 'MO0001',
  carId: 'car-1',
  carName: 'Vehicle with a long model and specification description',
  customerId: 'customer-1',
  customerName: 'عميل صيانة ذو اسم طويل لاختبار العرض',
  warehouseId: 'warehouse-1',
  isSoldCar: true,
  pricingType: 'paid',
  status: 'completed',
  laborCost: 250000,
  partsCost: 750000,
  totalCost: 1000000,
  salePrice: 1250000,
  profit: 250000,
  carCostAdded: 0,
  maintenanceDate: '2026-08-10',
  currencyCode: 'IQD',
  workflowStage: 'completed',
  paidAmount: 1250000,
  invoiceNumber: 'MINV0001',
  stockIssueNumber: 'MISS0001',
);

typedef _SurfaceBuilder = Widget Function();

Map<String, _SurfaceBuilder> _surfaces() => <String, _SurfaceBuilder>{
  'Sales': () => OrderDetailsDialog(
    orderId: 'sales-order-1',
    purchase: false,
    initialDetails: _commercialDetails(purchase: false),
  ),
  'Purchases': () => OrderDetailsDialog(
    orderId: 'purchase-order-1',
    purchase: true,
    initialDetails: _commercialDetails(purchase: true),
  ),
  'Maintenance': () => MaintenanceOrderDetailsDialog(
    order: _maintenance,
    initialLines: const <MaintenanceLineModel>[
      MaintenanceLineModel(
        id: 'line-1',
        productId: 'product-1',
        productName: 'Long maintenance material description',
        quantity: 5,
        unitCost: 150000,
        unitPrice: 200000,
        lineType: 'stock',
        warehouseId: 'warehouse-1',
        warehouseName: 'Central warehouse',
      ),
    ],
  ),
  'Opportunity': () => AddOpportunityPage(opportunity: _opportunity),
  'Warehouse': () => const WarehouseEditor(
    warehouse: WarehouseModel(
      id: 'warehouse-1',
      code: 'WH-001',
      name: 'مخزن مركزي ذو اسم طويل للاختبار',
      address: 'A long optional warehouse address',
      notes: null,
      isActive: true,
    ),
  ),
  'Accounting': () => CashAccountForm(account: _cashAccount),
  'Payments': () => InvoicePaymentBatchDialog(
    invoiceCurrency: 'USD',
    remainingAmount: 1000000000.99,
    cashAccounts: <Map<String, Object?>>[
      <String, Object?>{
        'id': 'cash-usd',
        'name': 'Main operational USD cashbox with long name',
        'currency': 'USD',
        'accountId': 'cash-usd-ledger',
        'isActive': true,
      },
    ],
    settlementAccounts: const <Map<String, Object?>>[],
    purchase: false,
    documentLabelArabic: 'فاتورة مبيعات ذات وصف طويل',
    documentLabelEnglish: 'Sales invoice with a long descriptive label',
  ),
  'Cars': () => const AddCarPage(),
  'Products': () => const AddInventoryPage(),
};

Widget _testApp({required Locale locale, required Widget child}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AccessController>(
          create: (_) => _AllowedAccessController(),
        ),
        ChangeNotifierProvider<AccountingController>(
          create: (_) => _MatrixAccountingController(),
        ),
        ChangeNotifierProvider<CashboxController>(
          create: (_) => _MatrixCashboxController(),
        ),
        ChangeNotifierProvider<InventoryController>(
          create: (_) => _MatrixInventoryController(),
        ),
        ChangeNotifierProvider<CustomersController>(
          create: (_) => _EmptyCustomersController(),
        ),
        ChangeNotifierProvider<OpportunitiesController>(
          create: (_) => _EmptyOpportunitiesController(),
        ),
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: child,
      ),
    );

void main() {
  final viewports = <String, Size>{
    'wide': const Size(1440, 900),
    'medium': const Size(900, 760),
    'narrow': const Size(390, 700),
  };
  final locales = <String, Locale>{
    'EN': const Locale('en'),
    'AR': const Locale('ar'),
  };

  for (final module in _surfaces().entries) {
    for (final viewport in viewports.entries) {
      for (final locale in locales.entries) {
        testWidgets(
          '${module.key} ${viewport.key} ${locale.key} production surface fits',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = viewport.value;
            addTearDown(tester.view.reset);

            await tester.pumpWidget(
              _testApp(locale: locale.value, child: module.value()),
            );
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull);
            expect(
              tester
                  .widget<Directionality>(find.byType(Directionality).first)
                  .textDirection,
              locale.key == 'AR' ? TextDirection.rtl : TextDirection.ltr,
            );
            expect(find.byType(Scrollable), findsWidgets);
          },
        );
      }
    }
  }
}
