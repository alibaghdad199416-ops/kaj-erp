import 'dart:async';

import 'package:quality_line_erp/core/printing/accounting_report_export_service.dart';
import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';
import 'package:quality_line_erp/core/utils/erp_display_formatter.dart';
import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/events/app_data_change_bus.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:quality_line_erp/core/widgets/app_module_dialog.dart';
import 'package:quality_line_erp/core/widgets/compact_metric_pill.dart';
import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';
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
  const AccountingCenterPage({
    super.key,
    this.initialSection = 0,
    this.initialCashboxId,
  });

  final int initialSection;
  final String? initialCashboxId;

  @override
  State<AccountingCenterPage> createState() => _AccountingCenterPageState();
}

class _AccountingCenterPageState extends State<AccountingCenterPage> {
  late int _selected;
  StreamSubscription<AppDataChangeEvent>? _changes;

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
    _changes = AppDataChangeBus.instance.events
        .where(
          (event) => const {
            'accounting',
            'cashbox',
            'expenses',
            'sales',
            'purchases',
          }.contains(event.source),
        )
        .listen((_) {
          if (mounted) {
            unawaited(
              context.read<AccountingController>().refreshHeaderSnapshot(),
            );
          }
        });
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AccountingController>();
    final isArabic = context.l10n.isArabic;

