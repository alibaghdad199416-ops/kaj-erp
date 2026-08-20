import 'dart:async';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/core/widgets/app_dialog.dart';
import 'package:quality_line_erp/core/widgets/app_empty.dart';
import 'package:quality_line_erp/core/widgets/app_entity_page.dart';
import 'package:quality_line_erp/core/widgets/app_loading.dart';
import 'package:quality_line_erp/core/widgets/app_search.dart';
import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';
import 'package:quality_line_erp/core/widgets/compact_metric_pill.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:quality_line_erp/features/business_partners/suppliers/controllers/suppliers_controller.dart';
import 'package:quality_line_erp/features/business_partners/suppliers/models/supplier_model.dart';
import 'package:quality_line_erp/features/business_partners/suppliers/widgets/supplier_card.dart';
import 'package:quality_line_erp/features/business_partners/shared/data/business_partner_card_service.dart';
import 'package:quality_line_erp/features/business_partners/shared/data/partner_record_route.dart';
import 'package:quality_line_erp/features/business_partners/shared/widgets/business_partner_profile_dialog.dart';
import 'package:quality_line_erp/features/sales/workflow/pages/order_details_dialog.dart';
import 'add_supplier_page.dart';

enum _SupplierFilter { all, active, inactive }

enum _SupplierSort { newest, name, highestBalance }

class SuppliersPage extends StatefulWidget {
  const SuppliersPage({super.key});

  @override
  State<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  _SupplierFilter _filter = _SupplierFilter.all;
  _SupplierSort _sort = _SupplierSort.newest;

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
    _searchController.dispose();
    super.dispose();
  }

  List<SupplierModel> _visible(List<SupplierModel> suppliers) {
    final statuses = switch (_filter) {
      _SupplierFilter.all => const <String>{},
      _SupplierFilter.active => const <String>{'active'},
      _SupplierFilter.inactive => const <String>{'inactive'},
    };
    final result = UnifiedFilterEngine.apply<SupplierModel>(
      suppliers,
      criteria: UnifiedFilterCriteria(
        searchText: _searchQuery,
        statuses: statuses,
      ),
      adapter: UnifiedFilterAdapter<SupplierModel>(
        searchableText: (supplier) => <Object?>[
          supplier.id,
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
    );

    switch (_sort) {
      case _SupplierSort.newest:
        result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _SupplierSort.name:
        result.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case _SupplierSort.highestBalance:
        result.sort((a, b) => b.openingBalance.compareTo(a.openingBalance));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SuppliersController>();
    final suppliers = controller.suppliers;
    final visible = _visible(suppliers);
    final canCreate = PermissionAction.allowed(context, 'suppliers.create');

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
      toolbar: LayoutBuilder(
        builder: (context, constraints) {
          final search = AppSearch(
            controller: _searchController,
            hintText: AppTranslation.translate(
              'البحث بالاسم أو الهاتف أو الشركة',
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          );
          final filters = SegmentedButton<_SupplierFilter>(
            segments: const [
              ButtonSegment(value: _SupplierFilter.all, label: AppText('الكل')),
              ButtonSegment(
                value: _SupplierFilter.active,
                label: AppText('نشط'),
              ),
              ButtonSegment(
                value: _SupplierFilter.inactive,
                label: AppText('غير نشط'),
              ),
            ],
            selected: {_filter},
            showSelectedIcon: false,
            onSelectionChanged: (value) =>
                setState(() => _filter = value.first),
          );
          final sort = PopupMenuButton<_SupplierSort>(
            tooltip: AppTranslation.translate('الترتيب'),
            initialValue: _sort,
            onSelected: (value) => setState(() => _sort = value),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _SupplierSort.newest,
                child: AppText('الأحدث أولاً'),
              ),
              PopupMenuItem(
                value: _SupplierSort.name,
                child: AppText('حسب الاسم'),
              ),
              PopupMenuItem(
                value: _SupplierSort.highestBalance,
                child: AppText('أعلى رصيد'),
              ),
            ],
            child: ActionChip(
              avatar: const Icon(Icons.sort_rounded, size: 17),
              label: AppText(_sortLabel),
              onPressed: null,
            ),
          );
          final controls = Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [filters, sort],
          );
          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [search, const SizedBox(height: 8), controls],
            );
          }
          return Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 8),
              controls,
            ],
          );
        },
      ),
      body: _buildBody(controller, suppliers, visible, canCreate),
    );
  }

  String get _sortLabel => switch (_sort) {
    _SupplierSort.newest => 'الأحدث أولاً',
    _SupplierSort.name => 'حسب الاسم',
    _SupplierSort.highestBalance => 'أعلى رصيد',
  };

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
      child: LayoutBuilder(
        builder: (context, constraints) {
          const minimumCardWidth = 300.0;
          const gap = 8.0;
          final availableWidth = constraints.maxWidth - 12;
          final columns = ((availableWidth + gap) / (minimumCardWidth + gap))
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
      onOpenRecord: _openPartnerRecord,
      canOpenRecord: (record) =>
          PartnerRecordRoute.resolve(record)?.destination ==
          PartnerRecordDestination.purchaseOrder,
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
            supplier.isActive
                ? AppTranslation.translate('فعال')
                : AppTranslation.translate('متوقف'),
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

  Future<void> _openPartnerRecord(Map<String, Object?> record) async {
    final route = PartnerRecordRoute.resolve(record);
    if (route?.destination != PartnerRecordDestination.purchaseOrder ||
        !mounted) {
      return;
    }
    await showAppWorkspaceDialogBuilder<void>(
      context: context,
      builder: (_) => OrderDetailsDialog(orderId: route!.id, purchase: true),
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
    if (changed != null && mounted) {
      await context.read<SuppliersController>().loadSuppliers();
    }
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
    if (changed != null && mounted) {
      await context.read<SuppliersController>().loadSuppliers();
    }
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < items.length; index++) ...[
          CompactMetricPill(
            icon: items[index].icon,
            label: items[index].label,
            value: items[index].value,
          ),
          if (index != items.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}
