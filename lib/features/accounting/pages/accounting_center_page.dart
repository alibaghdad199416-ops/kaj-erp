import 'dart:async';

import 'package:quality_line_erp/core/printing/accounting_report_export_service.dart';
import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';
import 'package:quality_line_erp/core/utils/erp_display_formatter.dart';
import 'package:quality_line_erp/core/errors/user_facing_error.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:quality_line_erp/core/widgets/app_module_dialog.dart';
import 'package:quality_line_erp/core/widgets/app_entity_page.dart';
import 'package:quality_line_erp/core/widgets/app_horizontal_strip.dart';
import 'package:quality_line_erp/core/widgets/compact_metric_pill.dart';
import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_phase6_components.dart';
import 'package:quality_line_erp/features/accounting/cashbox/pages/cashbox_page.dart';
import 'package:quality_line_erp/features/accounting/expenses/pages/expenses_page.dart';
import 'package:quality_line_erp/features/accounting/installments/pages/installments_page.dart';
import 'package:quality_line_erp/features/accounting/fixed_assets/fixed_assets_page.dart';
import 'package:quality_line_erp/features/accounting/controllers/accounting_controller.dart';
import 'package:quality_line_erp/features/accounting/models/account_model.dart';
import 'package:quality_line_erp/features/accounting/models/account_type_presentation.dart';
import 'package:quality_line_erp/features/accounting/repositories/professional_accounting_repository.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'account_statement_page.dart';
import 'accounting_page.dart';
import 'add_journal_entry_page.dart';

class AccountingCenterPage extends StatefulWidget {
  const AccountingCenterPage({super.key, this.initialSection = 0});

  final int initialSection;

  @override
  State<AccountingCenterPage> createState() => _AccountingCenterPageState();
}

class _AccountingCenterPageState extends State<AccountingCenterPage> {
  late int _selected;

