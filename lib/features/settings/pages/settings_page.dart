import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:quality_line_erp/core/widgets/app_dialog.dart';
import 'package:quality_line_erp/core/widgets/app_back_button.dart';
import 'package:quality_line_erp/core/widgets/app_module_dialog.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/preferences/app_preferences_controller.dart';
import 'package:quality_line_erp/design_system/kaj_admin_stage8_components.dart';
import 'package:quality_line_erp/core/utils/thousands_input_formatter.dart';

import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:quality_line_erp/features/settings/access/models/permission_codes.dart';
import 'package:quality_line_erp/features/settings/controllers/settings_controller.dart';
import 'package:quality_line_erp/features/settings/models/branch_model.dart';
import 'package:quality_line_erp/features/settings/models/company_settings_model.dart';
import 'package:quality_line_erp/features/settings/models/currency_model.dart';
import 'package:quality_line_erp/core/widgets/app_responsive.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<SettingsController>().loadSettings();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = context.l10n.isArabic;
    final sections = <({String ar, String en, IconData icon})>[
      (ar: 'بيانات الشركة', en: 'Company', icon: Icons.business_outlined),
      (ar: 'الفروع', en: 'Branches', icon: Icons.store_outlined),
      (ar: 'العملات', en: 'Currencies', icon: Icons.currency_exchange),
      (ar: 'النسخ الاحتياطي', en: 'Backups', icon: Icons.backup_outlined),
    ];

    final content = Consumer<SettingsController>(
      builder: (context, controller, _) {
        if (controller.isLoading && controller.branches.isEmpty) {
          return KajAdminState(
            kind: KajAdminStateKind.loading,
            title: isArabic ? 'جاري تحميل الإعدادات' : 'Loading settings',
            message: isArabic
                ? 'تتم مزامنة بيانات الشركة والفروع والعملات والنسخ الاحتياطية.'
                : 'Synchronizing company, branch, currency and backup configuration.',
          );
        }
        return Column(
          key: const ValueKey('system-model-full-height-workspace'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              key: const ValueKey('system-model-horizontal-sections'),
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: sections.length,
                separatorBuilder: (_, _) => const SizedBox(width: 7),
                itemBuilder: (context, index) {
                  final section = sections[index];
                  final permissionField = const <String>[
                    'companyProfile',
                    'branches',
                    'currencies',
                    'backup',
                  ][index];
                  return FieldPermissionVisibility(
                    resource: 'settings',
                    field: permissionField,
                    child: AnimatedBuilder(
                      animation: _tabController,
                      builder: (context, _) => ChoiceChip(
                        selected: _tabController.index == index,
                        onSelected: (_) => _tabController.animateTo(index),
                        avatar: Icon(section.icon, size: 17),
                        label: AppText(isArabic ? section.ar : section.en),
                        visualDensity: const VisualDensity(
                          horizontal: -2,
                          vertical: -3,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                key: const ValueKey('system-model-active-section-viewport'),
                controller: _tabController,
                children: [
                  FieldPermissionVisibility(
                    resource: 'settings',
                    field: 'companyProfile',
                    child: _CompanyTab(controller: controller),
                  ),
                  FieldPermissionVisibility(
                    resource: 'settings',
                    field: 'branches',
                    child: _BranchesTab(controller: controller),
                  ),
                  FieldPermissionVisibility(
                    resource: 'settings',
                    field: 'currencies',
                    child: _CurrenciesTab(controller: controller),
                  ),
                  FieldPermissionVisibility(
                    resource: 'settings',
                    field: 'backup',
                    child: _BackupsTab(controller: controller),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );

    if (widget.embedded) return content;
    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(),
          title: const AppText('الإعدادات العامة'),
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: content,
        ),
      ),
    );
  }
}

class _CompanyTab extends StatefulWidget {
  const _CompanyTab({required this.controller});
  final SettingsController controller;

  @override
  State<_CompanyTab> createState() => _CompanyTabState();
}

class _CompanyTabState extends State<_CompanyTab> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _nameEn = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _tax = TextEditingController();
  String _currency = 'USD';
  String _language = 'en';
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _fill(widget.controller.company);
      _initialized = true;
    }
  }

  void _fill(CompanySettingsModel model) {
    _name.text = model.companyName;
    _nameEn.text = model.companyNameEn;
    _phone.text = model.phone;
    _email.text = model.email;
    _address.text = model.address;
    _tax.text = model.taxNumber;
    _currency = model.defaultCurrency;
    _language = model.language == 'ar' ? 'ar' : 'en';
  }

  @override
  void dispose() {
    _name.dispose();
    _nameEn.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _tax.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    try {
      await widget.controller.saveCompany(
        CompanySettingsModel(
          companyName: _name.text.trim(),
          companyNameEn: _nameEn.text.trim(),
          phone: _phone.text.trim(),
          email: _email.text.trim(),
          address: _address.text.trim(),
          taxNumber: _tax.text.trim(),
          defaultCurrency: _currency,
          language: _language,
        ),
      );
      if (mounted) {
        await context.read<AppPreferencesController>().setLocale(
          Locale(_language),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AppText(widget.controller.errorMessage ?? 'تعذر الحفظ'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = context.watch<AccessController>();
    final canSave =
        access.canEditField(
          'settings',
          'companyProfile',
          viewPermission: PermissionCodes.settingsView,
        ) ||
        access.canEditField(
          'settings',
          'financialDefaults',
          viewPermission: PermissionCodes.settingsView,
        ) ||
        access.canEditField(
          'settings',
          'language',
          viewPermission: PermissionCodes.settingsView,
        );
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final compact = constraints.maxWidth < 760;
        final fieldWidth = compact
            ? constraints.maxWidth
            : (constraints.maxWidth - gap) / 2;

        Widget sized(Widget child) => SizedBox(width: fieldWidth, child: child);

        return SingleChildScrollView(
          key: const ValueKey('settings-company-full-page-scroll'),
          padding: const EdgeInsets.fromLTRB(2, 2, 2, 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight > 14
                  ? constraints.maxHeight - 14
                  : 0.0,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Padding(
                padding: EdgeInsets.all(compact ? 14 : 18),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: .08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.business_outlined,
                              size: 19,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AppText(
                                  context.l10n.isArabic
                                      ? 'هوية الشركة والإعدادات الافتراضية'
                                      : 'Company identity and defaults',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 2),
                                AppText(
                                  context.l10n.isArabic
                                      ? 'بيانات موحدة للطباعة والعملات واللغة.'
                                      : 'Shared identity, currency, print and language defaults.',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilledButton.icon(
                            onPressed: widget.controller.isLoading || !canSave
                                ? null
                                : _save,
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              minimumSize: const Size(0, 38),
                            ),
                            icon: const Icon(Icons.save_outlined, size: 18),
                            label: AppText(
                              context.l10n.isArabic ? 'حفظ' : 'Save',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: gap,
                        runSpacing: 12,
                        children: [
                          sized(
                            _field(
                              _name,
                              'اسم الشركة بالعربية',
                              required: true,
                            ),
                          ),
                          sized(_field(_nameEn, 'اسم الشركة بالإنجليزية')),
                          sized(_field(_phone, 'الهاتف')),
                          sized(_field(_email, 'البريد الإلكتروني')),
                          sized(_field(_address, 'العنوان')),
                          sized(_field(_tax, 'الرقم الضريبي')),
                          sized(
                            FieldPermissionControl(
                              resource: 'settings',
                              field: 'financialDefaults',
                              viewPermission: 'settings.view',
                              writePermission: 'settings.view',
                              child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: _currency,
                                decoration: InputDecoration(
                                  labelText: AppTranslation.translate(
                                    'العملة الافتراضية',
                                  ),
                                  border: const OutlineInputBorder(),
                                ),
                                items: widget.controller.currencies
                                    .where((e) => e.isActive)
                                    .map(
                                      (e) => DropdownMenuItem(
                                        value: e.code,
                                        child: AppText(
                                          '${e.name} (${e.code})',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) =>
                                    setState(() => _currency = value ?? 'USD'),
                              ),
                            ),
                          ),
                          sized(
                            FieldPermissionControl(
                              resource: 'settings',
                              field: 'language',
                              viewPermission: 'settings.view',
                              writePermission: 'settings.view',
                              child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: _language,
                                decoration: InputDecoration(
                                  labelText: AppTranslation.translate(
                                    'لغة النظام',
                                  ),
                                  border: const OutlineInputBorder(),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'ar',
                                    child: AppText('العربية'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'en',
                                    child: AppText('English'),
                                  ),
                                ],
                                onChanged: (value) =>
                                    setState(() => _language = value ?? 'en'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = false,
  }) {
    return FieldPermissionControl(
      resource: 'settings',
      field: 'companyProfile',
      viewPermission: PermissionCodes.settingsView,
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: AppTranslation.translate(label),
          border: const OutlineInputBorder(),
        ),
        validator: required
            ? (value) => value == null || value.trim().isEmpty
                  ? AppTranslation.translate('هذا الحقل مطلوب')
                  : null
            : null,
      ),
    );
  }
}

class _BranchesTab extends StatelessWidget {
  const _BranchesTab({required this.controller});
  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    final canEdit = context.select<AccessController, bool>(
      (access) => access.canEditField(
        'settings',
        'branches',
        viewPermission: PermissionCodes.settingsView,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        const minCardWidth = 300.0;
        final columns = ((constraints.maxWidth + gap) / (minCardWidth + gap))
            .floor()
            .clamp(1, 4);
        final activeCount = controller.branches.where((b) => b.isActive).length;

        Widget branchCard(BranchModel branch) {
          final scheme = Theme.of(context).colorScheme;
          return Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        branch.isMain
                            ? Icons.star_rounded
                            : Icons.store_outlined,
                        size: 18,
                        color: branch.isMain
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: AppText(
                          branch.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        tooltip: context.l10n.isArabic
                            ? 'تعديل الفرع'
                            : 'Edit branch',
                        visualDensity: VisualDensity.compact,
                        onPressed: canEdit
                            ? () => _showBranchDialog(context, branch: branch)
                            : null,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                      ),
                      IconButton(
                        tooltip: context.l10n.isArabic
                            ? 'حذف الفرع'
                            : 'Delete branch',
                        visualDensity: VisualDensity.compact,
                        onPressed: !canEdit || branch.isMain
                            ? null
                            : () => _deleteBranch(context, branch),
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  AppText(
                    branch.code,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Expanded(
                    child: AppText(
                      branch.address.trim().isEmpty
                          ? (context.l10n.isArabic
                                ? 'بدون عنوان'
                                : 'No address')
                          : branch.address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: branch.isActive
                              ? Colors.green.withValues(alpha: .08)
                              : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: AppText(
                          branch.isActive
                              ? (context.l10n.isArabic ? 'نشط' : 'Active')
                              : (context.l10n.isArabic
                                    ? 'غير نشط'
                                    : 'Inactive'),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (branch.isMain) ...[
                        const SizedBox(width: 6),
                        AppText(
                          context.l10n.isArabic ? 'رئيسي' : 'Main',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );
        }

        return CustomScrollView(
          key: const ValueKey('settings-branches-full-page-scroll'),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(2, 2, 2, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          AppText(
                            context.l10n.isArabic ? 'الفروع' : 'Branches',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: AppText(
                              context.l10n.isArabic
                                  ? '${controller.branches.length} إجمالي'
                                  : '${controller.branches.length} total',
                            ),
                          ),
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: AppText(
                              context.l10n.isArabic
                                  ? '$activeCount نشط'
                                  : '$activeCount active',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: canEdit
                          ? () => _showBranchDialog(context)
                          : null,
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        minimumSize: const Size(0, 38),
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: AppText(
                        context.l10n.isArabic ? 'إضافة فرع' : 'Add branch',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (controller.branches.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: AppText(
                    context.l10n.isArabic
                        ? 'لا توجد فروع معرفة.'
                        : 'No branches have been defined.',
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: gap,
                    mainAxisSpacing: gap,
                    mainAxisExtent: 132,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => branchCard(controller.branches[index]),
                    childCount: controller.branches.length,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _deleteBranch(BuildContext context, BranchModel branch) async {
    try {
      await controller.deleteBranch(branch.id);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: AppText(controller.errorMessage ?? 'تعذر الحذف')),
        );
      }
    }
  }

  Future<void> _showBranchDialog(
    BuildContext context, {
    BranchModel? branch,
  }) async {
    final name = TextEditingController(text: branch?.name ?? '');
    final code = TextEditingController(text: branch?.code ?? '');
    final phone = TextEditingController(text: branch?.phone ?? '');
    final address = TextEditingController(text: branch?.address ?? '');
    var isMain = branch?.isMain ?? false;
    var isActive = branch?.isActive ?? true;
    await showAppModuleDialog<void>(
      context: context,
      title: branch == null ? 'إضافة فرع' : 'تعديل الفرع',
      windowKey: branch == null
          ? 'settings:branch:add'
          : 'settings:branch:${branch.id}',
      maxWidth: 560,
      maxHeight: 560,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: AppText(branch == null ? 'إضافة فرع' : 'تعديل الفرع'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: InputDecoration(
                      labelText: AppTranslation.translate('اسم الفرع'),
                    ),
                  ),
                  TextField(
                    controller: code,
                    decoration: InputDecoration(
                      labelText: AppTranslation.translate('رمز الفرع'),
                    ),
                  ),
                  TextField(
                    controller: phone,
                    decoration: InputDecoration(
                      labelText: AppTranslation.translate('الهاتف'),
                    ),
                  ),
                  TextField(
                    controller: address,
                    decoration: InputDecoration(
                      labelText: AppTranslation.translate('العنوان'),
                    ),
                  ),
                  SwitchListTile(
                    value: isMain,
                    onChanged: (v) => setState(() => isMain = v),
                    title: const AppText('فرع رئيسي'),
                  ),
                  SwitchListTile(
                    value: isActive,
                    onChanged: (v) => setState(() => isActive = v),
                    title: const AppText('نشط'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const AppText('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                if (name.text.trim().isEmpty || code.text.trim().isEmpty) {
                  return;
                }
                await controller.saveBranch(
                  BranchModel(
                    id: branch?.id ?? const Uuid().v4(),
                    name: name.text.trim(),
                    code: code.text.trim().toUpperCase(),
                    phone: phone.text.trim(),
                    address: address.text.trim(),
                    isMain: isMain,
                    isActive: isActive,
                    createdAt: branch?.createdAt ?? DateTime.now(),
                    updatedAt: branch == null ? null : DateTime.now(),
                  ),
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const AppText('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrenciesTab extends StatelessWidget {
  const _CurrenciesTab({required this.controller});
  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    final canEdit = context.select<AccessController, bool>(
      (access) => access.canEditField(
        'settings',
        'currencies',
        viewPermission: PermissionCodes.settingsView,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        const minCardWidth = 280.0;
        final columns = ((constraints.maxWidth + gap) / (minCardWidth + gap))
            .floor()
            .clamp(1, 4);
        final activeCount = controller.currencies
            .where((c) => c.isActive)
            .length;

        Widget currencyCard(CurrencyModel currency) {
          final scheme = Theme.of(context).colorScheme;
          return Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: scheme.primary.withValues(alpha: .08),
                        child: AppText(
                          currency.symbol,
                          style: TextStyle(
                            color: scheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: AppText(
                          '${currency.name} (${currency.code})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        tooltip: context.l10n.isArabic
                            ? 'تعديل العملة'
                            : 'Edit currency',
                        visualDensity: VisualDensity.compact,
                        onPressed: canEdit
                            ? () => _showCurrencyDialog(
                                context,
                                currency: currency,
                              )
                            : null,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                      ),
                      IconButton(
                        tooltip: context.l10n.isArabic
                            ? 'حذف العملة'
                            : 'Delete currency',
                        visualDensity: VisualDensity.compact,
                        onPressed: !canEdit || currency.isBase
                            ? null
                            : () => _deleteCurrency(context, currency),
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Expanded(
                        child: AppText(
                          context.l10n.isArabic
                              ? 'سعر الصرف: ${currency.exchangeRate}'
                              : 'Exchange rate: ${currency.exchangeRate}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                      if (currency.isBase)
                        Chip(
                          visualDensity: const VisualDensity(
                            horizontal: -3,
                            vertical: -3,
                          ),
                          label: AppText(
                            context.l10n.isArabic ? 'الأساسية' : 'Base',
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: currency.isActive
                            ? Colors.green.withValues(alpha: .08)
                            : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: AppText(
                        currency.isActive
                            ? (context.l10n.isArabic ? 'نشطة' : 'Active')
                            : (context.l10n.isArabic ? 'غير نشطة' : 'Inactive'),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return CustomScrollView(
          key: const ValueKey('settings-currencies-full-page-scroll'),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(2, 2, 2, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          AppText(
                            context.l10n.isArabic ? 'العملات' : 'Currencies',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: AppText(
                              context.l10n.isArabic
                                  ? '${controller.currencies.length} إجمالي'
                                  : '${controller.currencies.length} total',
                            ),
                          ),
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: AppText(
                              context.l10n.isArabic
                                  ? '$activeCount نشطة'
                                  : '$activeCount active',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: canEdit
                          ? () => _showCurrencyDialog(context)
                          : null,
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        minimumSize: const Size(0, 38),
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: AppText(
                        context.l10n.isArabic ? 'إضافة عملة' : 'Add currency',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (controller.currencies.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: AppText(
                    context.l10n.isArabic
                        ? 'لا توجد عملات معرفة.'
                        : 'No currencies have been defined.',
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: gap,
                    mainAxisSpacing: gap,
                    mainAxisExtent: 118,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) =>
                        currencyCard(controller.currencies[index]),
                    childCount: controller.currencies.length,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _deleteCurrency(
    BuildContext context,
    CurrencyModel currency,
  ) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'حذف العملة',
      message: 'هل تريد حذف عملة ${currency.name}؟',
      confirmLabel: 'حذف',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await controller.deleteCurrency(currency.code);
  }

  Future<void> _showCurrencyDialog(
    BuildContext context, {
    CurrencyModel? currency,
  }) async {
    final code = TextEditingController(text: currency?.code ?? '');
    final name = TextEditingController(text: currency?.name ?? '');
    final symbol = TextEditingController(text: currency?.symbol ?? '');
    final rate = TextEditingController(
      text: currency?.exchangeRate.toString() ?? '1',
    );
    var isBase = currency?.isBase ?? false;
    var isActive = currency?.isActive ?? true;
    await showAppModuleDialog<void>(
      context: context,
      title: currency == null ? 'إضافة عملة' : 'تعديل العملة',
      windowKey: currency == null
          ? 'settings:currency:add'
          : 'settings:currency:${currency.code}',
      maxWidth: 540,
      maxHeight: 520,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: AppText(currency == null ? 'إضافة عملة' : 'تعديل العملة'),
          content: SizedBox(
            width: 450,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: code,
                  enabled: currency == null,
                  decoration: InputDecoration(
                    labelText: AppTranslation.translate('الرمز ISO'),
                  ),
                ),
                TextField(
                  controller: name,
                  decoration: InputDecoration(
                    labelText: AppTranslation.translate('اسم العملة'),
                  ),
                ),
                TextField(
                  controller: symbol,
                  decoration: InputDecoration(
                    labelText: AppTranslation.translate('العلامة'),
                  ),
                ),
                TextField(
                  controller: rate,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    ThousandsInputFormatter(decimalDigits: 15),
                  ],
                  decoration: InputDecoration(
                    labelText: AppTranslation.translate('سعر الصرف'),
                  ),
                ),
                SwitchListTile(
                  value: isBase,
                  onChanged: (v) => setState(() => isBase = v),
                  title: const AppText('العملة الأساسية'),
                ),
                SwitchListTile(
                  value: isActive,
                  onChanged: (v) => setState(() => isActive = v),
                  title: const AppText('نشطة'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const AppText('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                final parsedRate = ThousandsInputFormatter.parse(rate.text);
                if (code.text.trim().isEmpty ||
                    name.text.trim().isEmpty ||
                    parsedRate == null ||
                    parsedRate <= 0) {
                  return;
                }
                await controller.saveCurrency(
                  CurrencyModel(
                    code: code.text.trim().toUpperCase(),
                    name: name.text.trim(),
                    symbol: symbol.text.trim(),
                    exchangeRate: parsedRate,
                    isBase: isBase,
                    isActive: isActive,
                  ),
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const AppText('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackupsTab extends StatelessWidget {
  const _BackupsTab({required this.controller});
  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    final canManageBackups = context.select<AccessController, bool>(
      (access) => access.hasPermission(PermissionCodes.settingsBackup),
    );
    final canRestoreBackups = context.select<AccessController, bool>(
      (access) => access.hasPermission(PermissionCodes.settingsRestore),
    );

    return ListView(
      key: const ValueKey('settings-backups-full-page-scroll'),
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 12),
      children: [
        if (!canManageBackups || !canRestoreBackups) ...[
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: const Icon(Icons.lock_outline),
              title: const AppText('صلاحيات النسخ الاحتياطية'),
              subtitle: AppText(
                !canManageBackups && !canRestoreBackups
                    ? 'لا تملك صلاحية إدارة النسخ أو استعادتها.'
                    : !canManageBackups
                    ? 'يمكنك الاستعادة فقط؛ إنشاء النسخ وفحصها وحذفها غير متاح.'
                    : 'يمكنك إدارة النسخ، لكن الاستعادة تتطلب صلاحية مستقلة.',
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: AppResponsive.dialogWidth(context, 520),
                  child: const AppText(
                    'أنشئ نسخة داخلية أو استورد ملف نسخة محمولًا. يمكن تصدير أي نسخة وحفظها خارج النظام ثم استيرادها على جهاز آخر.',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
                FieldPermissionControl(
                  resource: 'settings',
                  field: 'backup',
                  viewPermission: PermissionCodes.settingsView,
                  writePermission: PermissionCodes.settingsBackup,
                  child: FilledButton.icon(
                    onPressed: controller.isLoading || !canManageBackups
                        ? null
                        : () => controller.createBackup(),
                    icon: const Icon(Icons.backup_outlined),
                    label: const AppText('إنشاء نسخة الآن'),
                  ),
                ),
                FieldPermissionControl(
                  resource: 'settings',
                  field: 'restore',
                  viewPermission: PermissionCodes.settingsView,
                  writePermission: PermissionCodes.settingsRestore,
                  child: OutlinedButton.icon(
                    onPressed: controller.isLoading || !canRestoreBackups
                        ? null
                        : () => _importBackup(context),
                    icon: const Icon(Icons.upload_file_outlined),
                    label: const AppText('استيراد ملف نسخة'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (controller.backups.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(22),
              child: AppText('لا توجد نسخ احتياطية بعد'),
            ),
          )
        else
          ...controller.backups.map(
            (backup) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: const Icon(Icons.storage_outlined),
                title: AppText(backup.name),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      '${backup.createdAt.toLocal()} • ${(backup.sizeBytes / 1024).toStringAsFixed(1)} KB • ${backup.recordCount} سجل',
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _BackupStatusChip(status: backup.status),
                        AppText(
                          'Schema ${backup.schemaVersion}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (backup.checksum.isNotEmpty)
                          Tooltip(
                            message: backup.checksum,
                            child: AppText(
                              'SHA-256: ${backup.checksum.substring(0, 10)}…',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                trailing: Wrap(
                  children: [
                    IconButton(
                      tooltip: AppTranslation.translate('تصدير إلى ملف'),
                      onPressed: controller.isLoading || !canManageBackups
                          ? null
                          : () => _exportBackup(context, backup.id),
                      icon: const Icon(Icons.download_outlined),
                    ),
                    IconButton(
                      tooltip: AppTranslation.translate('فحص السلامة'),
                      onPressed: controller.isLoading || !canManageBackups
                          ? null
                          : () => _verifyBackup(context, backup.id),
                      icon: const Icon(Icons.verified_outlined),
                    ),
                    IconButton(
                      tooltip: AppTranslation.translate('استعادة'),
                      onPressed:
                          controller.isLoading ||
                              !canRestoreBackups ||
                              backup.status == 'corrupted'
                          ? null
                          : () => _confirmRestore(context, backup.id),
                      icon: const Icon(Icons.restore),
                    ),
                    IconButton(
                      tooltip: AppTranslation.translate('حذف'),
                      onPressed: controller.isLoading || !canManageBackups
                          ? null
                          : () => controller.deleteBackup(backup.id),
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _exportBackup(BuildContext context, String id) async {
    try {
      final exported = await controller.exportBackup(id);
      final dot = exported.fileName.lastIndexOf('.');
      final name = dot > 0
          ? exported.fileName.substring(0, dot)
          : exported.fileName;
      final extension = dot > 0 ? exported.fileName.substring(dot + 1) : 'json';
      await FileSaver.instance.saveFile(
        name: name,
        bytes: exported.bytes,
        ext: extension,
        mimeType: MimeType.json,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: AppText('تم تصدير النسخة الاحتياطية.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AppText(controller.errorMessage ?? 'تعذر تصدير النسخة'),
          ),
        );
      }
    }
  }

  Future<void> _importBackup(BuildContext context) async {
    try {
      final selected = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json', 'qlbackup'],
        withData: true,
      );
      if (selected == null || selected.files.isEmpty) {
        return;
      }
      final file = selected.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        throw StateError('تعذر قراءة الملف المحدد.');
      }
      await controller.importBackup(bytes: bytes, sourceName: file.name);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: AppText('تم استيراد النسخة وفحص سلامتها بنجاح.'),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AppText(controller.errorMessage ?? 'تعذر استيراد النسخة'),
          ),
        );
      }
    }
  }

  Future<void> _verifyBackup(BuildContext context, String id) async {
    try {
      final valid = await controller.verifyBackup(id);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            valid
                ? 'تم التحقق من سلامة النسخة الاحتياطية.'
                : 'النسخة الاحتياطية تالفة أو غير صالحة.',
          ),
        ),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AppText(controller.errorMessage ?? 'تعذر فحص النسخة'),
          ),
        );
      }
    }
  }

  Future<void> _confirmRestore(BuildContext context, String id) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'استعادة النسخة الاحتياطية',
      message:
          'ستُستبدل البيانات الحالية بمحتوى النسخة. يوصى بإنشاء نسخة جديدة قبل المتابعة.',
      confirmLabel: 'استعادة',
      destructive: true,
    );
    if (confirmed == true) {
      try {
        await controller.restoreBackup(id);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: AppText(controller.errorMessage ?? 'تعذرت الاستعادة'),
            ),
          );
        }
      }
    }
  }
}

class _BackupStatusChip extends StatelessWidget {
  const _BackupStatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (status) {
      'verified' => ('سليمة', Icons.verified_outlined),
      'safety' => ('نسخة أمان', Icons.health_and_safety_outlined),
      'corrupted' => ('تالفة', Icons.warning_amber_rounded),
      _ => ('قديمة - تحتاج فحص', Icons.help_outline),
    };
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 16),
      label: AppText(label),
    );
  }
}
