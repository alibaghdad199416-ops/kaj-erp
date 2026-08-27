import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';
import 'package:quality_line_erp/core/filtering/unified_query.dart';
import 'package:quality_line_erp/core/filtering/unified_query_toolbar.dart';
import 'package:quality_line_erp/core/widgets/app_dialog.dart';
import 'package:quality_line_erp/core/widgets/app_empty.dart';
import 'package:quality_line_erp/core/widgets/app_entity_page.dart';
import 'package:quality_line_erp/core/widgets/app_module_dialog.dart';
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
  final UnifiedQueryController _queryController = UnifiedQueryController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) await context.read<CustomersController>().loadCustomers();
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  List<UnifiedSortCriterion<CustomerModel>> _sorts(UnifiedQueryState state) {
    return state.sorts.map((rule) {
      final direction = rule.descending
          ? UnifiedSortDirection.descending
          : UnifiedSortDirection.ascending;
      switch (rule.field) {
        case 'name':
          return UnifiedSortCriterion<CustomerModel>(
            key: rule.field,
            direction: direction,
            value: (customer) => customer.name.toLowerCase(),
          );
        case 'createdAt':
          return UnifiedSortCriterion<CustomerModel>(
            key: rule.field,
            direction: direction,
            value: (customer) =>
                customer.createdAtDate ?? DateTime.fromMillisecondsSinceEpoch(0),
          );
        default:
          return UnifiedSortCriterion<CustomerModel>(
            key: rule.field,
            direction: direction,
            value: (customer) => customer.name.toLowerCase(),
          );
      }
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final customers = context.watch<CustomersController>().customers;
    final canCreate = PermissionAction.allowed(context, 'customers.create');

    return AnimatedBuilder(
      animation: _queryController,
      builder: (context, _) {
        final state = _queryController.state;
        final filteredCustomers = UnifiedFilterEngine.apply<CustomerModel>(
          customers,
          criteria: UnifiedFilterCriteria(searchText: state.search),
          adapter: UnifiedFilterAdapter<CustomerModel>(
            searchableText: (customer) => <Object?>[
              customer.name,
              customer.phone,
              customer.address,
              customer.nationalId,
              customer.notes,
            ],
            date: (customer) => customer.createdAtDate,
          ),
          sorts: _sorts(state),
        );

        final sortOptions = <UnifiedQuerySortOption>[
          const UnifiedQuerySortOption(
            rule: UnifiedSortRule(field: 'createdAt', label: 'الأحدث', descending: true),
            icon: Icons.schedule_rounded,
          ),
          const UnifiedQuerySortOption(
            rule: UnifiedSortRule(field: 'name', label: 'الاسم'),
            icon: Icons.sort_by_alpha_rounded,
          ),
        ];

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
          toolbar: UnifiedQueryToolbar(
            controller: _queryController,
            searchHint: 'البحث بالاسم أو الهاتف أو العنوان أو الهوية',
            sorts: sortOptions,
          ),
          body: filteredCustomers.isEmpty
              ? AppEmpty(
                  title: 'لا يوجد عملاء',
                  message: state.search.trim().isEmpty
                      ? 'ابدأ بإضافة أول عميل إلى النظام.'
                      : 'جرّب تغيير كلمات البحث أو إزالة أحد شروط الفرز.',
                  icon: Icons.people_outline_rounded,
                  action: canCreate && state.search.trim().isEmpty
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
      },
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