  static const _sections = <_AccountingSection>[
    _AccountingSection(
      'دليل الحسابات',
      'Chart of Accounts',
      Icons.account_tree_outlined,
    ),
    _AccountingSection(
      'القيود اليومية',
      'Journal Entries',
      Icons.menu_book_outlined,
    ),
    _AccountingSection(
      'الصناديق والحسابات',
      'Cashboxes & Accounts',
      Icons.account_balance_wallet_outlined,
    ),
    _AccountingSection('المصاريف', 'Expenses', Icons.payments_outlined),
    _AccountingSection(
      'الأقساط والدفعات',
      'Installments & Payments',
      Icons.calendar_month_outlined,
    ),
    _AccountingSection(
      'كشف الحساب',
      'Account Statement',
      Icons.receipt_long_outlined,
    ),
    _AccountingSection(
      'ميزان المراجعة',
      'Trial Balance',
      Icons.balance_outlined,
    ),
    _AccountingSection(
      'دفتر الأستاذ العام',
      'General Ledger',
      Icons.auto_stories_outlined,
    ),
    _AccountingSection(
      'التدفق النقدي',
      'Cash Flow',
      Icons.waterfall_chart_outlined,
    ),
    _AccountingSection(
      'المركز المالي',
      'Financial Position',
      Icons.account_balance_outlined,
    ),
    _AccountingSection(
      'الأرباح والخسائر',
      'Profit & Loss',
      Icons.trending_up_outlined,
    ),
    _AccountingSection(
      'الأصول الثابتة',
      'Fixed Assets',
      Icons.apartment_outlined,
    ),
    _AccountingSection(
      'الفروع ومراكز الكلفة',
      'Branches & Cost Centers',
      Icons.hub_outlined,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSection.clamp(0, _sections.length - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<AccountingController>().loadAccounting();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AccountingController>();
    final isArabic = context.l10n.isArabic;
    return AppEntityPage(
      hideHeader: true,
      toolbarFramed: false,
      title: isArabic ? 'المركز المحاسبي' : 'Accounting Center',
      subtitle: isArabic
          ? 'الحسابات والقيود والصناديق والكشوف والتقارير المالية.'
          : 'Accounts, journals, cashboxes, statements and financial reports.',
      leading: const Icon(Icons.account_balance_outlined, size: 20),
      showBackButton: false,
      actions: [
        FilledButton.icon(
          onPressed: () => showAppWorkspaceDialog<void>(
            context: context,
            child: const AddJournalEntryPage(),
          ),
          icon: const Icon(Icons.post_add_outlined, size: 17),
          label: AppText(isArabic ? 'إدخال محاسبي جديد' : 'New journal entry'),
        ),
      ],
      statistics: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CompactMetricPill(
            icon: Icons.account_tree_outlined,
            label: isArabic ? 'الحسابات' : 'Accounts',
            value: controller.accounts.length.toString(),
          ),
          const SizedBox(width: 7),
          CompactMetricPill(
            icon: Icons.menu_book_outlined,
            label: isArabic ? 'القيود' : 'Entries',
            value: controller.entries.length.toString(),
          ),
          const SizedBox(width: 7),
          CompactMetricPill(
            icon: Icons.balance_outlined,
            label: 'ميزان USD',
            value: MoneyFormatter.format(
              controller.usdTrial['debit'] ?? 0,
              currency: 'USD',
            ),
          ),
          const SizedBox(width: 7),
          CompactMetricPill(
            icon: Icons.balance_outlined,
            label: 'ميزان IQD',
            value: MoneyFormatter.format(
              controller.iqdTrial['debit'] ?? 0,
              currency: 'IQD',
            ),
          ),
        ],
      ),
      toolbar: AppHorizontalStrip(
        spacing: 8,
        children: List<Widget>.generate(_sections.length, (index) {
          final section = _sections[index];
          final selected = _selected == index;
          final chip = SizedBox(
            width: 158,
            child: ChoiceChip(
              selected: selected,
              showCheckmark: false,
              onSelected: (_) => setState(() => _selected = index),
              avatar: Icon(section.icon, size: 15),
              label: SizedBox(
                width: 116,
                child: AppText(
                  isArabic ? section.ar : section.en,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                ),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
            ),
          );
          return index == 4
              ? PermissionVisibility(
                  permission: 'installments.view',
                  child: chip,
                )
              : chip;
        }, growable: false),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: KajExecutiveHero(
              eyebrow: AppTranslation.translate('الإدارة المالية التنفيذية'),
              title: AppTranslation.translate('المركز المالي والمحاسبي'),
              subtitle: AppTranslation.translate(
                'عرض موحد للحسابات والقيود والسيولة والأصول والتقارير المالية.',
              ),
              icon: Icons.account_balance_outlined,
              metrics: <KajExecutiveMetricData>[
                KajExecutiveMetricData(
                  label: AppTranslation.translate('الحسابات'),
                  value: controller.accounts.length.toString(),
                  icon: Icons.account_tree_outlined,
                  accent: KajDesignTokens.electricBlue,
                ),
                KajExecutiveMetricData(
                  label: AppTranslation.translate('القيود'),
                  value: controller.entries.length.toString(),
                  icon: Icons.menu_book_outlined,
                  accent: KajDesignTokens.staticGreen,
                ),
                KajExecutiveMetricData(
                  label: AppTranslation.translate('ميزان USD'),
                  value: MoneyFormatter.format(
                    controller.usdTrial['debit'] ?? 0,
                    currency: 'USD',
                  ),
                  icon: Icons.balance_outlined,
                  accent: KajDesignTokens.champagneGold,
                ),
                KajExecutiveMetricData(
                  label: AppTranslation.translate('ميزان IQD'),
                  value: MoneyFormatter.format(
                    controller.iqdTrial['debit'] ?? 0,
                    currency: 'IQD',
                  ),
                  icon: Icons.currency_exchange_outlined,
                  accent: KajDesignTokens.electricBlue,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: _sectionBody()),
        ],
      ),
    );
  }

  Widget _sectionBody() {
    switch (_selected) {
      case 0:
        return const _ChartOfAccountsView();
      case 1:
        return const AccountingPage(embedded: true);
      case 2:
        return const CashboxPage();
      case 3:
        return const ExpensesPage();
      case 4:
        return const PermissionVisibility(
          permission: 'installments.view',
          child: InstallmentsPage(),
        );
      case 5:
        return const AccountStatementPage();
      case 6:
        return const FieldPermissionVisibility(
          resource: 'accounting',
          field: 'trialBalance',
          viewPermission: 'accounting.view',
          child: _AccountingReportView(
            type: _AccountingReportType.trialBalance,
          ),
        );
      case 7:
        return const FieldPermissionVisibility(
          resource: 'accounting',
          field: 'generalLedger',
          viewPermission: 'accounting.view',
          child: _AccountingReportView(
            type: _AccountingReportType.generalLedger,
          ),
        );
      case 8:
        return const FieldPermissionVisibility(
          resource: 'accounting',
          field: 'cashFlow',
          viewPermission: 'accounting.view',
          child: _AccountingReportView(type: _AccountingReportType.cashFlow),
        );
      case 9:
        return const FieldPermissionVisibility(
          resource: 'accounting',
          field: 'balances',
          viewPermission: 'accounting.view',
          child: _AccountingReportView(
            type: _AccountingReportType.balanceSheet,
          ),
        );
      case 10:
        return const FieldPermissionVisibility(
          resource: 'accounting',
          field: 'balances',
          viewPermission: 'accounting.view',
          child: _AccountingReportView(type: _AccountingReportType.profitLoss),
        );
      case 11:
        return const FixedAssetsPage();
      case 12:
        return const _FinancialDimensionsView();
      default:
        return const SizedBox.shrink();
    }
  }
}

class _ChartOfAccountsView extends StatelessWidget {
  const _ChartOfAccountsView();

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountingController>().accounts;
    final roots = accounts.where((a) => a.parentId == null).toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            const Expanded(
              child: AppText(
                'دليل الحسابات الشجري',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            FilledButton.icon(
              onPressed: () => showAppModuleDialog<bool>(
                context: context,
                title: 'إضافة حساب فرعي',
                builder: (_) => const _AddAccountForm(),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const AppText('إضافة حساب'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const AppText(
          'أضف حسابات رئيسية أو مسارات فرعية غير محدودة ضمن شجرة الحسابات.',
        ),
        const SizedBox(height: 16),
        if (roots.isEmpty)
          const Center(child: AppText('لا توجد حسابات.'))
        else
          ...roots.map(
            (root) => _AccountTreeNode(account: root, accounts: accounts),
          ),
      ],
    );
  }
}

class _AccountTreeNode extends StatelessWidget {
  const _AccountTreeNode({required this.account, required this.accounts});
  final AccountModel account;
  final List<AccountModel> accounts;

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const AppText('حذف حساب من الشجرة'),
        content: AppText(
          'هل تريد حذف ${account.code} — ${account.name}؟ لا يمكن حذف الحساب إذا كان مستخدماً أو يحتوي على حسابات فرعية.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const AppText('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const AppText('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await context.read<AccountingController>().deleteAccount(account.id);
    } catch (error) {
      if (!context.mounted) return;
      AppLogger.debug('Account deletion failed: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            userFacingError(error, isArabic: context.l10n.isArabic),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final children = accounts
        .where((item) => item.parentId == account.id)
        .toList();
    return Card(
      child: ExpansionTile(
        initiallyExpanded: account.parentId == null,
        leading: const Icon(Icons.account_balance_outlined),
        title: Row(
          children: [
            Expanded(
              child: AppText(
                '${account.code} — ${account.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            AppText(
              account.type,
              maxLines: 1,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          key: ValueKey('account-actions-${account.id}'),
          tooltip: AppTranslation.translate('إجراءات الحساب'),
          onSelected: (action) {
            if (action == 'edit') {
              unawaited(
                showAppModuleDialog<bool>(
                  context: context,
                  title: 'تعديل الحساب',
                  builder: (_) => _AddAccountForm(editing: account),
                ),
              );
            } else if (action == 'add') {
              unawaited(
                showAppModuleDialog<bool>(
                  context: context,
                  title: 'إضافة حساب فرعي',
                  builder: (_) => _AddAccountForm(parent: account),
                ),
              );
            } else if (action == 'delete') {
              unawaited(_confirmDeleteAccount(context));
            }
          },
          itemBuilder: (_) => <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
              value: 'edit',
              child: AppText(AppTranslation.translate('تعديل الحساب')),
            ),
            PopupMenuItem<String>(
              value: 'add',
              child: AppText(AppTranslation.translate('إضافة حساب فرعي')),
            ),
            PopupMenuItem<String>(
              key: ValueKey('delete-account-${account.id}'),
              value: 'delete',
              child: AppText(AppTranslation.translate('حذف الحساب')),
            ),
          ],
        ),
        children: children.isEmpty
            ? [const SizedBox(height: 8)]
            : children
                  .map(
                    (child) => Padding(
                      padding: const EdgeInsetsDirectional.only(start: 18),
                      child: _AccountTreeNode(
                        account: child,
                        accounts: accounts,
                      ),
                    ),
                  )
                  .toList(),
      ),
    );
  }
}

class _AddAccountForm extends StatefulWidget {
  const _AddAccountForm({this.parent, this.editing});
  final AccountModel? parent;
  final AccountModel? editing;
  @override
  State<_AddAccountForm> createState() => _AddAccountFormState();
}

class _AddAccountFormState extends State<_AddAccountForm> {
  String get _writePermission =>
      widget.editing == null ? 'accounting.create' : 'accounting.update';

  Widget _securedField(String field, Widget child) => FieldPermissionControl(
    resource: 'accounting',
    field: field,
    viewPermission: 'accounting.view',
    writePermission: _writePermission,
    child: child,
  );

  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _name = TextEditingController();
  String _type = 'asset';
  String _currency = 'IQD';
  AccountModel? _parent;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _parent = e == null
        ? widget.parent
        : (e.parentId == null
              ? null
              : context
                    .read<AccountingController>()
                    .accounts
                    .where((a) => a.id == e.parentId)
                    .firstOrNull);
    if (e != null) {
      _code.text = e.code;
      _name.text = e.name;
      _type =
          const {
            'asset',
            'liability',
            'equity',
            'revenue',
            'expense',
          }.contains(e.type)
          ? e.type
          : 'asset';
      _currency =
          const {'USD', 'IQD', 'MULTI'}.contains(e.currency.toUpperCase())
          ? e.currency.toUpperCase()
          : 'IQD';
    } else {
      if (_parent != null) _type = _parent!.type;
      _syncCodePreview();
    }
  }

  void _syncCodePreview() {
    if (widget.editing != null) return;
    _code.text = _parent == null ? 'AUTO' : '${_parent!.code}.AUTO';
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountingController>().accounts;
    final excludedIds = <String>{};
    void collectDescendants(String id) {
      if (!excludedIds.add(id)) return;
      for (final child in accounts.where((item) => item.parentId == id)) {
        collectDescendants(child.id);
      }
    }

    if (widget.editing != null) collectDescendants(widget.editing!.id);
    final parentCandidates = accounts
        .where((item) => !excludedIds.contains(item.id) && item.isActive)
        .toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        title: AppText(
          widget.editing == null ? 'إضافة حساب إلى الشجرة' : 'تعديل الحساب',
        ),
        automaticallyImplyLeading: false,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(15),
          children: [
            _securedField(
              'parentAccount',
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: parentCandidates.any((a) => a.id == _parent?.id)
                    ? _parent!.id
                    : '__root__',
                decoration: InputDecoration(
                  labelText: AppTranslation.translate(
                    'الحساب الأب / المسار الرئيسي',
                  ),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: '__root__',
                    child: AppText('حساب رئيسي'),
                  ),
                  ...parentCandidates.map(
                    (a) => DropdownMenuItem<String>(
                      value: a.id,
                      child: AppText('${a.code} — ${a.name}'),
                    ),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() {
                        _parent = value == null || value == '__root__'
                            ? null
                            : parentCandidates.firstWhere(
                                (account) => account.id == value,
                              );
                        if (_parent != null) _type = _parent!.type;
                        _syncCodePreview();
                      }),
              ),
            ),
            const SizedBox(height: 14),
            _securedField(
              'accountCode',
              TextFormField(
                controller: _code,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: AppTranslation.translate(
                    widget.editing == null
                        ? 'رمز الحساب (يولد تلقائياً)'
                        : 'رمز الحساب',
                  ),
                  helperText: widget.editing == null
                      ? AppTranslation.translate(
                          'يولد الرمز تسلسلياً حسب الحساب الرئيسي المختار',
                        )
                      : null,
                  prefixIcon: const Icon(Icons.account_tree_outlined),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _securedField(
              'accountName',
              TextFormField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: AppTranslation.translate('اسم الحساب'),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? AppTranslation.translate('اسم الحساب مطلوب')
                    : null,
              ),
            ),
            const SizedBox(height: 14),
            _securedField(
              'accountType',
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _type,
                decoration: InputDecoration(
                  labelText: AppTranslation.translate('نوع الحساب'),
                ),
                items: const [
                  DropdownMenuItem(value: 'asset', child: AppText('أصول')),
                  DropdownMenuItem(value: 'liability', child: AppText('خصوم')),
                  DropdownMenuItem(
                    value: 'equity',
                    child: AppText('حقوق ملكية'),
                  ),
                  DropdownMenuItem(value: 'revenue', child: AppText('إيرادات')),
                  DropdownMenuItem(value: 'expense', child: AppText('مصروفات')),
                ],
                onChanged: _parent == null
                    ? (v) => setState(() {
                        _type = v ?? _type;
                      })
                    : null,
              ),
            ),
            const SizedBox(height: 14),
            _securedField(
              'currency',
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _currency,
                decoration: InputDecoration(
                  labelText: AppTranslation.translate('عملة الحساب'),
                ),
                items: const [
                  DropdownMenuItem(value: 'USD', child: AppText('USD')),
                  DropdownMenuItem(value: 'IQD', child: AppText('IQD')),
                ],
                // Leaf accounts may intentionally use a currency different
                // from their grouping parent. PostgreSQL validates postings on
                // the leaf account, so changing currency must not clear parent.
                onChanged: widget.editing == null
                    ? (value) => setState(() => _currency = value ?? _currency)
                    : null,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: AppText(_saving ? 'جاري الحفظ...' : 'حفظ الحساب'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final current = widget.editing;
      if (_parent?.id == current?.id) {
        throw StateError('لا يمكن جعل الحساب أباً لنفسه.');
      }
      final now = DateTime.now();
      final account = AccountModel(
        id: current?.id ?? const Uuid().v4(),
        code: current?.code ?? '',
        name: _name.text.trim(),
        type: _type,
        parentId: _parent?.id,
        currency: _currency,
        openingBalance: current?.openingBalance ?? 0,
        isActive: current?.isActive ?? true,
        createdAt: current?.createdAt ?? now,
        updatedAt: now,
      );
      final controller = context.read<AccountingController>();
      if (current == null) {
        await controller.addAccount(account);
      } else {
        await controller.updateAccount(account);
      }
      // Close only the module-local floating window. Using the root
      // navigator here pops the application's page route on Flutter Web.
      if (mounted) Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      AppLogger.debug('Account save failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            userFacingError(error, isArabic: context.l10n.isArabic),
          ),
        ),
      );
    }
  }
}

class _AccountingReportView extends StatefulWidget {
  const _AccountingReportView({required this.type});
  final _AccountingReportType type;

  @override
  State<_AccountingReportView> createState() => _AccountingReportViewState();
}

class _AccountingReportViewState extends State<_AccountingReportView> {
  Widget _reportField(String field, Widget child) => FieldPermissionControl(
    resource: 'reports',
    field: field,
    viewPermission: 'reports.view',
    writePermission: 'reports.view',
    child: child,
  );

  Widget _reportValue(String field, Widget child) => FieldPermissionVisibility(
    resource: 'reports',
    field: field,
    viewPermission: 'reports.view',
    child: child,
  );

  DateTime? _fromDate;
  DateTime? _toDate;
  String _currency = 'ALL';
  String? _branchId;
  String? _costCenterId;
  List<Map<String, Object?>> _branches = const [];
  List<Map<String, Object?>> _costCenters = const [];
  late Future<List<Map<String, Object?>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _initialize();
  }

  @override
  void didUpdateWidget(covariant _AccountingReportView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.type != widget.type) {
      _future = _load();
    }
  }

  Future<List<Map<String, Object?>>> _initialize() async {
    final repository = ProfessionalAccountingRepository();
    final results = await Future.wait<List<Map<String, Object?>>>([
      repository.getBranches(),
      repository.getCostCenters(),
    ]);
    if (mounted) {
      setState(() {
        _branches = results[0];
        _costCenters = results[1];
      });
    } else {
      _branches = results[0];
      _costCenters = results[1];
    }
    return _load();
  }

  void _refresh() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, Object?>>>(
      future: _future,
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const <Map<String, Object?>>[];
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 330,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(
                        _title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      AppText(_description),
                    ],
                  ),
                ),
                _reportField(
                  'currencyFilter',
                  DropdownButton<String>(
                    value: _currency,
                    items: const [
                      DropdownMenuItem(
                        value: 'ALL',
                        child: AppText('كل العملات'),
                      ),
                      DropdownMenuItem(value: 'USD', child: AppText('USD')),
                      DropdownMenuItem(value: 'IQD', child: AppText('IQD')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        _currency = value;
                        _refresh();
                      }
                    },
                  ),
                ),
                DropdownButton<String?>(
                  value: _branchId,
                  hint: const AppText('كل الفروع'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: AppText('كل الفروع'),
                    ),
                    ..._branches.map(
                      (row) => DropdownMenuItem<String?>(
                        value: row['id']?.toString(),
                        child: AppText(
                          (row['nameAr'] ?? row['name'] ?? row['code'])
                              .toString(),
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    _branchId = value;
                    _refresh();
                  },
                ),
                DropdownButton<String?>(
                  value: _costCenterId,
                  hint: const AppText('كل مراكز الكلفة'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: AppText('كل مراكز الكلفة'),
                    ),
                    ..._costCenters.map(
                      (row) => DropdownMenuItem<String?>(
                        value: row['id']?.toString(),
                        child: AppText(
                          '${row['code']} - ${(row['nameAr'] ?? row['nameEn'] ?? '').toString()}',
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    _costCenterId = value;
                    _refresh();
                  },
                ),
                _reportField(
                  'dateRange',
                  OutlinedButton.icon(
                    onPressed: _pickRange,
                    icon: const Icon(Icons.date_range_outlined),
                    label: AppText(_rangeLabel),
                  ),
                ),
                if (_fromDate != null)
                  _reportField(
                    'dateRange',
                    TextButton.icon(
                      onPressed: () {
                        _fromDate = null;
                        _toDate = null;
                        _refresh();
                      },
                      icon: const Icon(Icons.clear),
                      label: const AppText('مسح الفترة'),
                    ),
                  ),
                _reportField(
                  'exportExcel',
                  FilledButton.icon(
                    key: widget.type == _AccountingReportType.generalLedger
                        ? const ValueKey('export-general-ledger-excel')
                        : ValueKey('export-${widget.type.name}-excel'),
                    onPressed: rows.isEmpty ? null : () => _exportReport(rows),
                    icon: const Icon(Icons.table_view_outlined, size: 18),
                    label: AppText(
                      AppTranslation.translate('تصدير Excel كامل'),
                    ),
                  ),
                ),
                _reportField(
                  'exportPdf',
                  OutlinedButton.icon(
                    onPressed: rows.isEmpty ? null : () => _printReport(rows),
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: const AppText('طباعة PDF'),
                  ),
                ),
                _reportField(
                  'exportPdf',
                  OutlinedButton.icon(
                    onPressed: rows.isEmpty
                        ? null
                        : () => _downloadReport(rows),
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: const AppText('تنزيل PDF'),
                  ),
                ),
                IconButton(
                  onPressed: _refresh,
                  tooltip: AppTranslation.translate('تحديث'),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (snapshot.connectionState == ConnectionState.waiting)
              const LinearProgressIndicator(),
            if (snapshot.hasError)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: AppText(
                    userFacingError(
                      snapshot.error!,
                      isArabic: context.l10n.isArabic,
                      arabicFallback: 'تعذر تحميل التقرير.',
                      englishFallback: 'Unable to load the report.',
                    ),
                  ),
                ),
              ),
            if (!snapshot.hasError &&
                snapshot.connectionState != ConnectionState.waiting &&
                rows.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(30),
                  child: Center(
                    child: AppText(
                      'لا توجد بيانات متاحة ضمن المرشحات الحالية.',
                    ),
                  ),
                ),
              ),
            if (rows.isNotEmpty) ...[
              _summary(rows),
              const SizedBox(height: 12),
              if (widget.type == _AccountingReportType.generalLedger ||
                  widget.type == _AccountingReportType.trialBalance ||
                  widget.type == _AccountingReportType.cashFlow)
                _accountHierarchyGroupedTable(rows)
              else
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: const WidgetStatePropertyAll(
                        Colors.black12,
                      ),
                      columns: rows.first.keys
                          .map(
                            (key) => DataColumn(
                              label: AppText(
                                _label(key),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      rows: rows
                          .map(
                            (row) => DataRow(
                              cells: row.entries
                                  .map(
                                    (entry) =>
                                        DataCell(AppText(_format(entry.value))),
                                  )
                                  .toList(),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _accountHierarchyGroupedTable(List<Map<String, Object?>> rows) {
    String reportAccountCode(Object? value) {
      final raw = value?.toString().trim() ?? '';
      return raw.isEmpty ? '' : ErpDisplayFormatter.accountCode(raw);
    }

    String accountKey(Map<String, Object?> row) {
      final code = reportAccountCode(row['accountCode']);
      final name = (row['accountName'] ?? '').toString().trim();
      final path = (row['hierarchyPath'] ?? '').toString().trim();
      return '$path|$code|$name';
    }

    String accountTitle(Map<String, Object?> row) {
      final code = reportAccountCode(row['accountCode']);
      final name = (row['accountName'] ?? '').toString().trim();
      final path = (row['hierarchyPath'] ?? '').toString().trim();
      final leaf = code.isEmpty ? name : '$code — $name';
      if (path.isEmpty || path == name) return leaf;
      return '$path / $leaf';
    }

    String sectionFor(Map<String, Object?> row) {
      if (widget.type != _AccountingReportType.cashFlow) return 'entries';
      final cashIn = _toDouble(row['cashIn']);
      final cashOut = _toDouble(row['cashOut']);
      return cashIn > 0 ||
              (cashIn == 0 && cashOut == 0 && _toDouble(row['debit']) > 0)
          ? 'cashIn'
          : 'cashOut';
    }

    final grouped = <String, Map<String, List<Map<String, Object?>>>>{};
    final samples = <String, Map<String, Object?>>{};
    for (final row in rows) {
      final section = sectionFor(row);
      final key = accountKey(row);
      grouped
          .putIfAbsent(section, () => <String, List<Map<String, Object?>>>{})
          .putIfAbsent(key, () => <Map<String, Object?>>[])
          .add(row);
      samples[key] = row;
    }

    const preferredColumns = <String>[
      'entryDate',
      'entryNumber',
      'accountCode',
      'accountName',
      'description',
      'partyName',
      'paymentMethod',
      'referenceType',
      'referenceId',
      'currency',
      'openingBalance',
      'openingDebit',
      'openingCredit',
      'periodDebit',
      'periodCredit',
      'closingDebit',
      'closingCredit',
      'debit',
      'credit',
      'cashIn',
      'cashOut',
      'netCashFlow',
      'runningBalance',
    ];

    final sectionOrder = widget.type == _AccountingReportType.cashFlow
        ? const <String>['cashIn', 'cashOut']
        : const <String>['entries'];

    return Column(
      key: ValueKey('${widget.type.name}-final-account-entry-tables'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: sectionOrder
          .where(grouped.containsKey)
          .map((section) {
            final accounts = grouped[section]!;
            final sectionTitle = section == 'cashIn'
                ? 'Cash In'
                : section == 'cashOut'
                ? 'Cash Out'
                : _title;
            final sectionTotal = accounts.values.fold<int>(
              0,
              (sum, entries) => sum + entries.length,
            );
            final orderedAccounts = accounts.entries.toList(growable: false)
              ..sort((left, right) {
                final leftRow = samples[left.key] ?? left.value.first;
                final rightRow = samples[right.key] ?? right.value.first;
                final typeOrder =
                    AccountTypePresentation.orderOf(
                      leftRow['accountType'],
                    ).compareTo(
                      AccountTypePresentation.orderOf(rightRow['accountType']),
                    );
                if (typeOrder != 0) return typeOrder;
                return reportAccountCode(
                  leftRow['accountCode'],
                ).compareTo(reportAccountCode(rightRow['accountCode']));
              });
            return Card(
              margin: const EdgeInsets.only(bottom: 14),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: AppText(
                            sectionTitle,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        AppText(
                          '${context.l10n.isArabic ? 'عدد الإدخالات' : 'Entries'}: $sectionTotal',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ...orderedAccounts.map((account) {
                      final accountRows = account.value
                        ..sort((left, right) {
                          final leftDate = '${left['entryDate'] ?? ''}';
                          final rightDate = '${right['entryDate'] ?? ''}';
                          final dateResult = leftDate.compareTo(rightDate);
                          if (dateResult != 0) return dateResult;
                          return '${left['entryNumber'] ?? ''}'.compareTo(
                            '${right['entryNumber'] ?? ''}',
                          );
                        });
                      final sample = samples[account.key] ?? accountRows.first;
                      final columns = preferredColumns
                          .where(
                            (key) => accountRows.any(
                              (row) =>
                                  row.containsKey(key) &&
                                  '${row[key] ?? ''}'.trim().isNotEmpty,
                            ),
                          )
                          .toList(growable: false);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).dividerColor,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerLow,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(11),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.account_tree_outlined,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: AppText(
                                      accountTitle(sample),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  AppText(
                                    '${context.l10n.isArabic ? 'السطور' : 'Rows'}: ${accountRows.length}',
                                  ),
                                ],
                              ),
                            ),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                headingRowColor: const WidgetStatePropertyAll(
                                  Colors.black12,
                                ),
                                columns: columns
                                    .map(
                                      (key) => DataColumn(
                                        label: AppText(
                                          _label(key),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(growable: false),
                                rows: accountRows
                                    .map(
                                      (row) => DataRow(
                                        cells: columns
                                            .map(
                                              (key) => DataCell(
                                                AppText(
                                                  key == 'accountCode'
                                                      ? reportAccountCode(
                                                          row[key],
                                                        )
                                                      : _format(row[key]),
                                                ),
                                              ),
                                            )
                                            .toList(growable: false),
                                      ),
                                    )
                                    .toList(growable: false),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }

  Widget _summary(List<Map<String, Object?>> rows) {
    double total(Iterable<Map<String, Object?>> source, String key) =>
        source.fold(0, (sum, row) => sum + _toDouble(row[key]));

    final currencyGroups = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      final currency = (row['currency'] ?? _currency)
          .toString()
          .trim()
          .toUpperCase();
      final key = currency == 'USD' || currency == 'IQD'
          ? currency
          : (_currency == 'ALL' ? 'N/A' : _currency);
      currencyGroups.putIfAbsent(key, () => <Map<String, Object?>>[]).add(row);
    }
    final orderedCurrencies = <String>[
      if (currencyGroups.containsKey('USD')) 'USD',
      if (currencyGroups.containsKey('IQD')) 'IQD',
      ...currencyGroups.keys.where((key) => key != 'USD' && key != 'IQD'),
    ];

    final values = <(String, String, double)>[];
    for (final currency in orderedCurrencies) {
      final group = currencyGroups[currency]!;
      switch (widget.type) {
        case _AccountingReportType.trialBalance:
          final debit = total(group, 'periodDebit');
          final credit = total(group, 'periodCredit');
          values.addAll(<(String, String, double)>[
            (
              'totalDebit',
              '${context.l10n.isArabic ? 'إجمالي حركة المدين' : 'Total period debit'} ($currency)',
              debit,
            ),
            (
              'totalCredit',
              '${context.l10n.isArabic ? 'إجمالي حركة الدائن' : 'Total period credit'} ($currency)',
              credit,
            ),
            (
              'trialBalance',
              '${context.l10n.isArabic ? 'فرق الحركة' : 'Period difference'} ($currency)',
              debit - credit,
            ),
          ]);
          break;
        case _AccountingReportType.generalLedger:
          values.addAll(<(String, String, double)>[
            (
              'journalLedger',
              '${context.l10n.isArabic ? 'عدد السطور' : 'Rows'} ($currency)',
              group.length.toDouble(),
            ),
            (
              'totalDebit',
              '${context.l10n.isArabic ? 'إجمالي المدين' : 'Total debit'} ($currency)',
              total(group, 'debit'),
            ),
            (
              'totalCredit',
              '${context.l10n.isArabic ? 'إجمالي الدائن' : 'Total credit'} ($currency)',
              total(group, 'credit'),
            ),
          ]);
          break;
        case _AccountingReportType.cashFlow:
          values.addAll(<(String, String, double)>[
            (
              'cashIn',
              '${context.l10n.isArabic ? 'التدفقات الداخلة' : 'Cash in'} ($currency)',
              total(group, 'cashIn'),
            ),
            (
              'cashOut',
              '${context.l10n.isArabic ? 'التدفقات الخارجة' : 'Cash out'} ($currency)',
              total(group, 'cashOut'),
            ),
            (
              'journalLedger',
              '${context.l10n.isArabic ? 'صافي التدفق' : 'Net cash flow'} ($currency)',
              total(group, 'netCashFlow'),
            ),
          ]);
          break;
        case _AccountingReportType.balanceSheet:
          values.addAll(<(String, String, double)>[
            (
              'journalLedger',
              '${context.l10n.isArabic ? 'الموجودات' : 'Assets'} ($currency)',
              total(group, 'assets'),
            ),
            (
              'journalLedger',
              '${context.l10n.isArabic ? 'المطلوبات' : 'Liabilities'} ($currency)',
              total(group, 'liabilities'),
            ),
            (
              'journalLedger',
              '${context.l10n.isArabic ? 'حقوق الملكية' : 'Equity'} ($currency)',
              total(group, 'equity'),
            ),
          ]);
          break;
        case _AccountingReportType.profitLoss:
          values.addAll(<(String, String, double)>[
            (
              'journalLedger',
              '${context.l10n.isArabic ? 'الإيرادات' : 'Revenue'} ($currency)',
              total(group, 'revenue'),
            ),
            (
              'journalLedger',
              '${context.l10n.isArabic ? 'المصروفات' : 'Expenses'} ($currency)',
              total(group, 'expenses'),
            ),
            (
              'journalLedger',
              '${context.l10n.isArabic ? 'صافي الربح' : 'Net profit'} ($currency)',
              total(group, 'netProfit'),
            ),
          ]);
          break;
      }
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: values
          .map(
            (item) => _reportValue(
              item.$1,
              SizedBox(
                width: 220,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppText(
                          item.$2,
                          style: const TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 5),
                        AppText(
                          _number(item.$3),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Future<void> _exportReport(List<Map<String, Object?>> rows) async {
    try {
      await const AccountingReportExportService().exportExcel(
        reportName: _exportTitle,
        period: _exportRangeLabel,
        currency: _currency == 'ALL' ? 'All currencies' : _currency,
        rows: rows,
        label: _exportLabel,
        format: _format,
        arabic: false,
        forceCashFlow: widget.type == _AccountingReportType.cashFlow,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            userFacingError(error, isArabic: context.l10n.isArabic),
          ),
        ),
      );
    }
  }

  Future<void> _printReport(List<Map<String, Object?>> rows) async {
    try {
      await const AccountingReportExportService().printPdf(
        reportName: _exportTitle,
        period: _exportRangeLabel,
        currency: _currency == 'ALL' ? 'All currencies' : _currency,
        rows: rows,
        label: _exportLabel,
        format: _format,
        arabic: false,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            userFacingError(error, isArabic: context.l10n.isArabic),
          ),
        ),
      );
    }
  }

  Future<void> _downloadReport(List<Map<String, Object?>> rows) async {
    try {
      await const AccountingReportExportService().downloadPdf(
        reportName: _exportTitle,
        period: _exportRangeLabel,
        currency: _currency == 'ALL' ? 'All currencies' : _currency,
        rows: rows,
        label: _exportLabel,
        format: _format,
        arabic: false,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            userFacingError(error, isArabic: context.l10n.isArabic),
          ),
        ),
      );
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _fromDate != null && _toDate != null
          ? DateTimeRange(start: _fromDate!, end: _toDate!)
          : null,
    );
    if (range != null) {
      _fromDate = range.start;
      _toDate = range.end;
      _refresh();
    }
  }

  String get _exportRangeLabel => _fromDate == null
      ? 'All periods'
      : '${_fromDate!.year}/${_fromDate!.month.toString().padLeft(2, '0')}/${_fromDate!.day.toString().padLeft(2, '0')} - ${_toDate!.year}/${_toDate!.month.toString().padLeft(2, '0')}/${_toDate!.day.toString().padLeft(2, '0')}';
  String get _exportTitle => switch (widget.type) {
    _AccountingReportType.trialBalance => 'Detailed Trial Balance',
    _AccountingReportType.generalLedger => 'General Ledger',
    _AccountingReportType.cashFlow => 'Cash Flow Statement',
    _AccountingReportType.balanceSheet => 'Financial Position',
    _AccountingReportType.profitLoss => 'Profit and Loss Statement',
  };
  String _exportLabel(String key) =>
      const <String, String>{
        'code': 'Code',
        'name': 'Account',
        'type': 'Type',
        'currency': 'Currency',
        'openingBalance': 'Opening balance',
        'openingDebit': 'Opening debit',
        'openingCredit': 'Opening credit',
        'periodDebit': 'Period debit',
        'periodCredit': 'Period credit',
        'closingDebit': 'Closing debit',
        'closingCredit': 'Closing credit',
        'flowSection': 'Flow classification',
        'debit': 'Debit',
        'credit': 'Credit',
        'balance': 'Balance',
        'entryDate': 'Date',
        'entryNumber': 'Entry number',
        'accountCode': 'Account code',
        'accountName': 'Account name',
        'accountType': 'Account type',
        'parentAccountCode': 'Parent account code',
        'parentAccountName': 'Parent account name',
        'partyName': 'Party',
        'paymentMethod': 'Payment method',
        'referenceType': 'Reference type',
        'referenceId': 'Reference ID',
        'description': 'Description',
        'cashIn': 'Cash in',
        'cashOut': 'Cash out',
        'netCashFlow': 'Net cash flow',
        'runningBalance': 'Running balance',
        'assets': 'Assets',
        'liabilities': 'Liabilities',
        'equity': 'Equity',
        'difference': 'Equation difference',
        'revenue': 'Revenue',
        'expenses': 'Expenses',
        'netProfit': 'Net profit',
        'costCenterName': 'Cost center',
        'branchName': 'Branch',
      }[key] ??
      key;

  String get _rangeLabel => _fromDate == null
      ? 'كل الفترات'
      : '${_fromDate!.year}/${_fromDate!.month}/${_fromDate!.day} - ${_toDate!.year}/${_toDate!.month}/${_toDate!.day}';
  String get _title => switch (widget.type) {
    _AccountingReportType.trialBalance => 'ميزان المراجعة التفصيلي',
    _AccountingReportType.generalLedger => 'دفتر الأستاذ العام',
    _AccountingReportType.cashFlow => 'قائمة التدفق النقدي',
    _AccountingReportType.balanceSheet => 'قائمة المركز المالي',
    _AccountingReportType.profitLoss => 'قائمة الأرباح والخسائر',
  };
  String get _description => switch (widget.type) {
    _AccountingReportType.trialBalance =>
      'أرصدة وحركات الحسابات من القيود المرحلة فقط.',
    _AccountingReportType.generalLedger => 'كل حركات الحسابات مع رصيد تراكمي.',
    _AccountingReportType.cashFlow => 'المقبوضات والمدفوعات وصافي التدفق.',
    _AccountingReportType.balanceSheet => 'الموجودات والمطلوبات وحقوق الملكية.',
    _AccountingReportType.profitLoss => 'الإيرادات والمصروفات وصافي الربح.',
  };

  Future<List<Map<String, Object?>>> _load() async {
    return ProfessionalAccountingRepository().loadReport(
      type: widget.type.name,
      currency: _currency,
      branchId: _branchId,
      costCenterId: _costCenterId,
      fromDate: _fromDate,
      toDate: _toDate,
    );
  }

  String _label(String key) =>
      const {
        'code': 'الرمز',
        'name': 'الحساب',
        'type': 'النوع',
        'currency': 'العملة',
        'openingBalance': 'الرصيد الافتتاحي',
        'openingDebit': 'افتتاحي مدين',
        'openingCredit': 'افتتاحي دائن',
        'periodDebit': 'حركة مدين',
        'periodCredit': 'حركة دائن',
        'closingDebit': 'ختامي مدين',
        'closingCredit': 'ختامي دائن',
        'flowSection': 'تصنيف التدفق',
        'debit': 'مدين',
        'credit': 'دائن',
        'balance': 'الرصيد',
        'entryDate': 'التاريخ',
        'entryNumber': 'رقم القيد',
        'accountCode': 'رمز الحساب',
        'accountName': 'اسم الحساب',
        'accountType': 'نوع الحساب',
        'parentAccountCode': 'رمز الحساب الرئيسي',
        'parentAccountName': 'اسم الحساب الرئيسي',
        'partyName': 'الطرف',
        'paymentMethod': 'طريقة الدفع',
        'referenceType': 'نوع المرجع',
        'referenceId': 'رقم المرجع',
        'description': 'البيان',
        'cashIn': 'التدفقات الداخلة',
        'cashOut': 'التدفقات الخارجة',
        'netCashFlow': 'صافي التدفق',
        'runningBalance': 'الرصيد التراكمي',
        'assets': 'الموجودات',
        'liabilities': 'المطلوبات',
        'equity': 'حقوق الملكية',
        'difference': 'فرق المعادلة',
        'revenue': 'الإيرادات',
        'expenses': 'المصروفات',
        'netProfit': 'صافي الربح',
      }[key] ??
      key;
  String _format(Object? value) => value is num
      ? _number(value.toDouble())
      : ((value?.toString() ?? '').contains('T')
            ? (value?.toString() ?? '').split('T').first
            : value?.toString() ?? '');
  String _number(double value) {
    final fixed = MoneyFormatter.format(value, currency: _currency);
    final p = fixed.split('.');
    final sign = p[0].startsWith('-') ? '-' : '';
    final d = p[0]
        .replaceFirst('-', '')
        .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return '$sign$d${p.length > 1 ? '.${p[1]}' : ''}';
  }

  double _toDouble(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
}

class _FinancialDimensionsView extends StatefulWidget {
  const _FinancialDimensionsView();

  @override
  State<_FinancialDimensionsView> createState() =>
      _FinancialDimensionsViewState();
}

class _FinancialDimensionsViewState extends State<_FinancialDimensionsView> {
  late Future<Map<String, List<Map<String, Object?>>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, List<Map<String, Object?>>>> _load() async {
    final repository = ProfessionalAccountingRepository();
    final values = await Future.wait<List<Map<String, Object?>>>([
      repository.getBranches(),
      repository.getCostCenters(),
    ]);
    return {'branches': values[0], 'costCenters': values[1]};
  }

  void _refresh() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, List<Map<String, Object?>>>>(
      future: _future,
      builder: (context, snapshot) {
        final branches =
            snapshot.data?['branches'] ?? const <Map<String, Object?>>[];
        final centers =
            snapshot.data?['costCenters'] ?? const <Map<String, Object?>>[];
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const AppText(
              'الفروع ومراكز الكلفة',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const AppText(
              'إدارة الأبعاد المستخدمة لتصفية التقارير وتوزيع القيود والمستندات المالية.',
            ),
            const SizedBox(height: 18),
            if (snapshot.connectionState == ConnectionState.waiting)
              const LinearProgressIndicator(),
            _dimensionHeader(
              'الفروع',
              Icons.store_outlined,
              () => _openBranchForm(context),
            ),
            const SizedBox(height: 8),
            if (branches.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: AppText('لا توجد فروع معرفة.'),
                ),
              )
            else
              ...branches.map(
                (row) => Card(
                  child: ListTile(
                    leading: Icon(
                      (row['isMain'] as num? ?? 0) == 1
                          ? Icons.star_rounded
                          : Icons.store_outlined,
                    ),
                    title: AppText(
                      (row['nameAr'] ?? row['name'] ?? '').toString(),
                    ),
                    subtitle: AppText(
                      '${row['code'] ?? ''} • ${((row['isActive'] as num?)?.toInt() ?? 1) == 1 ? 'فعال' : 'غير فعال'}',
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 20),
            _dimensionHeader(
              'مراكز الكلفة',
              Icons.account_tree_outlined,
              () => _openCostCenterForm(context, centers),
            ),
            const SizedBox(height: 8),
            if (centers.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: AppText('لا توجد مراكز كلفة معرفة.'),
                ),
              )
            else
              ...centers.map(
                (row) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.hub_outlined),
                    title: AppText(
                      '${row['code']} - ${(row['nameAr'] ?? row['nameEn'] ?? '').toString()}',
                    ),
                    subtitle: AppText(
                      ((row['isActive'] as num?)?.toInt() ?? 1) == 1
                          ? 'فعال'
                          : 'غير فعال',
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _dimensionHeader(String title, IconData icon, VoidCallback onAdd) {
    return Row(
      children: [
        Icon(icon),
        const SizedBox(width: 8),
        Expanded(
          child: AppText(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const AppText('إضافة'),
        ),
      ],
    );
  }

  Future<void> _openBranchForm(BuildContext context) async {
    final code = TextEditingController();
    final name = TextEditingController();
    var isMain = false;
    final saved = await showAppModuleDialog<bool>(
      context: context,
      title: 'إضافة فرع',
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: code,
                decoration: InputDecoration(
                  labelText: AppTranslation.translate('رمز الفرع'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: name,
                decoration: InputDecoration(
                  labelText: AppTranslation.translate('اسم الفرع'),
                ),
              ),
              SwitchListTile(
                value: isMain,
                onChanged: (value) => setLocalState(() => isMain = value),
                title: const AppText('فرع رئيسي'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  if (code.text.trim().isEmpty || name.text.trim().isEmpty)
                    return;
                  await ProfessionalAccountingRepository().addBranch(
                    code: code.text,
                    nameAr: name.text,
                    nameEn: name.text,
                    isMain: isMain,
                  );
                  if (dialogContext.mounted)
                    Navigator.of(dialogContext).pop(true);
                },
                child: const AppText('حفظ الفرع'),
              ),
            ],
          ),
        ),
      ),
    );
    code.dispose();
    name.dispose();
    if (saved == true) _refresh();
  }

  Future<void> _openCostCenterForm(
    BuildContext context,
    List<Map<String, Object?>> centers,
  ) async {
    if (!await PermissionAction.require(context, 'accounting.create')) return;
    if (!context.mounted) return;
    final code = TextEditingController();
    final name = TextEditingController();
    String? parentId;
    final saved = await showAppModuleDialog<bool>(
      context: context,
      title: 'إضافة مركز كلفة',
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: code,
                decoration: InputDecoration(
                  labelText: AppTranslation.translate('رمز مركز الكلفة'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: name,
                decoration: InputDecoration(
                  labelText: AppTranslation.translate('اسم مركز الكلفة'),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: parentId,
                decoration: InputDecoration(
                  labelText: AppTranslation.translate('المركز الأب (اختياري)'),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: AppText('بدون مركز أب'),
                  ),
                  ...centers.map(
                    (row) => DropdownMenuItem<String?>(
                      value: row['id']?.toString(),
                      child: AppText('${row['code']} - ${row['nameAr'] ?? ''}'),
                    ),
                  ),
                ],
                onChanged: (value) => setLocalState(() => parentId = value),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () async {
                  if (code.text.trim().isEmpty || name.text.trim().isEmpty)
                    return;
                  await ProfessionalAccountingRepository().addCostCenter(
                    code: code.text,
                    nameAr: name.text,
                    nameEn: name.text,
                    parentId: parentId,
                  );
                  if (dialogContext.mounted)
                    Navigator.of(dialogContext).pop(true);
                },
                child: const AppText('حفظ مركز الكلفة'),
              ),
            ],
          ),
        ),
      ),
    );
    code.dispose();
    name.dispose();
    if (saved == true) _refresh();
  }
}

enum _AccountingReportType {
  trialBalance,
  generalLedger,
  cashFlow,
  balanceSheet,
  profitLoss,
}

class _AccountingSection {
  const _AccountingSection(this.ar, this.en, this.icon);
  final String ar;
  final String en;
  final IconData icon;
}

extension _AccountFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final i = iterator;
    return i.moveNext() ? i.current : null;
  }
}