    final commandRail = ScrollConfiguration(
      behavior: ScrollConfiguration.of(
        context,
      ).copyWith(scrollbars: false, overscroll: false),
      child: SingleChildScrollView(
        key: const ValueKey('accounting-command-horizontal-rail'),
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.icon(
              onPressed: () => showAppWorkspaceDialog<void>(
                context: context,
                child: const AddJournalEntryPage(),
              ),
              icon: const Icon(Icons.post_add_outlined, size: 17),
              label: AppText(
                isArabic ? 'إدخال محاسبي جديد' : 'New journal entry',
              ),
            ),
            const SizedBox(width: 8),
            CompactMetricPill(
              icon: Icons.account_tree_outlined,
              label: isArabic ? 'الحسابات' : 'Accounts',
              value: controller.headerAccountCount.toString(),
            ),
            const SizedBox(width: 7),
            CompactMetricPill(
              icon: Icons.menu_book_outlined,
              label: isArabic ? 'القيود' : 'Entries',
              value: controller.headerEntryCount.toString(),
            ),
            const SizedBox(width: 7),
            CompactMetricPill(
              icon: Icons.balance_outlined,
              label: isArabic ? 'النقد المتاح USD' : 'Available cash USD',
              value: MoneyFormatter.format(
                controller.cashByCurrency['USD'] ?? 0,
                currency: 'USD',
              ),
            ),
            const SizedBox(width: 7),
            CompactMetricPill(
              icon: Icons.balance_outlined,
              label: isArabic ? 'النقد المتاح IQD' : 'Available cash IQD',
              value: MoneyFormatter.format(
                controller.cashByCurrency['IQD'] ?? 0,
                currency: 'IQD',
              ),
            ),
          ],
        ),
      ),
    );

    final sectionStrip = ScrollConfiguration(
      behavior: ScrollConfiguration.of(
        context,
      ).copyWith(scrollbars: false, overscroll: false),
      child: SingleChildScrollView(
        key: const ValueKey('accounting-section-horizontal-nav'),
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List<Widget>.generate(_sections.length, (index) {
            final section = _sections[index];
            final selected = _selected == index;
            final chip = Padding(
              padding: EdgeInsetsDirectional.only(
                end: index == _sections.length - 1 ? 0 : 8,
              ),
              child: ChoiceChip(
                selected: selected,
                showCheckmark: false,
                onSelected: (_) => setState(() => _selected = index),
                avatar: Icon(section.icon, size: 14),
                label: AppText(
                  isArabic ? section.ar : section.en,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
                labelPadding: const EdgeInsets.symmetric(horizontal: 7),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
                visualDensity: const VisualDensity(
                  horizontal: -2,
                  vertical: -3,
                ),
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
      ),
    );

    // Accounting deliberately bypasses AppEntityPage. The module shell already
    // owns the route-level header and provides a tight viewport. Keeping the
    // accounting command rail, section strip and active section in this single
    // root Column guarantees that the active section receives every remaining
    // pixel of both width and height instead of inheriting content-sized page
    // heuristics from the generic entity-page wrapper.
    return SizedBox.expand(
      key: const ValueKey('accounting-root-tight-viewport'),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 12, 0),
        child: Column(
          key: const ValueKey('accounting-root-full-height-column'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            commandRail,
            const SizedBox(height: 8),
            sectionStrip,
            const SizedBox(height: 8),
            Expanded(
              key: const ValueKey('accounting-active-section-expanded'),
              child: SizedBox.expand(
                key: const ValueKey('accounting-active-section-full-viewport'),
                child: KeyedSubtree(
                  key: ValueKey('accounting-active-section-$_selected'),
                  child: _sectionBody(),
                ),
              ),
            ),
          ],
        ),
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
        return CashboxPage(
          embedded: true,
          initialCashboxId: widget.initialCashboxId,
        );
      case 3:
        return const ExpensesPage(embedded: true);
      case 4:
        return const PermissionVisibility(
          permission: 'installments.view',
          child: InstallmentsPage(embedded: true),
        );
      case 5:
        return const AccountStatementPage(embedded: true);
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
        return const FixedAssetsPage(embedded: true);
      case 12:
        return const _FinancialDimensionsView();
      default:
        return const SizedBox.shrink();
    }
  }
}

class _AccountingDataViewport extends StatelessWidget {
  const _AccountingDataViewport({
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.expand(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: .72),
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _ChartOfAccountsView extends StatelessWidget {
  const _ChartOfAccountsView();

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountingController>().accounts;
    final roots = accounts.where((a) => a.parentId == null).toList();
    final activeCount = accounts.where((account) => account.isActive).length;

    final controls = LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final metrics = Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            CompactMetricPill(
              icon: Icons.account_tree_outlined,
              label: context.l10n.isArabic ? 'الحسابات' : 'Accounts',
              value: accounts.length.toString(),
            ),
            CompactMetricPill(
              icon: Icons.check_circle_outline_rounded,
              label: context.l10n.isArabic ? 'النشطة' : 'Active',
              value: activeCount.toString(),
            ),
            CompactMetricPill(
              icon: Icons.call_split_rounded,
              label: context.l10n.isArabic ? 'الجذور' : 'Root accounts',
              value: roots.length.toString(),
            ),
          ],
        );
        final add = FilledButton.icon(
          onPressed: () => showAppModuleDialog<bool>(
            context: context,
            title: 'إضافة حساب فرعي',
            builder: (_) => const _AddAccountForm(),
          ),
          style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
          icon: const Icon(Icons.add_rounded, size: 17),
          label: const AppText('إضافة حساب'),
        );
        if (compact) {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [metrics, add],
          );
        }
        return Row(
          children: [
            Expanded(child: metrics),
            const SizedBox(width: 10),
            add,
          ],
        );
      },
    );

    Widget treeViewport() {
      if (roots.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.account_tree_outlined, size: 20),
                const SizedBox(width: 8),
                AppText(
                  context.l10n.isArabic
                      ? 'لا توجد حسابات معرفة بعد.'
                      : 'No accounts have been defined yet.',
                ),
              ],
            ),
          ),
        );
      }
      return ListView(
        key: const ValueKey('accounting-chart-tree-full-height-list'),
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
        children: roots
            .map((root) => _AccountTreeNode(account: root, accounts: accounts))
            .toList(growable: false),
      );
    }

    return Column(
      key: const ValueKey('accounting-chart-full-height-column'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        controls,
        const SizedBox(height: 9),
        Expanded(child: _AccountingDataViewport(child: treeViewport())),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: .55),
          ),
        ),
      ),
      child: ExpansionTile(
        initiallyExpanded: account.parentId == null,
        dense: true,
        visualDensity: const VisualDensity(vertical: -2),
        tilePadding: const EdgeInsetsDirectional.fromSTEB(8, 0, 3, 0),
        childrenPadding: const EdgeInsets.only(bottom: 2),
        shape: const Border(),
        collapsedShape: const Border(),
        leading: const Icon(Icons.account_balance_outlined, size: 19),
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
                      padding: const EdgeInsetsDirectional.only(start: 14),
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
  String? _cashAccountId;
  String? _branchId;
  String? _costCenterId;
  List<Map<String, Object?>> _branches = const [];
  List<Map<String, Object?>> _costCenters = const [];
  List<Map<String, Object?>> _cashboxes = const [];
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
      _cashAccountId = null;
      _future = _initialize();
    }
  }

  Future<List<Map<String, Object?>>> _initialize() async {
    final repository = ProfessionalAccountingRepository();
    final results = await Future.wait<List<Map<String, Object?>>>([
      repository.getBranches(),
      repository.getCostCenters(),
      if (widget.type == _AccountingReportType.cashFlow)
        repository.getCashFlowCashboxes(),
    ]);
    final cashboxes = results.length > 2
        ? results[2]
        : const <Map<String, Object?>>[];
    if (mounted) {
      setState(() {
        _branches = results[0];
        _costCenters = results[1];
        _cashboxes = cashboxes;
        if (_cashAccountId != null &&
            !_cashboxes.any((row) => row['id']?.toString() == _cashAccountId)) {
          _cashAccountId = null;
        }
      });
    } else {
      _branches = results[0];
      _costCenters = results[1];
      _cashboxes = cashboxes;
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

        final controls = _buildReportControls(rows);

        Widget reportViewport;
        if (snapshot.connectionState == ConnectionState.waiting) {
          reportViewport = Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  AppText(
                    context.l10n.isArabic
                        ? 'جارٍ تحميل التقرير...'
                        : 'Loading report...',
                  ),
                ],
              ),
            ),
          );
        } else if (snapshot.hasError) {
          reportViewport = Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
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
            ),
          );
        } else if (rows.isEmpty) {
          reportViewport = Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: AppText(
                context.l10n.isArabic
                    ? 'لا توجد بيانات متاحة ضمن المرشحات الحالية.'
                    : 'No data is available for the current filters.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        } else {
          final table = widget.type == _AccountingReportType.trialBalance
              ? _compactTrialBalanceTable(rows)
              : widget.type == _AccountingReportType.generalLedger ||
                    widget.type == _AccountingReportType.cashFlow
              ? _accountHierarchyGroupedTable(rows)
              : SingleChildScrollView(
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
                );

          reportViewport = SingleChildScrollView(
            key: ValueKey('${widget.type.name}-full-height-report-scroll'),
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 14),
            child: table,
          );
        }

        final content = <Widget>[
          controls,
          const SizedBox(height: 10),
          if (rows.isNotEmpty &&
              snapshot.connectionState != ConnectionState.waiting &&
              !snapshot.hasError) ...[
            _summary(rows),
            const SizedBox(height: 10),
          ],
        ];

        return Column(
          key: ValueKey('${widget.type.name}-full-height-report-column'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...content,
            Expanded(child: _AccountingDataViewport(child: reportViewport)),
            const SizedBox(height: 4),
          ],
        );
      },
    );
  }

  Widget _buildReportControls(List<Map<String, Object?>> rows) {
    final ar = context.l10n.isArabic;
    final controls = <Widget>[
      _reportField(
        'currencyFilter',
        SizedBox(
          width: 150,
          child: DropdownButtonFormField<String>(
            initialValue: _currency,
            isExpanded: true,
            decoration: InputDecoration(
              isDense: true,
              labelText: ar ? 'العملة' : 'Currency',
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(
                value: 'ALL',
                child: AppText(ar ? 'كل العملات' : 'All currencies'),
              ),
              const DropdownMenuItem(value: 'USD', child: AppText('USD')),
              const DropdownMenuItem(value: 'IQD', child: AppText('IQD')),
            ],
            onChanged: (value) {
              if (value != null) {
                _currency = value;
                _refresh();
              }
            },
          ),
        ),
      ),
      if (widget.type == _AccountingReportType.cashFlow)
        _reportField(
          'cashboxFilter',
          SizedBox(
            width: 210,
            child: DropdownButtonFormField<String?>(
              key: ValueKey('cash-flow-cashbox-${_cashAccountId ?? 'all'}'),
              initialValue: _cashAccountId,
              isExpanded: true,
              decoration: InputDecoration(
                isDense: true,
                labelText: ar ? 'الصندوق' : 'Cashbox',
                border: const OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<String?>>[
                DropdownMenuItem<String?>(
                  value: null,
                  child: AppText(ar ? 'كل الصناديق' : 'All cashboxes'),
                ),
                ..._cashboxes.map(
                  (row) => DropdownMenuItem<String?>(
                    value: row['id']?.toString(),
                    child: AppText(
                      '${row['name'] ?? row['id'] ?? ''} • ${row['currency'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: (value) {
                _cashAccountId = value;
                _refresh();
              },
            ),
          ),
        ),
      SizedBox(
        width: 170,
        child: DropdownButtonFormField<String?>(
          initialValue: _branchId,
          isExpanded: true,
          decoration: InputDecoration(
            isDense: true,
            labelText: ar ? 'الفرع' : 'Branch',
            border: const OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: AppText(ar ? 'كل الفروع' : 'All branches'),
            ),
            ..._branches.map(
              (row) => DropdownMenuItem<String?>(
                value: row['id']?.toString(),
                child: AppText(
                  (row['nameAr'] ?? row['name'] ?? row['code']).toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: (value) {
            _branchId = value;
            _refresh();
          },
        ),
      ),
      SizedBox(
        width: 190,
        child: DropdownButtonFormField<String?>(
          initialValue: _costCenterId,
          isExpanded: true,
          decoration: InputDecoration(
            isDense: true,
            labelText: ar ? 'مركز الكلفة' : 'Cost center',
            border: const OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: AppText(ar ? 'كل مراكز الكلفة' : 'All cost centers'),
            ),
            ..._costCenters.map(
              (row) => DropdownMenuItem<String?>(
                value: row['id']?.toString(),
                child: AppText(
                  '${row['code']} - ${(row['nameAr'] ?? row['nameEn'] ?? '').toString()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: (value) {
            _costCenterId = value;
            _refresh();
          },
        ),
      ),
      _reportField(
        'dateRange',
        OutlinedButton.icon(
          onPressed: _pickRange,
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            minimumSize: const Size(150, 44),
          ),
          icon: const Icon(Icons.date_range_outlined, size: 18),
          label: AppText(
            context.l10n.isArabic
                ? (_fromDate == null ? 'كل الفترات' : _rangeLabel)
                : (_fromDate == null ? 'All periods' : _exportRangeLabel),
            maxLines: 1,
          ),
        ),
      ),
      if (_fromDate != null)
        _reportField(
          'dateRange',
          IconButton.outlined(
            onPressed: () {
              _fromDate = null;
              _toDate = null;
              _refresh();
            },
            tooltip: ar ? 'مسح الفترة' : 'Clear period',
            icon: const Icon(Icons.clear_rounded, size: 18),
          ),
        ),
      _reportField(
        'exportExcel',
        FilledButton.icon(
          key: widget.type == _AccountingReportType.generalLedger
              ? const ValueKey('export-general-ledger-excel')
              : ValueKey('export-${widget.type.name}-excel'),
          onPressed: rows.isEmpty ? null : () => _exportReport(rows),
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            minimumSize: const Size(142, 44),
          ),
          icon: const Icon(Icons.table_view_outlined, size: 18),
          label: AppText(ar ? 'Excel كامل' : 'Full Excel'),
        ),
      ),
      _reportField(
        'exportPdf',
        OutlinedButton.icon(
          onPressed: rows.isEmpty ? null : () => _printReport(rows),
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            minimumSize: const Size(116, 44),
          ),
          icon: const Icon(Icons.print_outlined, size: 18),
          label: AppText(ar ? 'طباعة PDF' : 'Print PDF'),
        ),
      ),
      _reportField(
        'exportPdf',
        OutlinedButton.icon(
          onPressed: rows.isEmpty ? null : () => _downloadReport(rows),
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            minimumSize: const Size(126, 44),
          ),
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: AppText(ar ? 'تنزيل PDF' : 'Download PDF'),
        ),
      ),
      IconButton.outlined(
        onPressed: _refresh,
        tooltip: ar ? 'تحديث' : 'Refresh',
        icon: const Icon(Icons.refresh_rounded, size: 19),
      ),
    ];

    return LayoutBuilder(
      key: ValueKey('${widget.type.name}-horizontal-report-toolbar'),
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        if (!wide) {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: controls,
          );
        }
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(
            context,
          ).copyWith(scrollbars: false, overscroll: false),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < controls.length; index++) ...[
                  controls[index],
                  if (index != controls.length - 1) const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _compactTrialBalanceTable(List<Map<String, Object?>> rows) {
    final ar = context.l10n.isArabic;
    int depthOf(Map<String, Object?> row) {
      final value = row['hierarchyDepth'];
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    Widget amountCell(Map<String, Object?> row, String key) =>
        AppText(_format(row[key]), maxLines: 1, textAlign: TextAlign.end);
    Widget groupedHeader(
      String groupAr,
      String groupEn,
      String sideAr,
      String sideEn,
    ) => Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        AppText(
          ar ? groupAr : groupEn,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
        ),
        AppText(
          ar ? sideAr : sideEn,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    return SingleChildScrollView(
      key: const ValueKey('trial-balance-compact-table-horizontal-scroll'),
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 54,
        dataRowMinHeight: 40,
        dataRowMaxHeight: 44,
        horizontalMargin: 12,
        columnSpacing: 22,
        columns: [
          DataColumn(label: AppText(ar ? 'الحساب' : 'Account')),
          DataColumn(label: AppText(ar ? 'العملة' : 'Currency')),
          DataColumn(
            label: groupedHeader('الافتتاحي', 'Opening', 'مدين', 'Debit'),
            numeric: true,
          ),
          DataColumn(
            label: groupedHeader('الافتتاحي', 'Opening', 'دائن', 'Credit'),
            numeric: true,
          ),
          DataColumn(
            label: groupedHeader('الحركة', 'Period', 'مدين', 'Debit'),
            numeric: true,
          ),
          DataColumn(
            label: groupedHeader('الحركة', 'Period', 'دائن', 'Credit'),
            numeric: true,
          ),
          DataColumn(
            label: groupedHeader('الختامي', 'Closing', 'مدين', 'Debit'),
            numeric: true,
          ),
          DataColumn(
            label: groupedHeader('الختامي', 'Closing', 'دائن', 'Credit'),
            numeric: true,
          ),
        ],
        rows: rows
            .map(
              (row) => DataRow(
                cells: [
                  DataCell(
                    SizedBox(
                      width: 310,
                      child: Row(
                        children: [
                          SizedBox(width: depthOf(row) * 14.0),
                          const Icon(Icons.account_balance_outlined, size: 16),
                          const SizedBox(width: 7),
                          Expanded(
                            child: AppText(
                              '${ErpDisplayFormatter.accountCode(row['accountCode'])} — ${(row['accountName'] ?? '').toString()}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  DataCell(AppText((row['currency'] ?? '').toString())),
                  DataCell(amountCell(row, 'openingDebit')),
                  DataCell(amountCell(row, 'openingCredit')),
                  DataCell(amountCell(row, 'periodDebit')),
                  DataCell(amountCell(row, 'periodCredit')),
                  DataCell(amountCell(row, 'closingDebit')),
                  DataCell(amountCell(row, 'closingCredit')),
                ],
              ),
            )
            .toList(growable: false),
      ),
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
      if (cashIn > 0) return 'cashIn';
      if (cashOut > 0) return 'cashOut';
      return 'unclassified';
    }

    final grouped = <String, Map<String, List<Map<String, Object?>>>>{};
    final samples = <String, Map<String, Object?>>{};
    for (final row in rows) {
      final section = sectionFor(row);
      if (section == 'unclassified') continue;
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
              'netCashFlow',
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

    return LayoutBuilder(
      key: ValueKey('${widget.type.name}-responsive-summary-grid'),
      builder: (context, constraints) {
        const gap = 8.0;
        const minWidth = 190.0;
        final columns = ((constraints.maxWidth + gap) / (minWidth + gap))
            .floor()
            .clamp(1, 6);
        final width = (constraints.maxWidth - ((columns - 1) * gap)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: values
              .map(
                (item) => _reportValue(
                  item.$1,
                  SizedBox(
                    width: width,
                    child: CompactMetricPill(
                      icon: switch (item.$1) {
                        'totalDebit' => Icons.south_west_rounded,
                        'totalCredit' => Icons.north_east_rounded,
                        'cashIn' => Icons.call_received_rounded,
                        'cashOut' => Icons.call_made_rounded,
                        'trialBalance' => Icons.balance_outlined,
                        _ => Icons.analytics_outlined,
                      },
                      label: item.$2,
                      value: _number(item.$3),
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
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
        'cashAccountId': 'Cashbox',
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
  Future<List<Map<String, Object?>>> _load() async {
    return ProfessionalAccountingRepository().loadReport(
      type: widget.type.name,
      currency: _currency,
      cashAccountId: widget.type == _AccountingReportType.cashFlow
          ? _cashAccountId
          : null,
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
        'cashAccountId': 'الصندوق',
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

        final bodyChildren = <Widget>[
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
        ];

        return Column(
          key: const ValueKey('financial-dimensions-full-height-column'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppText(
              'الفروع ومراكز الكلفة',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 3),
            const AppText(
              'إدارة الأبعاد المستخدمة لتصفية التقارير وتوزيع القيود والمستندات المالية.',
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _AccountingDataViewport(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
                child: ListView(children: bodyChildren),
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

bool trialBalanceRowIsConsistent(
  Map<String, Object?> row, {
  double tolerance = 0.01,
}) {
  double number(String key) {
    final value = row[key];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  final opening = number('openingDebit') - number('openingCredit');
  final period = number('periodDebit') - number('periodCredit');
  final closing = number('closingDebit') - number('closingCredit');
  return (opening + period - closing).abs() <= tolerance;
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
