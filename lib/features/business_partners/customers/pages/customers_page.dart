import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/core/widgets/app_dialog.dart';
import 'package:quality_line_erp/core/widgets/app_empty.dart';
import 'package:quality_line_erp/core/widgets/app_entity_page.dart';
import 'package:quality_line_erp/core/widgets/app_module_dialog.dart';
import 'package:quality_line_erp/core/widgets/app_search.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:quality_line_erp/features/business_partners/customers/controllers/customers_controller.dart';
import 'package:quality_line_erp/features/business_partners/customers/models/customer_model.dart';
import 'package:quality_line_erp/features/business_partners/customers/widgets/customer_card.dart';
import 'package:quality_line_erp/features/business_partners/customers/widgets/customers_statistics.dart';
import 'package:quality_line_erp/features/business_partners/shared/data/business_partner_card_service.dart';
import 'package:quality_line_erp/features/business_partners/shared/data/partner_record_route.dart';
import 'package:quality_line_erp/features/business_partners/shared/widgets/business_partner_profile_dialog.dart';
import 'package:quality_line_erp/features/customer_service/models/opportunity_model.dart';
import 'package:quality_line_erp/features/customer_service/pages/add_opportunity_page.dart';
import 'package:quality_line_erp/features/maintenance/data/maintenance_repository.dart';
import 'package:quality_line_erp/features/maintenance/pages/maintenance_order_details_dialog.dart';
import 'package:quality_line_erp/features/sales/workflow/pages/order_details_dialog.dart';
import 'add_customer_page.dart';
import 'edit_customer_page.dart';

enum _CustomerSort { newest, name }

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key});

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';
  _CustomerSort _sort = _CustomerSort.newest;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) await context.read<CustomersController>().loadCustomers();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customers = context.watch<CustomersController>().customers;
    final canCreate = PermissionAction.allowed(context, 'customers.create');
    final query = _searchText.trim();
    final filteredCustomers =
        UnifiedFilterEngine.apply<CustomerModel>(
          customers,
          criteria: UnifiedFilterCriteria(searchText: query),
          adapter: UnifiedFilterAdapter<CustomerModel>(
            searchableText: (customer) => <Object?>[
              customer.id,
              customer.name,
              customer.phone,
              customer.address,
              customer.nationalId,
              customer.notes,
            ],
            date: (customer) => customer.createdAtDate,
          ),
        )..sort((a, b) {
          if (_sort == _CustomerSort.name) {
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          }
          final aDate = a.createdAtDate;
          final bDate = b.createdAtDate;
          if (aDate == null && bDate == null) return 0;
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          return bDate.compareTo(aDate);
        });

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
      toolbar: LayoutBuilder(
        builder: (context, constraints) {
          final search = AppSearch(
            controller: _searchController,
            hintText: AppTranslation.translate(
              'البحث بالاسم أو الهاتف أو العنوان',
            ),
            onChanged: (value) => setState(() => _searchText = value),
          );
          final sort = SegmentedButton<_CustomerSort>(
            segments: const [
              ButtonSegment(
                value: _CustomerSort.newest,
                label: AppText('الأحدث'),
                icon: Icon(Icons.schedule_rounded, size: 16),
              ),
              ButtonSegment(
                value: _CustomerSort.name,
                label: AppText('الاسم'),
                icon: Icon(Icons.sort_by_alpha_rounded, size: 16),
              ),
            ],
            selected: {_sort},
            showSelectedIcon: false,
            onSelectionChanged: (value) => setState(() => _sort = value.first),
          );
          if (constraints.maxWidth < 720) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [search, const SizedBox(height: 8), sort],
            );
          }
          return Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 8),
              sort,
            ],
          );
        },
      ),
      body: filteredCustomers.isEmpty
          ? AppEmpty(
              title: 'لا يوجد عملاء',
              message: query.isEmpty
                  ? 'ابدأ بإضافة أول عميل إلى النظام.'
                  : 'جرّب تغيير كلمات البحث.',
              icon: Icons.people_outline_rounded,
              action: canCreate && query.isEmpty
                  ? FilledButton.icon(
                      onPressed: _openAddCustomer,
                      icon: const Icon(Icons.add_rounded, size: 17),
                      label: const AppText('إضافة عميل'),
                    )
                  : null,
            )
          : RefreshIndicator(
              onRefresh: context.read<CustomersController>().loadCustomers,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const minimumCardWidth = 300.0;
                  const gap = 8.0;
                  final availableWidth = constraints.maxWidth - 12;
                  final columns =
                      ((availableWidth + gap) / (minimumCardWidth + gap))
                          .floor()
                          .clamp(1, 4);
                  return GridView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(6),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisExtent: 142,
                      mainAxisSpacing: gap,
                      crossAxisSpacing: gap,
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
      onOpenRecord: _openPartnerRecord,
      canOpenRecord: (record) {
        final destination = PartnerRecordRoute.resolve(record)?.destination;
        return destination == PartnerRecordDestination.opportunity ||
            destination == PartnerRecordDestination.maintenance ||
            destination == PartnerRecordDestination.salesOrder;
      },
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
      notes:
          context.read<AccessController>().canViewField(
            'customers',
            'notes',
            viewPermission: 'customers.view',
          )
          ? customer.notes
          : null,
    );
  }

  Future<void> _openPartnerRecord(Map<String, Object?> record) async {
    final route = PartnerRecordRoute.resolve(record);
    if (route == null) return;
    if (route.destination == PartnerRecordDestination.opportunity) {
      await showAppModuleDialog<void>(
        context: context,
        title: 'تفاصيل الفرصة',
        windowKey: 'opportunities:${route.id}',
        builder: (_) =>
            AddOpportunityPage(opportunity: OpportunityModel.fromMap(record)),
      );
      return;
    }
    if (route.destination == PartnerRecordDestination.maintenance) {
      final orders = await MaintenanceRepository().getOrders();
      final matches = orders.where((order) => order.id == route.id);
      if (!mounted || matches.isEmpty) return;
      await showAppModuleDialog<void>(
        context: context,
        title: 'تفاصيل أمر الصيانة',
        windowKey: 'maintenance:${route.id}',
        builder: (_) => MaintenanceOrderDetailsDialog(order: matches.first),
      );
      return;
    }
    if (route.destination == PartnerRecordDestination.salesOrder) {
      if (!mounted) return;
      await showAppModuleDialog<void>(
        context: context,
        title: 'تفاصيل أمر البيع',
        windowKey: 'sales-order:${route.id}',
        builder: (_) => OrderDetailsDialog(orderId: route.id, purchase: false),
      );
    }
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
    if (!mounted) return;
    await showAppModuleDialog(
      context: context,
      title: 'تعديل عميل',
      windowKey: 'customers:edit:${customer.id}',
      builder: (_) => EditCustomerPage(customer: customer),
    );
  }

  Future<void> _deleteCustomer(CustomerModel customer) async {
    if (!await PermissionAction.require(context, 'customers.delete')) return;
    if (!mounted) return;
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'تأكيد حذف العميل',
      message: 'هل تريد حذف هذا العميل؟ لا يمكن التراجع عن هذا الإجراء.',
      confirmLabel: 'حذف',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await context.read<CustomersController>().removeCustomer(customer.id);
  }
}
