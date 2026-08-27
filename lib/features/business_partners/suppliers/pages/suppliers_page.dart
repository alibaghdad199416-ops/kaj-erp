import 'dart:async';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';
import 'package:quality_line_erp/core/filtering/unified_query.dart';
import 'package:quality_line_erp/core/filtering/unified_query_toolbar.dart';
import 'package:quality_line_erp/core/widgets/app_dialog.dart';
import 'package:quality_line_erp/core/widgets/app_empty.dart';
import 'package:quality_line_erp/core/widgets/app_entity_page.dart';
import 'package:quality_line_erp/core/widgets/app_loading.dart';
import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';
import 'package:quality_line_erp/core/widgets/compact_metric_pill.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:quality_line_erp/features/business_partners/suppliers/controllers/suppliers_controller.dart';
import 'package:quality_line_erp/features/business_partners/suppliers/models/supplier_model.dart';
import 'package:quality_line_erp/features/business_partners/suppliers/widgets/supplier_card.dart';
import 'package:quality_line_erp/features/business_partners/shared/data/business_partner_card_service.dart';
import 'package:quality_line_erp/features/business_partners/shared/widgets/business_partner_profile_dialog.dart';
import 'add_supplier_page.dart';

class SuppliersPage extends StatefulWidget {
  const SuppliersPage({super.key});

  @override
  State<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage> {
  final UnifiedQueryController _queryController = UnifiedQueryController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted)
        unawaited(context.read<SuppliersController>().loadSuppliers());
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  List<UnifiedSortCriterion<SupplierModel>> _sorts(UnifiedQueryState state) {
    return state.sorts
        .map((rule) {
          final direction = rule.descending
              ? UnifiedSortDirection.descending
              : UnifiedSortDirection.ascending;
          switch (rule.field) {
            case 'name':
              return UnifiedSortCriterion<SupplierModel>(
                key: rule.field,
                direction: direction,
                value: (supplier) => supplier.name.toLowerCase(),
              );
            case 'balance':
              return UnifiedSortCriterion<SupplierModel>(
                key: rule.field,
                direction: direction,
                value: (supplier) => supplier.openingBalance,
              );
            case 'createdAt':
              return UnifiedSortCriterion<SupplierModel>(
                key: rule.field,
                direction: direction,
                value: (supplier) => supplier.createdAt,
              );
            default:
              return UnifiedSortCriterion<SupplierModel>(
                key: rule.field,
                direction: direction,
                value: (supplier) => supplier.name.toLowerCase(),
              );
          }
        })
        .toList(growable: false);
  }

  String _statusLabel(bool active) => active ? 'نشط' : 'غير نشط';

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SuppliersController>();
    final suppliers = controller.suppliers;
    final canCreate = PermissionAction.allowed(context, 'suppliers.create');

