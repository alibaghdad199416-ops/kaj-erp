import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/filtering/unified_query.dart';
import 'package:quality_line_erp/core/filtering/unified_query_executor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/core/widgets/app_dialog.dart';
import 'package:quality_line_erp/core/widgets/app_empty.dart';
import 'package:quality_line_erp/core/widgets/app_entity_page.dart';
import 'package:quality_line_erp/core/widgets/app_module_dialog.dart';
import 'package:quality_line_erp/design_system/kaj_query_toolbar.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:quality_line_erp/features/business_partners/customers/controllers/customers_controller.dart';
import 'package:quality_line_erp/features/business_partners/customers/models/customer_model.dart';
import 'package:quality_line_erp/features/business_partners/customers/widgets/customer_card.dart';
import 'package:quality_line_erp/features/business_partners/customers/widgets/customers_statistics.dart';
import 'package:quality_line_erp/features/business_partners/shared/data/business_partner_card_service.dart';
import 'package:quality_line_erp/features/business_partners/shared/widgets/business_partner_profile_dialog.dart';
import 'add_customer_page.dart';
import 'edit_customer_page.dart';

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key});

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  late final UnifiedQueryController _queryController = UnifiedQueryController(
    const UnifiedQueryState(
      sorts: <UnifiedSortRule>[
        UnifiedSortRule(
          field: 'created_at',
          label: 'الأحدث',
          descending: true,
        ),
      ],
    ),
  );

  @override
  void initState() {
    super.initState();
    _queryController.addListener(_onQueryChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) await context.read<CustomersController>().loadCustomers();
    });
  }

  void _onQueryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _queryController.removeListener(_onQueryChanged);
    _queryController.dispose();
    super.dispose();
  }

  List<CustomerModel> _applyQuery(List<CustomerModel> customers) {
    final access = context.read<AccessController>();
    final executor = UnifiedQueryExecutor<CustomerModel>(
      criteriaBuilder: (state) => UnifiedFilterCriteria(
        searchText: state.search,
      ),
      filterAdapter: UnifiedFilterAdapter<CustomerModel>(
        searchableText: (customer) {
          final values = <Object?>[
            customer.name,
            customer.phone,
            customer.address,
            customer.notes,
          ];
          if (access.canViewField(
            'customers',
            'nationalId',
            viewPermission: 'customers.view',
          )) {
            values.add(customer.nationalId);
          }
          return values;
        },
        date: (customer) => customer.createdAtDate,
      ),
      sort: (left, right, field) {
        if (field == 'name') {
          return left.name.toLowerCase().compareTo(right.name.toLowerCase());
        }
        final aDate = left.createdAtDate;
        final bDate = right.createdAtDate;
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return aDate.compareTo(bDate);
      },
    );
    return executor.execute(customers, _queryController.state);
  }

  @override
  Widget build(BuildContext context) {
    final customers = context.watch<CustomersController>().customers;
    final canCreate = PermissionAction.allowed(context, 'customers.create');
    final filteredCustomers = _applyQuery(customers);
    final hasSearch = _queryController.state.search.trim().isNotEmpty;

    return AppEntityPage(
      hideHeader: true,
      title: 'إدارة العملاء',
      subtitle: 'إدارة بيانات العملاء وسجل التعامل معهم.',
      actions: [
        IconButton(
          tooltip: AppTranslation.translate('تحديث البيانات'),
          onPressed: () => context.read<CustomersController>().loadCustomers(),
          icon: const Icon(Icons.refresh_rounded, size: 19),
        ),
        if (canCreate)
          FilledButton.icon(
            onPressed: _openAddCustomer,
            icon: const Icon(Icons.add_rounded, size: 17),
            label: const AppText('إضافة عميل'),
          ),
      ],
      statistics: CustomersStatistics(
        totalCustomers: customers.length,
        visibleCustomers: filteredCustomers.length,
      ),
      toolbar: KajQueryToolbar(
        controller: _queryController,
        hintText: 'البحث بالاسم أو الهاتف أو العنوان أو الملاحظات',
        sortBuilder: (context) => PopupMenuButton<String>(
          tooltip: 'الفرز',
          icon: const Icon(Icons.sort_rounded),
          onSelected: (field) {
            _queryController.setSorts([
              UnifiedSortRule(
                field: field,
                label: field == 'name' ? 'الاسم' : 'الأحدث',
                descending: field == 'created_at',
              ),
            ]);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'created_at', child: Text('الأحدث')),
            PopupMenuItem(value: 'name', child: Text('الاسم')),
          ],
        ),
      ),
      body: filteredCustomers.isEmpty
          ? AppEmpty(
              title: 'لا يوجد عملاء',
              message: hasSearch
                  ? 'جرّب تغيير كلمات البحث.'
                  : 'ابدأ بإضافة أول عميل إلى النظام.',
              icon: Icons.people_outline_rounded,
              action: canCreate && !hasSearch
                  ? FilledButton.icon(
                      onPressed: _openAddCustomer,
                      icon: const Icon(Icons.add_rounded, size: 17),
                      label: const AppText('إضافة عميل'),
                    )
                  : null,
            )
          : RefreshIndicator(
              onRefresh: context.read<CustomersController>().loadCustomers,
              child: GridView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(10),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 320,
                  mainAxisExtent: 176,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                ),
                itemCount: filteredCustomers.length,
                itemBuilder: (context, index) {
                  final customer = filteredCustomers[index];
                  return CustomerCard(
                    customer: customer,
                    onView: () => _showCustomerDetails(customer),
                    onEdit: () => _editCustomer(customer),
                    onDelete: () => _deleteCustomer(customer),
                  );
                },
              ),
            ),
    );
  }

  Future<void> _showCustomerDetails(CustomerModel customer) async {
    final summary = await const BusinessPartnerCardService().load(
      kind: 'customer',
      partnerId: customer.id,
    );
    if (!mounted) return;
    await showBusinessPartnerProfileDialog(
      context: context,
      title: 'بطاقة الشريك التجاري',
      accountingSectionTitle: 'الحسابات المحاسبية',
      paymentsSectionTitle: 'الدفعات',
      documentsSectionTitle: 'المستندات المرتبطة',
      partnerId: customer.id,
      partnerName: customer.name,
      partnerType: 'عميل',
      icon: Icons.person_outline_rounded,
      photoBase64: customer.photoBase64,
      summary: summary,
      identityFields: [
        if (context.read<AccessController>().canViewField(
          'customers',
          'nationalId',
          viewPermission: 'customers.view',
        ))
          BusinessPartnerProfileField('رقم الهوية', customer.nationalId),
        if (context.read<AccessController>().canViewField(
          'customers',
          'createdAt',
          viewPermission: 'customers.view',
        ))
          BusinessPartnerProfileField('تاريخ الإنشاء', customer.createdAt),
      ],
      contactFields: [
        if (context.read<AccessController>().canViewField(
          'customers',
          'phone',
          viewPermission: 'customers.view',
        ))
          BusinessPartnerProfileField(
            'الهاتف',
            customer.phone,
            icon: Icons.phone_outlined,
          ),
        if (context.read<AccessController>().canViewField(
          'customers',
          'address',
          viewPermission: 'customers.view',
        ))
          BusinessPartnerProfileField(
            'العنوان',
            customer.address,
            icon: Icons.location_on_outlined,
          ),
      ],
      notes: context.read<AccessController>().canViewField(
        'customers',
        'notes',
        viewPermission: 'customers.view',
      )
          ? customer.notes
          : null,
    );
  }

  Future<void> _openAddCustomer() async {
    await showAppModuleDialog(
      context: context,
      title: 'إضافة عميل',
      windowKey: 'customers:add',
      builder: (_) => const AddCustomerPage(),
    );
  }

  Future<void> _editCustomer(CustomerModel customer) async {
    if (!await PermissionAction.require(context, 'customers.update')) return;
    await showAppModuleDialog(
      context: context,
      title: 'تعديل عميل',
      windowKey: 'customers:edit:${customer.id}',
      builder: (_) => EditCustomerPage(customer: customer),
    );
  }

  Future<void> _deleteCustomer(CustomerModel customer) async {
    if (!await PermissionAction.require(context, 'customers.delete')) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: 'حذف العميل',
        content: AppText('هل أنت متأكد من حذف ${customer.name}؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const AppText('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const AppText('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<CustomersController>().deleteCustomer(customer.id);
  }
}