    return AnimatedBuilder(
      animation: _queryController,
      builder: (context, _) {
        final state = _queryController.state;
        final statusToken = state.filters
            .where((item) => item.key == 'status')
            .firstOrNull;
        final status = statusToken?.value.toString();
        final visible = UnifiedFilterEngine.apply<SupplierModel>(
          suppliers,
          criteria: UnifiedFilterCriteria(
            searchText: state.search,
            statuses: status == null ? const <String>{} : <String>{status},
          ),
          adapter: UnifiedFilterAdapter<SupplierModel>(
            searchableText: (supplier) => <Object?>[
              supplier.name,
              supplier.phone,
              supplier.alternativePhone,
              supplier.companyName,
              supplier.address,
              supplier.taxNumber,
              supplier.notes,
            ],
            status: (supplier) => supplier.isActive ? 'active' : 'inactive',
            currency: (supplier) => supplier.currency,
            date: (supplier) => supplier.createdAt,
          ),
          sorts: _sorts(state),
        );

        final sortOptions = <UnifiedQuerySortOption>[
          const UnifiedQuerySortOption(
            rule: UnifiedSortRule(
              field: 'createdAt',
              label: 'الأحدث',
              descending: true,
            ),
            icon: Icons.schedule_rounded,
          ),
          const UnifiedQuerySortOption(
            rule: UnifiedSortRule(field: 'name', label: 'الاسم'),
            icon: Icons.sort_by_alpha_rounded,
          ),
          const UnifiedQuerySortOption(
            rule: UnifiedSortRule(
              field: 'balance',
              label: 'الرصيد',
              descending: true,
            ),
            icon: Icons.account_balance_wallet_outlined,
          ),
        ];

        return AppEntityPage(
          hideHeader: true,
          title: 'إدارة الموردين',
          subtitle: 'إدارة بيانات الموردين وأرصدتهم وحالة تعاملهم.',
          actions: [
            IconButton(
              tooltip: AppTranslation.translate('تحديث البيانات'),
              onPressed: controller.isLoading ? null : controller.loadSuppliers,
              icon: const Icon(Icons.refresh_rounded, size: 19),
            ),
            if (canCreate)
              FilledButton.icon(
                onPressed: _openAdd,
                icon: const Icon(Icons.add_rounded, size: 17),
                label: const AppText('إضافة مورد'),
              ),
          ],
          statistics: _SupplierStatistics(controller: controller),
          toolbar: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UnifiedQueryToolbar(
                controller: _queryController,
                searchHint: 'البحث بالاسم أو الهاتف أو الشركة أو الرقم الضريبي',
                sorts: sortOptions,
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 560;
                  final filter = DropdownButtonFormField<String>(
                    value: status,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'الحالة',
                      prefixIcon: Icon(Icons.flag_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'active', child: Text('نشط')),
                      DropdownMenuItem(
                        value: 'inactive',
                        child: Text('غير نشط'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        _queryController.removeFilterKey('status');
                      } else {
                        _queryController.addFilter(
                          UnifiedFilterToken(
                            key: 'status',
                            label: 'الحالة',
                            value: value,
                            valueLabel: _statusLabel(value == 'active'),
                          ),
                        );
                      }
                    },
                  );
                  final clearStatus = TextButton.icon(
                    onPressed: status == null
                        ? null
                        : () => _queryController.removeFilterKey('status'),
                    icon: const Icon(Icons.filter_alt_off_outlined),
                    label: const AppText('مسح الحالة'),
                  );
                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [filter, clearStatus],
                    );
                  }
                  return Row(
                    children: [
                      SizedBox(width: 220, child: filter),
                      clearStatus,
                    ],
                  );
                },
              ),
            ],
          ),
          body: _buildBody(controller, suppliers, visible, canCreate),
        );
      },
    );
  }

  Widget _buildBody(
    SuppliersController controller,
    List<SupplierModel> all,
    List<SupplierModel> visible,
    bool canCreate,
  ) {
    if (controller.isLoading && all.isEmpty) return const AppLoading();
    if (controller.errorMessage != null && all.isEmpty) {
      return AppEmpty(
        title: 'تعذر تحميل الموردين',
        message: controller.errorMessage,
        icon: Icons.cloud_off_outlined,
        action: FilledButton.icon(
          onPressed: controller.loadSuppliers,
          icon: const Icon(Icons.refresh_rounded, size: 17),
          label: const AppText('إعادة المحاولة'),
        ),
      );
    }
    if (visible.isEmpty) {
      return AppEmpty(
        title: 'لا يوجد موردون مطابقون',
        message: all.isEmpty
            ? 'ابدأ بإضافة أول مورد إلى النظام.'
            : 'جرّب تغيير البحث أو عوامل التصفية.',
        icon: Icons.local_shipping_outlined,
        action: canCreate && all.isEmpty
            ? FilledButton.icon(
                onPressed: _openAdd,
                icon: const Icon(Icons.add_rounded, size: 17),
                label: const AppText('إضافة مورد'),
              )
            : null,
      );
    }
    return RefreshIndicator(
      onRefresh: controller.loadSuppliers,
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(10),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 320,
          mainAxisExtent: 126,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
        ),
        itemCount: visible.length,
        itemBuilder: (context, index) {
          final supplier = visible[index];
          return SupplierCard(
            supplier: supplier,
            onView: () => _showSupplierDetails(supplier),
            onEdit: () => _openEdit(supplier),
            onDelete: () => _delete(supplier),
            onToggleStatus: () => _toggle(supplier),
          );
        },
      ),
    );
  }

  Future<void> _showSupplierDetails(SupplierModel supplier) async {
    final summary = await const BusinessPartnerCardService().load(
      kind: 'supplier',
      partnerId: supplier.id,
    );
    if (!mounted) return;
    await showBusinessPartnerProfileDialog(
      context: context,
      title: 'بطاقة الشريك التجاري',
      accountingSectionTitle: 'الحسابات المحاسبية',
      paymentsSectionTitle: 'الدفعات',
      documentsSectionTitle: 'المستندات المرتبطة',
      partnerId: supplier.id,
      partnerName: supplier.name,
      partnerType: 'مورد',
      icon: Icons.local_shipping_outlined,
      photoBase64: supplier.photoBase64,
      summary: summary,
      identityFields: [
        if (context.read<AccessController>().canViewField(
          'suppliers',
          'companyName',
          viewPermission: 'suppliers.view',
        ))
          BusinessPartnerProfileField('اسم الشركة', supplier.companyName),
        if (context.read<AccessController>().canViewField(
          'suppliers',
          'taxNumber',
          viewPermission: 'suppliers.view',
        ))
          BusinessPartnerProfileField('الرقم الضريبي', supplier.taxNumber),
        if (context.read<AccessController>().canViewField(
          'suppliers',
          'isActive',
          viewPermission: 'suppliers.view',
        ))
          BusinessPartnerProfileField(
            'الحالة',
            supplier.isActive ? 'فعال' : 'متوقف',
          ),
        if (context.read<AccessController>().canViewField(
          'suppliers',
          'createdAt',
          viewPermission: 'suppliers.view',
        ))
          BusinessPartnerProfileField('تاريخ الإنشاء', supplier.createdAt),
        if (supplier.updatedAt != null &&
            context.read<AccessController>().canViewField(
              'suppliers',
              'updatedAt',
              viewPermission: 'suppliers.view',
            ))
          BusinessPartnerProfileField('تاريخ التحديث', supplier.updatedAt),
      ],
      contactFields: [
        if (context.read<AccessController>().canViewField(
          'suppliers',
          'phone',
          viewPermission: 'suppliers.view',
        ))
          BusinessPartnerProfileField(
            'الهاتف',
            supplier.phone,
            icon: Icons.phone_outlined,
          ),
        if (context.read<AccessController>().canViewField(
          'suppliers',
          'alternativePhone',
          viewPermission: 'suppliers.view',
        ))
          BusinessPartnerProfileField(
            'هاتف بديل',
            supplier.alternativePhone,
            icon: Icons.phone_in_talk_outlined,
          ),
        if (context.read<AccessController>().canViewField(
          'suppliers',
          'address',
          viewPermission: 'suppliers.view',
        ))
          BusinessPartnerProfileField(
            'العنوان',
            supplier.address,
            icon: Icons.location_on_outlined,
          ),
        if (context.read<AccessController>().canViewField(
          'suppliers',
          'currency',
          viewPermission: 'suppliers.view',
        ))
          BusinessPartnerProfileField('العملة', supplier.currency),
      ],
      notes:
          context.read<AccessController>().canViewField(
            'suppliers',
            'notes',
            viewPermission: 'suppliers.view',
          )
          ? supplier.notes
          : null,
    );
  }

  Future<void> _openAdd() async {
    if (!await PermissionAction.require(context, 'suppliers.create')) return;
    if (!mounted) return;
    final changed = await showAppWorkspaceDialog<SupplierModel>(
      context: context,
      title: 'إضافة مورد',
      windowKey: 'suppliers:add',
      child: const AddSupplierPage(),
    );
    if (changed != null && mounted)
      await context.read<SuppliersController>().loadSuppliers();
  }

  Future<void> _openEdit(SupplierModel supplier) async {
    if (!await PermissionAction.require(context, 'suppliers.update')) return;
    if (!mounted) return;
    final changed = await showAppWorkspaceDialog<SupplierModel>(
      context: context,
      title: 'تعديل مورد',
      windowKey: 'suppliers:edit:${supplier.id}',
      child: AddSupplierPage(supplier: supplier),
    );
    if (changed != null && mounted)
      await context.read<SuppliersController>().loadSuppliers();
  }

  Future<void> _toggle(SupplierModel supplier) async {
    if (!await PermissionAction.require(context, 'suppliers.update')) return;
    if (!mounted) return;
    final activate = !supplier.isActive;
    final confirmed = await showAppConfirmDialog(
      context,
      title: activate ? 'تفعيل المورد' : 'تعطيل المورد',
      message: activate
          ? 'هل تريد تفعيل هذا المورد؟'
          : 'هل تريد تعطيل هذا المورد؟',
      confirmLabel: activate ? 'تفعيل' : 'تعطيل',
    );
    if (!confirmed || !mounted) return;
    try {
      await context.read<SuppliersController>().toggleSupplierStatus(supplier);
    } catch (_) {
      if (!mounted) return;
      _showError(
        context.read<SuppliersController>().errorMessage ??
            'تعذر تحديث حالة المورد.',
      );
    }
  }

  Future<void> _delete(SupplierModel supplier) async {
    if (!await PermissionAction.require(context, 'suppliers.delete')) return;
    if (!mounted) return;
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'تأكيد حذف المورد',
      message: 'هل تريد حذف هذا المورد؟ لا يمكن التراجع عن هذا الإجراء.',
      confirmLabel: 'حذف',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await context.read<SuppliersController>().deleteSupplier(supplier.id);
    } catch (_) {
      if (!mounted) return;
      _showError(
        context.read<SuppliersController>().errorMessage ?? 'تعذر حذف المورد.',
      );
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: AppText(message)));
  }
}

class _SupplierStatistics extends StatelessWidget {
  const _SupplierStatistics({required this.controller});
  final SuppliersController controller;

  @override
  Widget build(BuildContext context) {
    final ar = context.l10n.isArabic;
    String t(String arText, String enText) => ar ? arText : enText;
    final items = <({IconData icon, String label, String value})>[
      (
        icon: Icons.local_shipping_outlined,
        label: t('إجمالي الموردين', 'Total suppliers'),
        value: '${controller.totalSuppliers}',
      ),
      (
        icon: Icons.check_circle_outline_rounded,
        label: t('الموردون النشطون', 'Active suppliers'),
        value: '${controller.activeSuppliers}',
      ),
      (
        icon: Icons.pause_circle_outline_rounded,
        label: t('غير النشطين', 'Inactive suppliers'),
        value: '${controller.inactiveSuppliers}',
      ),
      (
        icon: Icons.attach_money_rounded,
        label: t('الرصيد بالدولار', 'USD balance'),
        value: controller.totalOpeningBalanceUsd.toStringAsFixed(2),
      ),
      (
        icon: Icons.account_balance_wallet_outlined,
        label: t('الرصيد بالدينار', 'IQD balance'),
        value: controller.totalOpeningBalanceIqd.toStringAsFixed(0),
      ),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in items)
          CompactMetricPill(
            icon: item.icon,
            label: item.label,
            value: item.value,
          ),
      ],
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
