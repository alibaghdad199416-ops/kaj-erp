import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/exporting/excel_export_service.dart';
import 'package:quality_line_erp/core/exporting/export_document.dart';
import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/utils/erp_display_formatter.dart';
import 'package:quality_line_erp/core/utils/thousands_input_formatter.dart';
import 'package:quality_line_erp/core/widgets/app_dialog.dart';
import 'package:quality_line_erp/core/widgets/app_module_dialog.dart';
import 'package:quality_line_erp/core/widgets/app_responsive.dart';
import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';
import 'package:quality_line_erp/core/widgets/unified_document_details_dialog.dart';
import 'package:quality_line_erp/design_system/kaj_finance_stage7_components.dart';
import 'package:quality_line_erp/features/accounting/cashbox/controllers/cashbox_controller.dart';
import 'package:quality_line_erp/features/accounting/cashbox/models/cash_account_model.dart';
import 'package:quality_line_erp/features/accounting/cashbox/models/cash_transaction_filter.dart';
import 'package:quality_line_erp/features/accounting/cashbox/models/cash_transaction_model.dart';
import 'package:quality_line_erp/features/accounting/cashbox/models/cashbox_workspace_metrics.dart';
import 'package:quality_line_erp/features/accounting/cashbox/services/cash_voucher_pdf_service.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'add_cash_transaction_page.dart';
import 'cash_account_form.dart';

class CashboxPage extends StatefulWidget {
  const CashboxPage({
    super.key,
    this.embedded = false,
    this.continuous = false,
    this.initialCashboxId,
  });

  final bool embedded;
  final bool continuous;
  final String? initialCashboxId;

  @override
  State<CashboxPage> createState() => _CashboxPageState();
}

class _CashboxPageState extends State<CashboxPage> {
  bool get ar => context.l10n.isArabic;
  String t(String arabic, String english) => ar ? arabic : english;

  Widget _securedCashboxField(String field, Widget child) =>
      FieldPermissionControl(
        resource: 'cashbox',
        field: field,
        viewPermission: 'accounting.view',
        writePermission: 'accounting.update',
        child: child,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final controller = context.read<CashboxController>();
      await controller.loadTransactions();
      if (!mounted) return;
      final id = widget.initialCashboxId?.trim();
      if (id == null || id.isEmpty) return;
      for (final account in controller.cashAccounts) {
        if (account.id == id) {
          await _openCashboxDetail(account);
          break;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = Consumer<CashboxController>(
      builder: (context, controller, _) {
        if (controller.isLoading && controller.cashAccounts.isEmpty) {
          return Center(
            child: KajFinanceState(
              icon: Icons.sync_rounded,
              title: t('جارٍ مزامنة الصناديق', 'Synchronizing cashboxes'),
              message: t(
                'يتم تحميل الصناديق والأرصدة المرتبطة.',
                'Loading cashboxes and linked balances.',
              ),
            ),
          );
        }
        if (controller.errorMessage != null &&
            controller.cashAccounts.isEmpty) {
          return Center(
            child: KajFinanceState(
              icon: Icons.error_outline_rounded,
              title: t('تعذر تحميل الصناديق', 'Unable to load cashboxes'),
              message: controller.errorMessage!,
            ),
          );
        }
        final body = ListView(
          shrinkWrap: widget.continuous,
          physics: widget.continuous
              ? const NeverScrollableScrollPhysics()
              : const AlwaysScrollableScrollPhysics(),
          padding: widget.embedded
              ? const EdgeInsets.fromLTRB(0, 0, 0, 24)
              : const EdgeInsets.all(16),
          children: <Widget>[
            if (!widget.embedded) ...[_header(), const SizedBox(height: 12)],
            _cashAccounts(controller),
          ],
        );
        return RefreshIndicator(
          onRefresh: controller.loadTransactions,
          child: body,
        );
      },
    );
    return Directionality(
      textDirection: Directionality.of(context),
      child: widget.embedded
          ? content
          : Scaffold(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              body: content,
            ),
    );
  }

  Widget _header() {
    final access = context.read<AccessController>();
    final canTransfer = access.canPerformAction(
      'cashbox',
      'transfer',
      legacyPermission: 'accounting.update',
    );
    return KajFinanceSection(
      title: t('الصناديق والحسابات النقدية', 'Cashboxes & Cash Accounts'),
      subtitle: t(
        'مساحات عمل مالية موحدة للحركة والرصيد والتحليل.',
        'Unified financial workspaces for movement, balance and analysis.',
      ),
      icon: Icons.account_balance_wallet_outlined,
      trailing: Wrap(
        spacing: 4,
        children: <Widget>[
          if (canTransfer)
            IconButton(
              tooltip: t('تحويل بين الصناديق', 'Transfer between cashboxes'),
              onPressed: _openTransfer,
              icon: const Icon(Icons.swap_horiz_rounded),
            ),
          if (access.canPerformAction(
            'cashbox',
            'account.create',
            legacyPermission: 'accounting.create',
          ))
            IconButton(
              tooltip: t('صندوق جديد', 'New cashbox'),
              onPressed: () => _editCashAccount(null),
              icon: const Icon(Icons.add_rounded),
            ),
        ],
      ),
      child: const SizedBox.shrink(),
    );
  }

  Widget _cashAccounts(CashboxController controller) {
    final scheme = Theme.of(context).colorScheme;
    if (controller.cashAccounts.isEmpty) {
      return KajFinanceState(
        icon: Icons.account_balance_wallet_outlined,
        title: t('لا توجد صناديق نقدية', 'No cashboxes'),
        message: t(
          'أنشئ صندوقًا نقديًا لبدء تسجيل الحركات.',
          'Create a cashbox to start recording transactions.',
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        const minWidth = 300.0;
        final columns = ((constraints.maxWidth + gap) / (minWidth + gap))
            .floor()
            .clamp(1, 4);
        final width = (constraints.maxWidth - ((columns - 1) * gap)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: controller.cashAccounts.map((account) {
            final transactions = controller.transactionsForCashbox(
              account.id,
              criteria: const UnifiedFilterCriteria(),
            );
            final metrics = CashboxWorkspaceMetrics.fromTransactions(
              account,
              transactions,
            );
            final reconciliation = controller.reconciliation[account.id];
            final difference = reconciliation?['difference'] ?? 0;
            final access = context.read<AccessController>();
            final canEdit = access.canPerformAction(
              'cashbox',
              'account.edit',
              legacyPermission: 'accounting.update',
            );
            return SizedBox(
              width: width,
              child: Material(
                color: scheme.surface,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: scheme.outlineVariant),
                ),
                child: InkWell(
                  onTap: () => _openCashboxDetail(account),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(
                              account.type == 'bank'
                                  ? Icons.account_balance_outlined
                                  : Icons.account_balance_wallet_outlined,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FieldPermissionVisibility(
                                resource: 'cashbox',
                                field: 'name',
                                viewPermission: 'accounting.view',
                                child: AppText(
                                  account.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                            FieldPermissionVisibility(
                              resource: 'cashbox',
                              field: 'currency',
                              viewPermission: 'accounting.view',
                              child: AppText(
                                ErpDisplayFormatter.normalizeCurrency(
                                  account.currency,
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (canEdit)
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: t('تعديل الصندوق', 'Edit cashbox'),
                                onPressed: () => _editCashAccount(account),
                                icon: const Icon(Icons.edit_outlined, size: 18),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        FieldPermissionVisibility(
                          resource: 'cashbox',
                          field: 'balance',
                          viewPermission: 'accounting.view',
                          child: AppText(
                            ErpDisplayFormatter.formatMoney(
                              metrics.currentBalance,
                              account.currency,
                            ),
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(height: 8),
                        FieldPermissionVisibility(
                          resource: 'cashbox',
                          field: 'amount',
                          viewPermission: 'accounting.view',
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: _miniValue(
                                  t('الداخل', 'Cash In'),
                                  metrics.cashIn,
                                  account.currency,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _miniValue(
                                  t('الخارج', 'Cash Out'),
                                  metrics.cashOut,
                                  account.currency,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 9),
                        _CashboxMovementChart(
                          transactions: transactions,
                          currency: account.currency,
                          compact: true,
                        ),
                        const SizedBox(height: 6),
                        FieldPermissionVisibility(
                          resource: 'cashbox',
                          field: 'reconciliationDifference',
                          viewPermission: 'accounting.view',
                          child: AppText(
                            difference.abs() <= .01
                                ? t(
                                    'مطابق مع دفتر الأستاذ',
                                    'Reconciled with general ledger',
                                  )
                                : t(
                                    'فرق المطابقة: ${ErpDisplayFormatter.formatMoney(difference, account.currency)}',
                                    'Reconciliation difference: ${ErpDisplayFormatter.formatMoney(difference, account.currency)}',
                                  ),
                            style: TextStyle(
                              fontSize: 10.5,
                              color: difference.abs() <= .01
                                  ? Colors.green.shade700
                                  : scheme.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(growable: false),
        );
      },
    );
  }

  Widget _miniValue(String label, double value, String currency) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      AppText(label, style: Theme.of(context).textTheme.labelSmall),
      AppText(
        ErpDisplayFormatter.formatMoney(value, currency),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
      ),
    ],
  );

  Future<void> _openCashboxDetail(CashAccountModel account) async {
    if (!await _requireCashboxAction(
      'transaction.view',
      legacyPermission: 'accounting.view',
    )) {
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: '/accounting/cashboxes/${account.id}'),
        builder: (_) => _CashboxWorkspaceScreen(account: account),
      ),
    );
  }

  Future<void> _editCashAccount(CashAccountModel? account) async {
    final changed = await showAppWorkspaceDialogBuilder<bool>(
      context: context,
      barrierDismissible: true,
      useRootNavigator: true,
      builder: (_) => CashAccountForm(account: account),
    );
    if (changed == true && mounted) {
      await context.read<CashboxController>().loadTransactions();
    }
  }

  Future<bool> _requireCashboxAction(
    String action, {
    required String legacyPermission,
  }) async {
    final access = context.read<AccessController>();
    if (access.canPerformAction(
      'cashbox',
      action,
      legacyPermission: legacyPermission,
    )) {
      return true;
    }
    await access.recordDeniedAccess('cashbox.$action');
    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: AppText(
          t(
            'ليس لديك صلاحية لتنفيذ هذه العملية.',
            'You do not have permission to perform this action.',
          ),
        ),
      ),
    );
    return false;
  }

  Future<void> _openTransfer() async {
    if (!await _requireCashboxAction(
      'transfer',
      legacyPermission: 'accounting.update',
    )) {
      return;
    }
    if (!mounted) return;
    final controller = context.read<CashboxController>();
    final accounts = controller.cashAccounts
        .where((account) => account.isActive)
        .toList(growable: false);
    if (accounts.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            t(
              'يجب إنشاء صندوقين فعالين على الأقل.',
              'Create at least two active cashboxes.',
            ),
          ),
        ),
      );
      return;
    }

    String fromId = accounts.first.id;
    String toId = accounts[1].id;
    final source = TextEditingController();
    final target = TextEditingController();
    final rate = TextEditingController(text: '1');
    final notes = TextEditingController();
    final key = GlobalKey<FormState>();
    DateTime transferDate = DateTime.now();

    CashAccountModel byId(String id) =>
        accounts.firstWhere((account) => account.id == id);
    CashAccountModel? linked(CashAccountModel sourceAccount) {
      final linkedId = sourceAccount.linkedCashAccountId?.trim();
      if (linkedId == null || linkedId.isEmpty) return null;
      for (final account in accounts) {
        if (account.id == linkedId &&
            account.currency.toUpperCase() !=
                sourceAccount.currency.toUpperCase()) {
          return account;
        }
      }
      return null;
    }

    List<CashAccountModel> targetsFor(CashAccountModel sourceAccount) {
      final configured = linked(sourceAccount);
      return accounts.where((account) {
        if (account.id == sourceAccount.id) return false;
        if (account.currency.toUpperCase() ==
            sourceAccount.currency.toUpperCase()) {
          return true;
        }
        return configured != null && account.id == configured.id;
      }).toList(growable: false);
    }

    void normalizeTarget() {
      final targets = targetsFor(byId(fromId));
      if (targets.isEmpty) return;
      if (!targets.any((account) => account.id == toId)) {
        toId = linked(byId(fromId))?.id ?? targets.first.id;
      }
    }

    void calculate() {
      normalizeTarget();
      final from = byId(fromId);
      final to = byId(toId);
      final same = from.currency.toUpperCase() == to.currency.toUpperCase();
      if (same) rate.text = '1';
      final sourceValue = double.tryParse(source.text.replaceAll(',', '')) ?? 0;
      final rateValue = same
          ? 1.0
          : (double.tryParse(rate.text.replaceAll(',', '')) ?? 0);
      target.text = sourceValue > 0 && rateValue > 0
          ? (sourceValue * rateValue).toStringAsFixed(2)
          : '';
    }

    try {
      final saved = await showAppWorkspaceDialogBuilder<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            normalizeTarget();
            final from = byId(fromId);
            final to = byId(toId);
            final targets = targetsFor(from);
            final same = from.currency.toUpperCase() == to.currency.toUpperCase();
            return AlertDialog(
              title: AppText(t('تحويل بين الصناديق', 'Cashbox transfer')),
              content: Form(
                key: key,
                child: SizedBox(
                  width: AppResponsive.dialogWidth(context, 560),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _securedCashboxField(
                          'transferFrom',
                          DropdownButtonFormField<String>(
                            initialValue: fromId,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: t('من صندوق', 'From cashbox'),
                            ),
                            items: accounts
                                .map(
                                  (account) => DropdownMenuItem<String>(
                                    value: account.id,
                                    child: AppText(
                                      '${account.name} (${account.currency})',
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: (value) {
                              if (value == null) return;
                              setDialogState(() {
                                fromId = value;
                                normalizeTarget();
                                calculate();
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 10),
                        _securedCashboxField(
                          'transferTo',
                          DropdownButtonFormField<String>(
                            key: ValueKey<String>('target:$fromId:$toId'),
                            initialValue: toId,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: t('إلى صندوق', 'To cashbox'),
                            ),
                            items: targets
                                .map(
                                  (account) => DropdownMenuItem<String>(
                                    value: account.id,
                                    child: AppText(
                                      '${account.name} (${account.currency})',
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: (value) {
                              if (value == null) return;
                              setDialogState(() {
                                toId = value;
                                calculate();
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 10),
                        _securedCashboxField(
                          'amount',
                          TextFormField(
                            controller: source,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: <TextInputFormatter>[
                              ThousandsInputFormatter(decimalDigits: 2),
                            ],
                            decoration: InputDecoration(
                              labelText: t(
                                'المبلغ الخارج (${from.currency})',
                                'Source amount (${from.currency})',
                              ),
                            ),
                            validator: _positiveAmount,
                            onChanged: (_) => setDialogState(calculate),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _securedCashboxField(
                          'exchangeRate',
                          TextFormField(
                            controller: rate,
                            enabled: !same,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: <TextInputFormatter>[
                              ThousandsInputFormatter(decimalDigits: 20),
                            ],
                            decoration: InputDecoration(
                              labelText: t(
                                'سعر التحويل: ${to.currency} لكل ${from.currency}',
                                'Conversion rate: ${to.currency} per ${from.currency}',
                              ),
                            ),
                            validator: _positiveAmount,
                            onChanged: (_) => setDialogState(calculate),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _securedCashboxField(
                          'amount',
                          TextFormField(
                            controller: target,
                            readOnly: true,
                            decoration: InputDecoration(
                              labelText: t(
                                'المبلغ الداخل (${to.currency})',
                                'Target amount (${to.currency})',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _securedCashboxField(
                          'operationalDate',
                          OutlinedButton.icon(
                            onPressed: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: transferDate,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (date == null || !context.mounted) return;
                              final time = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.fromDateTime(transferDate),
                              );
                              if (!context.mounted) return;
                              final selected =
                                  time ?? TimeOfDay.fromDateTime(transferDate);
                              setDialogState(() {
                                transferDate = DateTime(
                                  date.year,
                                  date.month,
                                  date.day,
                                  selected.hour,
                                  selected.minute,
                                );
                              });
                            },
                            icon: const Icon(Icons.event_available_outlined),
                            label: AppText(
                              ErpDisplayFormatter.formatDateTime(transferDate),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _securedCashboxField(
                          'notes',
                          TextField(
                            controller: notes,
                            maxLines: 2,
                            decoration: InputDecoration(
                              labelText: t('ملاحظات', 'Notes'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: AppText(t('إلغاء', 'Cancel')),
                ),
                FilledButton.icon(
                  onPressed: () {
                    calculate();
                    if (key.currentState?.validate() == true &&
                        target.text.isNotEmpty) {
                      Navigator.pop(dialogContext, true);
                    }
                  },
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: AppText(t('تنفيذ التحويل', 'Transfer funds')),
                ),
              ],
            );
          },
        ),
      );
      if (saved != true || !mounted) return;
      calculate();
      final from = byId(fromId);
      final to = byId(toId);
      final same = from.currency.toUpperCase() == to.currency.toUpperCase();
      if (!same && linked(from)?.id != to.id) {
        throw StateError(
          t(
            'الصندوق الوجهة ليس الرابط المحدد للصندوق المصدر.',
            'The destination is not the configured linked cashbox.',
          ),
        );
      }
      await controller.transferBetweenAccounts(
        fromAccountId: fromId,
        toAccountId: toId,
        sourceAmount: double.parse(source.text.replaceAll(',', '')),
        targetAmount: double.parse(target.text.replaceAll(',', '')),
        exchangeRate: same
            ? 1
            : double.parse(rate.text.replaceAll(',', '')),
        transferDate: transferDate,
        notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: AppText(userFacingError(error, isArabic: ar))),
      );
    } finally {
      source.dispose();
      target.dispose();
      rate.dispose();
      notes.dispose();
    }
  }

  String? _positiveAmount(String? value) {
    final parsed = double.tryParse((value ?? '').replaceAll(',', ''));
    if (parsed != null && parsed > 0) return null;
    return t('أدخل قيمة أكبر من صفر', 'Enter a value greater than zero');
  }
}

class _CashboxWorkspaceScreen extends StatefulWidget {
  const _CashboxWorkspaceScreen({required this.account});
  final CashAccountModel account;

  @override
  State<_CashboxWorkspaceScreen> createState() =>
      _CashboxWorkspaceScreenState();
}

class _CashboxWorkspaceScreenState extends State<_CashboxWorkspaceScreen> {
  final _search = TextEditingController();
  Timer? _searchDebounce;
  bool _initialized = false;

  bool get ar => context.l10n.isArabic;
  String t(String arabic, String english) => ar ? arabic : english;

  Widget _secured(String field, Widget child) => FieldPermissionControl(
    resource: 'cashbox',
    field: field,
    viewPermission: 'accounting.view',
    writePermission: 'accounting.update',
    child: child,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final controller = context.read<CashboxController>();
    _search.text = controller.transactionFilter.searchText;
    if (controller.transactionFilter.sort == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final current = context.read<CashboxController>();
        if (current.transactionFilter.sort == null) {
          current.setTransactionFilter(
            current.transactionFilter.copyWith(
              sort: const UnifiedSortSpec(
                'date',
                direction: UnifiedSortDirection.descending,
              ),
            ),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CashboxController>(
      builder: (context, controller, _) {
        final criteria = controller.transactionFilter;
        final transactions = controller.transactionsForCashbox(widget.account.id);
        final metrics = CashboxWorkspaceMetrics.fromTransactions(
          widget.account,
          transactions,
        );
        final access = context.read<AccessController>();
        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: <Widget>[
                const Icon(Icons.account_balance_wallet_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: AppText(
                    '${widget.account.name} • ${ErpDisplayFormatter.normalizeCurrency(widget.account.currency)}',
                  ),
                ),
              ],
            ),
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _summary(metrics),
                  const SizedBox(height: 10),
                  _actions(access, controller, transactions),
                  const SizedBox(height: 10),
                  _queryToolbar(controller, criteria),
                  if (criteria.activeFilterKeys.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 7),
                    _activeFilterChips(controller, criteria),
                  ],
                  const SizedBox(height: 10),
                  FieldPermissionVisibility(
                    resource: 'cashbox',
                    field: 'amount',
                    viewPermission: 'accounting.view',
                    child: _CashboxMovementChart(
                      transactions: transactions,
                      currency: widget.account.currency,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: transactions.isEmpty
                        ? KajFinanceState(
                            icon: Icons.receipt_long_outlined,
                            title: t(
                              'لا توجد حركات مطابقة',
                              'No matching transactions',
                            ),
                            message: t(
                              'عدّل البحث أو الفلاتر، أو أنشئ حركة جديدة.',
                              'Adjust search or filters, or create a transaction.',
                            ),
                          )
                        : _transactionTable(controller, transactions),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _summary(CashboxWorkspaceMetrics metrics) {
    final values = <(String, double, IconData)>[
      (
        t('الرصيد الافتتاحي', 'Opening Balance'),
        metrics.openingBalance,
        Icons.flag_outlined,
      ),
      (t('الداخل', 'Cash In'), metrics.cashIn, Icons.south_west_rounded),
      (t('الخارج', 'Cash Out'), metrics.cashOut, Icons.north_east_rounded),
      (
        t('صافي الحركة', 'Net Movement'),
        metrics.netMovement,
        Icons.swap_vert_rounded,
      ),
      (
        t('الرصيد الحالي', 'Current Balance'),
        metrics.currentBalance,
        Icons.account_balance_wallet_outlined,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 1100
            ? (constraints.maxWidth - 32) / 5
            : constraints.maxWidth >= 700
            ? (constraints.maxWidth - 16) / 3
            : (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: values
              .map(
                (item) => SizedBox(
                  width: width,
                  child: _metricCard(item.$1, item.$2, item.$3),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }

  Widget _metricCard(String label, double value, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 17, color: scheme.primary),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AppText(label, style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 2),
                AppText(
                  ErpDisplayFormatter.formatMoney(
                    value,
                    widget.account.currency,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions(
    AccessController access,
    CashboxController controller,
    List<CashTransactionModel> transactions,
  ) {
    final canReceive = access.canPerformAction(
      'cashbox',
      'receipt',
      legacyPermission: 'cashbox.receipt',
    );
    final canPay = access.canPerformAction(
      'cashbox',
      'payment',
      legacyPermission: 'cashbox.payment',
    );
    final canEdit = access.canPerformAction(
      'cashbox',
      'account.edit',
      legacyPermission: 'accounting.update',
    );
    final canExport = access.canPerformAction(
      'cashbox',
      'transaction.export',
      legacyPermission: 'accounting.view',
    );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        if (canReceive)
          FilledButton.icon(
            onPressed: () => _openAdd('receipt'),
            icon: const Icon(Icons.south_west_rounded, size: 17),
            label: AppText(t('سند قبض', 'Cash In')),
          ),
        if (canPay)
          OutlinedButton.icon(
            onPressed: () => _openAdd('payment'),
            icon: const Icon(Icons.north_east_rounded, size: 17),
            label: AppText(t('سند صرف', 'Cash Out')),
          ),
        if (canEdit)
          OutlinedButton.icon(
            onPressed: _editAccount,
            icon: const Icon(Icons.edit_outlined, size: 17),
            label: AppText(t('تعديل الصندوق', 'Edit Cashbox')),
          ),
        if (canExport)
          OutlinedButton.icon(
            onPressed: transactions.isEmpty
                ? null
                : () => _export(controller, transactions),
            icon: const Icon(Icons.table_view_outlined, size: 17),
            label: AppText(t('تصدير Excel', 'Export Excel')),
          ),
      ],
    );
  }

  Widget _queryToolbar(
    CashboxController controller,
    UnifiedFilterCriteria criteria,
  ) {
    final sortValue = _sortValue(criteria.sort);
    return LayoutBuilder(
      builder: (context, constraints) {
        final search = TextField(
          controller: _search,
          onChanged: (value) {
            _searchDebounce?.cancel();
            _searchDebounce = Timer(const Duration(milliseconds: 250), () {
              if (!mounted) return;
              final current = context.read<CashboxController>();
              current.setTransactionFilter(
                current.transactionFilter.copyWith(
                  searchText: value,
                  offset: 0,
                ),
              );
            });
          },
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: t(
              'بحث في المرجع والطرف والنوع والملاحظات',
              'Search reference, partner, type or notes',
            ),
            suffixIcon: criteria.searchText.trim().isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _search.clear();
                      controller.setTransactionFilter(
                        criteria.copyWith(searchText: '', offset: 0),
                      );
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        );
        final sort = DropdownButtonFormField<String>(
          initialValue: sortValue,
          decoration: InputDecoration(labelText: t('الترتيب', 'Sort')),
          items: <DropdownMenuItem<String>>[
            DropdownMenuItem(
              value: 'date_desc',
              child: AppText(t('الأحدث أولًا', 'Newest first')),
            ),
            DropdownMenuItem(
              value: 'date_asc',
              child: AppText(t('الأقدم أولًا', 'Oldest first')),
            ),
            DropdownMenuItem(
              value: 'amount_desc',
              child: AppText(t('المبلغ: الأعلى', 'Amount: high to low')),
            ),
            DropdownMenuItem(
              value: 'amount_asc',
              child: AppText(t('المبلغ: الأدنى', 'Amount: low to high')),
            ),
            DropdownMenuItem(
              value: 'reference_asc',
              child: AppText(t('المرجع', 'Reference')),
            ),
          ],
          onChanged: (value) {
            if (value == null) return;
            controller.setTransactionFilter(
              criteria.copyWith(sort: _sortSpec(value), offset: 0),
            );
          },
        );
        final filterButton = OutlinedButton.icon(
          onPressed: () => _showFilters(controller, criteria),
          icon: const Icon(Icons.filter_alt_outlined, size: 17),
          label: AppText(
            criteria.activeFilterKeys.isEmpty
                ? t('الفلاتر', 'Filters')
                : t(
                    'الفلاتر (${criteria.activeFilterKeys.length})',
                    'Filters (${criteria.activeFilterKeys.length})',
                  ),
          ),
        );
        final clear = TextButton.icon(
          onPressed: criteria.activeFilterKeys.isEmpty
              ? null
              : () {
                  _search.clear();
                  controller.clearTransactionFilters();
                  controller.setTransactionFilter(
                    controller.transactionFilter.copyWith(
                      sort: const UnifiedSortSpec(
                        'date',
                        direction: UnifiedSortDirection.descending,
                      ),
                    ),
                  );
                },
          icon: const Icon(Icons.filter_alt_off_outlined, size: 17),
          label: AppText(t('مسح', 'Clear')),
        );
        if (constraints.maxWidth >= 900) {
          return Row(
            children: <Widget>[
              Expanded(child: search),
              const SizedBox(width: 8),
              SizedBox(width: 190, child: sort),
              const SizedBox(width: 8),
              filterButton,
              clear,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            search,
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                SizedBox(width: 190, child: sort),
                filterButton,
                clear,
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _activeFilterChips(
    CashboxController controller,
    UnifiedFilterCriteria criteria,
  ) {
    final raw = controller.transactionsForCashbox(
      widget.account.id,
      criteria: const UnifiedFilterCriteria(),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: criteria.activeFilterKeys
            .map(
              (key) => Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: InputChip(
                  label: AppText(_chipLabel(key, criteria, raw)),
                  onDeleted: () => _removeCriterion(controller, criteria, key),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  String _chipLabel(
    String key,
    UnifiedFilterCriteria criteria,
    List<CashTransactionModel> raw,
  ) {
    String values(Iterable<String> input) => input.join(', ');
    switch (key) {
      case 'searchText':
        return '${t('بحث', 'Search')}: ${criteria.searchText}';
      case 'type':
        return '${t('الاتجاه', 'Direction')}: ${values(criteria.types)}';
      case 'currency':
        return '${t('العملة', 'Currency')}: ${values(criteria.currencies)}';
      case 'user':
        return '${t('المستخدم', 'User')}: ${values(criteria.userIds)}';
      case 'partner':
        final names = criteria.partnerIds.map((id) {
          for (final transaction in raw) {
            if (transaction.partyId == id) return transaction.partyName ?? id;
          }
          return id;
        });
        return '${t('الطرف', 'Partner')}: ${values(names)}';
      case 'dateFrom':
        return '${t('من', 'From')}: ${ErpDisplayFormatter.formatDate(criteria.fromDate)}';
      case 'dateTo':
        return '${t('إلى', 'To')}: ${ErpDisplayFormatter.formatDate(criteria.toDate)}';
      case 'reference':
        return '${t('المرجع', 'Reference')}: ${values(criteria.dimensions['reference'] ?? const <String>{})}';
      case 'sourceModule':
        return '${t('المصدر', 'Source')}: ${values(criteria.dimensions['sourceModule'] ?? const <String>{})}';
      case 'paymentType':
        return '${t('طريقة الدفع', 'Payment type')}: ${values(criteria.dimensions['paymentType'] ?? const <String>{})}';
      case 'amount':
        final range = criteria.numericRanges['amount'];
        return '${t('المبلغ', 'Amount')}: ${range?.min ?? '—'} → ${range?.max ?? '—'}';
      default:
        return key;
    }
  }

  void _removeCriterion(
    CashboxController controller,
    UnifiedFilterCriteria criteria,
    String key,
  ) {
    UnifiedFilterCriteria next = criteria;
    if (key == 'searchText') {
      _search.clear();
      next = criteria.copyWith(searchText: '', offset: 0);
    } else if (key == 'type') {
      next = criteria.copyWith(types: const <String>{}, offset: 0);
    } else if (key == 'currency') {
      next = criteria.copyWith(currencies: const <String>{}, offset: 0);
    } else if (key == 'user') {
      next = criteria.copyWith(userIds: const <String>{}, offset: 0);
    } else if (key == 'partner') {
      next = criteria.copyWith(partnerIds: const <String>{}, offset: 0);
    } else if (key == 'dateFrom') {
      next = criteria.copyWith(clearFromDate: true, offset: 0);
    } else if (key == 'dateTo') {
      next = criteria.copyWith(clearToDate: true, offset: 0);
    } else if (criteria.dimensions.containsKey(key)) {
      final dimensions = <String, Set<String>>{...criteria.dimensions};
      dimensions.remove(key);
      next = criteria.copyWith(dimensions: dimensions, offset: 0);
    } else if (criteria.numericRanges.containsKey(key)) {
      final ranges = <String, UnifiedNumericRange>{...criteria.numericRanges};
      ranges.remove(key);
      next = criteria.copyWith(numericRanges: ranges, offset: 0);
    }
    controller.setTransactionFilter(next);
  }

  Future<void> _showFilters(
    CashboxController controller,
    UnifiedFilterCriteria criteria,
  ) async {
    final raw = controller.transactionsForCashbox(
      widget.account.id,
      criteria: const UnifiedFilterCriteria(),
    );
    String? type = criteria.types.length == 1 ? criteria.types.first : null;
    String? currency = criteria.currencies.length == 1
        ? criteria.currencies.first
        : null;
    String? user = criteria.userIds.length == 1 ? criteria.userIds.first : null;
    String? partner = criteria.partnerIds.length == 1
        ? criteria.partnerIds.first
        : null;
    String? reference = _single(criteria.dimensions['reference']);
    String? sourceModule = _single(criteria.dimensions['sourceModule']);
    String? paymentType = _single(criteria.dimensions['paymentType']);
    DateTime? fromDate = criteria.fromDate;
    DateTime? toDate = criteria.toDate;
    final minAmount = TextEditingController(
      text: criteria.numericRanges['amount']?.min?.toString() ?? '',
    );
    final maxAmount = TextEditingController(
      text: criteria.numericRanges['amount']?.max?.toString() ?? '',
    );

    final currencies = _values(raw.map((e) => e.currency));
    final users = _values(raw.map((e) => e.performedBy));
    final references = _values(raw.map((e) => e.referenceId));
    final sources = _values(raw.map(CashboxTransactionFilter.sourceModuleOf));
    final paymentTypes = _values(raw.map((e) => e.paymentMethod));
    final partners = <String, String>{};
    for (final transaction in raw) {
      final id = transaction.partyId?.trim();
      if (id != null && id.isNotEmpty) {
        partners[id] = transaction.partyName?.trim().isNotEmpty == true
            ? transaction.partyName!.trim()
            : id;
      }
    }

    try {
      final result = await showDialog<UnifiedFilterCriteria>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> pick(bool from) async {
              final initial = (from ? fromDate : toDate) ?? DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: initial,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked == null) return;
              setDialogState(() {
                if (from) {
                  fromDate = DateTime(picked.year, picked.month, picked.day);
                } else {
                  toDate = DateTime(
                    picked.year,
                    picked.month,
                    picked.day,
                    23,
                    59,
                    59,
                    999,
                  );
                }
              });
            }

            Widget dropdown(
              String label,
              String? value,
              List<DropdownMenuItem<String>> items,
              ValueChanged<String?> onChanged,
            ) => DropdownButtonFormField<String>(
              initialValue: value,
              isExpanded: true,
              decoration: InputDecoration(labelText: label),
              items: <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(
                  value: null,
                  child: AppText(t('الكل', 'All')),
                ),
                ...items,
              ],
              onChanged: onChanged,
            );

            return AlertDialog(
              title: AppText(t('فلاتر حركات الصندوق', 'Cashbox filters')),
              content: SizedBox(
                width: AppResponsive.dialogWidth(context, 760),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      SizedBox(
                        width: 220,
                        child: dropdown(
                          t('الاتجاه', 'Direction'),
                          type,
                          <DropdownMenuItem<String>>[
                            DropdownMenuItem(
                              value: 'receipt',
                              child: AppText(t('داخل', 'Cash In')),
                            ),
                            DropdownMenuItem(
                              value: 'payment',
                              child: AppText(t('خارج', 'Cash Out')),
                            ),
                          ],
                          (value) => setDialogState(() => type = value),
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: dropdown(
                          t('العملة', 'Currency'),
                          currency,
                          currencies
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: AppText(value),
                                ),
                              )
                              .toList(),
                          (value) => setDialogState(() => currency = value),
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: dropdown(
                          t('المستخدم', 'User'),
                          user,
                          users
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: AppText(value),
                                ),
                              )
                              .toList(),
                          (value) => setDialogState(() => user = value),
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: dropdown(
                          t('الطرف', 'Partner'),
                          partner,
                          partners.entries
                              .map(
                                (entry) => DropdownMenuItem(
                                  value: entry.key,
                                  child: AppText(entry.value),
                                ),
                              )
                              .toList(),
                          (value) => setDialogState(() => partner = value),
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: dropdown(
                          t('المرجع', 'Reference'),
                          reference,
                          references
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: AppText(value),
                                ),
                              )
                              .toList(),
                          (value) => setDialogState(() => reference = value),
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: dropdown(
                          t('الوحدة المصدرية', 'Source Module'),
                          sourceModule,
                          sources
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: AppText(value),
                                ),
                              )
                              .toList(),
                          (value) => setDialogState(() => sourceModule = value),
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: dropdown(
                          t('طريقة الدفع', 'Payment Type'),
                          paymentType,
                          paymentTypes
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: AppText(value),
                                ),
                              )
                              .toList(),
                          (value) => setDialogState(() => paymentType = value),
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: OutlinedButton.icon(
                          onPressed: () => pick(true),
                          icon: const Icon(Icons.date_range_outlined),
                          label: AppText(
                            fromDate == null
                                ? t('من تاريخ', 'Date from')
                                : ErpDisplayFormatter.formatDate(fromDate),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: OutlinedButton.icon(
                          onPressed: () => pick(false),
                          icon: const Icon(Icons.event_outlined),
                          label: AppText(
                            toDate == null
                                ? t('إلى تاريخ', 'Date to')
                                : ErpDisplayFormatter.formatDate(toDate),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: TextField(
                          controller: minAmount,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: t('أقل مبلغ', 'Minimum amount'),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: TextField(
                          controller: maxAmount,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: t('أعلى مبلغ', 'Maximum amount'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: AppText(t('إلغاء', 'Cancel')),
                ),
                FilledButton(
                  onPressed: () {
                    final dimensions = <String, Set<String>>{
                      ...criteria.dimensions,
                    };
                    void setDimension(String key, String? value) {
                      if (value == null || value.trim().isEmpty) {
                        dimensions.remove(key);
                      } else {
                        dimensions[key] = <String>{value};
                      }
                    }

                    setDimension('reference', reference);
                    setDimension('sourceModule', sourceModule);
                    setDimension('paymentType', paymentType);
                    final numericRanges = <String, UnifiedNumericRange>{
                      ...criteria.numericRanges,
                    };
                    final min = double.tryParse(
                      minAmount.text.replaceAll(',', ''),
                    );
                    final max = double.tryParse(
                      maxAmount.text.replaceAll(',', ''),
                    );
                    if (min == null && max == null) {
                      numericRanges.remove('amount');
                    } else {
                      numericRanges['amount'] = UnifiedNumericRange(
                        min: min,
                        max: max,
                      );
                    }
                    Navigator.pop(
                      dialogContext,
                      criteria.copyWith(
                        types: type == null
                            ? const <String>{}
                            : <String>{type!},
                        currencies: currency == null
                            ? const <String>{}
                            : <String>{currency!},
                        userIds: user == null
                            ? const <String>{}
                            : <String>{user!},
                        partnerIds: partner == null
                            ? const <String>{}
                            : <String>{partner!},
                        fromDate: fromDate,
                        toDate: toDate,
                        clearFromDate: fromDate == null,
                        clearToDate: toDate == null,
                        dimensions: dimensions,
                        numericRanges: numericRanges,
                        offset: 0,
                      ),
                    );
                  },
                  child: AppText(t('تطبيق', 'Apply')),
                ),
              ],
            );
          },
        ),
      );
      if (result != null && mounted) controller.setTransactionFilter(result);
    } finally {
      minAmount.dispose();
      maxAmount.dispose();
    }
  }

  String? _single(Set<String>? values) =>
      values != null && values.length == 1 ? values.first : null;

  List<String> _values(Iterable<String?> source) {
    final result = source
        .map((value) => value?.trim())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return result;
  }

  String _sortValue(UnifiedSortSpec? sort) {
    if (sort == null) return 'date_desc';
    final suffix = sort.direction == UnifiedSortDirection.descending
        ? 'desc'
        : 'asc';
    final value = '${sort.key}_$suffix';
    return const <String>{
      'date_desc',
      'date_asc',
      'amount_desc',
      'amount_asc',
      'reference_asc',
    }.contains(value)
        ? value
        : 'date_desc';
  }

  UnifiedSortSpec _sortSpec(String value) {
    final parts = value.split('_');
    return UnifiedSortSpec(
      parts.first,
      direction: parts.last == 'desc'
          ? UnifiedSortDirection.descending
          : UnifiedSortDirection.ascending,
    );
  }

  Widget _transactionTable(
    CashboxController controller,
    List<CashTransactionModel> transactions,
  ) {
    final access = context.read<AccessController>();
    String counterName(CashTransactionModel transaction) {
      for (final account in controller.ledgerAccounts) {
        if (account.id == transaction.counterAccountId) {
          return '${account.code} — ${account.name}';
        }
      }
      return transaction.counterAccountId ?? '—';
    }

    return Scrollbar(
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 44,
            dataRowMinHeight: 44,
            dataRowMaxHeight: 58,
            columns: <DataColumn>[
              DataColumn(label: AppText(t('السند', 'Voucher'))),
              DataColumn(label: AppText(t('التاريخ والوقت', 'Date / time'))),
              DataColumn(label: AppText(t('الاتجاه', 'Direction'))),
              DataColumn(label: AppText(t('النوع', 'Type'))),
              DataColumn(label: AppText(t('المبلغ', 'Amount'))),
              DataColumn(label: AppText(t('العملة', 'Currency'))),
              DataColumn(label: AppText(t('الطرف', 'Partner'))),
              DataColumn(label: AppText(t('الحساب المقابل', 'Counter account'))),
              DataColumn(label: AppText(t('المصدر', 'Source module'))),
              DataColumn(label: AppText(t('المستند المرتبط', 'Related document'))),
              DataColumn(label: AppText(t('المرجع', 'Reference'))),
              DataColumn(label: AppText(t('طريقة الدفع', 'Payment type'))),
              DataColumn(label: AppText(t('المستخدم', 'User'))),
              DataColumn(label: AppText(t('الحالة', 'Status'))),
              DataColumn(label: AppText(t('ملاحظات', 'Notes'))),
              DataColumn(label: AppText(t('الإجراءات', 'Actions'))),
            ],
            rows: transactions.map((transaction) {
              final sourceModule = CashboxTransactionFilter.sourceModuleOf(
                transaction,
              );
              final isTransfer = sourceModule == 'cashbox' &&
                  (transaction.referenceType ?? '').toLowerCase().contains(
                    'transfer',
                  );
              final canEdit = !isTransfer &&
                  access.canPerformAction(
                    'cashbox',
                    'transaction.edit',
                    legacyPermission: 'accounting.update',
                  );
              final canDelete = access.canPerformAction(
                'cashbox',
                'transaction.delete',
                legacyPermission: 'accounting.delete',
              );
              final canPrint = access.canPerformAction(
                'cashbox',
                'transaction.print',
                legacyPermission: 'accounting.view',
              );
              return DataRow(
                onSelectChanged: (_) => _showDetails(transaction),
                cells: <DataCell>[
                  DataCell(
                    _secured(
                      'documentNumber',
                      AppText(
                        ErpDisplayFormatter.formatReference(
                          transaction.voucherNumber,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    _secured(
                      'operationalDate',
                      AppText(
                        ErpDisplayFormatter.formatDateTime(
                          transaction.transactionDate,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    _secured(
                      'transactionType',
                      AppText(
                        transaction.isReceipt
                            ? t('داخل', 'In')
                            : t('خارج', 'Out'),
                      ),
                    ),
                  ),
                  DataCell(
                    _secured('transactionType', AppText(transaction.category)),
                  ),
                  DataCell(
                    _secured(
                      'amount',
                      AppText(
                        ErpDisplayFormatter.formatMoney(
                          transaction.amount,
                          transaction.currency,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    _secured(
                      'currency',
                      AppText(
                        ErpDisplayFormatter.normalizeCurrency(
                          transaction.currency,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    _secured(
                      'partyName',
                      AppText(transaction.partyName ?? '—'),
                    ),
                  ),
                  DataCell(
                    _secured(
                      'counterAccount',
                      AppText(counterName(transaction)),
                    ),
                  ),
                  DataCell(
                    _secured('reference', AppText(sourceModule)),
                  ),
                  DataCell(
                    _secured(
                      'reference',
                      AppText(transaction.referenceType ?? '—'),
                    ),
                  ),
                  DataCell(
                    _secured(
                      'reference',
                      AppText(
                        ErpDisplayFormatter.formatReference(
                          transaction.referenceId,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    _secured(
                      'paymentMethod',
                      AppText(_paymentMethod(transaction.paymentMethod)),
                    ),
                  ),
                  DataCell(
                    _secured(
                      'performedBy',
                      AppText(transaction.performedBy ?? '—'),
                    ),
                  ),
                  DataCell(
                    _secured(
                      'transactionStatus',
                      AppText(t('معتمد', 'Posted')),
                    ),
                  ),
                  DataCell(
                    _secured(
                      'notes',
                      SizedBox(
                        width: 180,
                        child: AppText(
                          transaction.notes ?? '—',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    Wrap(
                      spacing: 2,
                      children: <Widget>[
                        IconButton(
                          tooltip: t('عرض', 'View'),
                          onPressed: () => _showDetails(transaction),
                          icon: const Icon(Icons.visibility_outlined, size: 18),
                        ),
                        if (canPrint)
                          IconButton(
                            tooltip: t('طباعة', 'Print'),
                            onPressed: () => const CashVoucherPdfService()
                                .printVoucher(
                                  transaction,
                                  arabic: ar,
                                  cashAccountName: widget.account.name,
                                  counterAccountName: counterName(transaction),
                                  journalEntryNumber: transaction.journalEntryId,
                                ),
                            icon: const Icon(Icons.print_outlined, size: 18),
                          ),
                        if (canEdit)
                          IconButton(
                            tooltip: t('تعديل', 'Edit'),
                            onPressed: () => _openEdit(transaction),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                          ),
                        if (canDelete)
                          IconButton(
                            tooltip: t('حذف', 'Delete'),
                            onPressed: () => _delete(
                              transaction,
                              isTransfer: isTransfer,
                            ),
                            icon: const Icon(Icons.delete_outline, size: 18),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(growable: false),
          ),
        ),
      ),
    );
  }

  Future<void> _openAdd(String type) async {
    final legacy = type == 'receipt' ? 'cashbox.receipt' : 'cashbox.payment';
    if (!await _requireAction(type, legacy)) return;
    if (!mounted) return;
    final changed = await showAppModuleDialog<bool>(
      context: context,
      title: type == 'receipt'
          ? t('إضافة سند قبض', 'Add receipt')
          : t('إضافة سند صرف', 'Add payment'),
      windowKey: 'cashbox:add:${widget.account.id}:$type',
      builder: (_) => AddCashTransactionPage(
        initialType: type,
        initialCashAccountId: widget.account.id,
      ),
    );
    if (changed == true && mounted) {
      await context.read<CashboxController>().loadTransactions();
    }
  }

  Future<void> _openEdit(CashTransactionModel transaction) async {
    if (!await _requireAction('transaction.edit', 'accounting.update')) return;
    if (!mounted) return;
    final changed = await showAppModuleDialog<bool>(
      context: context,
      title: t('تعديل حركة صندوق', 'Edit cash transaction'),
      windowKey: 'cashbox:edit:${transaction.id}',
      builder: (_) => AddCashTransactionPage(transaction: transaction),
    );
    if (changed == true && mounted) {
      await context.read<CashboxController>().loadTransactions();
    }
  }

  Future<void> _editAccount() async {
    if (!await _requireAction('account.edit', 'accounting.update')) return;
    if (!mounted) return;
    final changed = await showAppWorkspaceDialogBuilder<bool>(
      context: context,
      builder: (_) => CashAccountForm(account: widget.account),
    );
    if (changed == true && mounted) {
      await context.read<CashboxController>().loadTransactions();
    }
  }

  Future<bool> _requireAction(String action, String legacy) async {
    final access = context.read<AccessController>();
    if (access.canPerformAction('cashbox', action, legacyPermission: legacy)) {
      return true;
    }
    await access.recordDeniedAccess('cashbox.$action');
    return false;
  }

  Future<void> _delete(
    CashTransactionModel transaction, {
    required bool isTransfer,
  }) async {
    if (!await _requireAction('transaction.delete', 'accounting.delete')) {
      return;
    }
    if (!mounted) return;
    final confirmed = await showAppConfirmDialog(
      context,
      title: t('حذف حركة الصندوق', 'Delete cash transaction'),
      message: t(
        'هل تريد حذف السند ${transaction.voucherNumber}؟',
        'Delete voucher ${transaction.voucherNumber}?',
      ),
      confirmLabel: t('حذف', 'Delete'),
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    final controller = context.read<CashboxController>();
    try {
      if (isTransfer && transaction.referenceId?.trim().isNotEmpty == true) {
        await controller.deleteTransfer(transaction.referenceId!.trim());
      } else {
        await controller.deleteTransaction(transaction.id);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: AppText(userFacingError(error, isArabic: ar))),
      );
    }
  }

  Future<void> _showDetails(CashTransactionModel transaction) =>
      showUnifiedDocumentDetails(
        context: context,
        title: transaction.isReceipt
            ? t('سند قبض', 'Receipt voucher')
            : t('سند صرف', 'Payment voucher'),
        documentNumber: transaction.voucherNumber,
        status: t('معتمد', 'Posted'),
        icon: transaction.isReceipt
            ? Icons.south_west_rounded
            : Icons.north_east_rounded,
        sections: <UnifiedDocumentSection>[
          UnifiedDocumentSection(
            title: t('بيانات المستند', 'Document'),
            fields: <UnifiedDocumentField>[
              UnifiedDocumentField(t('النوع', 'Type'), transaction.category),
              UnifiedDocumentField(
                t('التاريخ', 'Date'),
                ErpDisplayFormatter.formatDateTime(transaction.transactionDate),
              ),
              UnifiedDocumentField(
                t('المبلغ', 'Amount'),
                ErpDisplayFormatter.formatMoney(
                  transaction.amount,
                  transaction.currency,
                ),
              ),
              UnifiedDocumentField(
                t('طريقة الدفع', 'Payment type'),
                _paymentMethod(transaction.paymentMethod),
              ),
            ],
          ),
          UnifiedDocumentSection(
            title: t('الطرف والربط', 'Partner & relations'),
            fields: <UnifiedDocumentField>[
              UnifiedDocumentField(
                t('الطرف', 'Partner'),
                transaction.partyName,
              ),
              UnifiedDocumentField(
                t('نوع الطرف', 'Partner type'),
                transaction.partyType,
              ),
              UnifiedDocumentField(
                t('المصدر', 'Source'),
                CashboxTransactionFilter.sourceModuleOf(transaction),
              ),
              UnifiedDocumentField(
                t('نوع المرجع', 'Reference type'),
                transaction.referenceType,
              ),
              UnifiedDocumentField(
                t('المرجع', 'Reference'),
                transaction.referenceId,
              ),
            ],
          ),
          UnifiedDocumentSection(
            title: t('التدقيق', 'Audit'),
            fields: <UnifiedDocumentField>[
              UnifiedDocumentField(
                t('المستخدم', 'User'),
                transaction.performedBy,
              ),
              UnifiedDocumentField(
                t('القيد', 'Journal entry'),
                transaction.journalEntryId,
              ),
              UnifiedDocumentField(t('ملاحظات', 'Notes'), transaction.notes),
            ],
          ),
        ],
      );

  String _paymentMethod(String value) => switch (value) {
    'bank_transfer' => t('تحويل مصرفي', 'Bank transfer'),
    'card' => t('بطاقة', 'Card'),
    'cheque' => t('صك', 'Cheque'),
    _ => t('نقدي', 'Cash'),
  };

  Future<void> _export(
    CashboxController controller,
    List<CashTransactionModel> transactions,
  ) async {
    if (!await _requireAction('transaction.export', 'accounting.view')) return;
    if (!mounted) return;
    String counterName(CashTransactionModel transaction) {
      for (final account in controller.ledgerAccounts) {
        if (account.id == transaction.counterAccountId) {
          return '${account.code} — ${account.name}';
        }
      }
      return transaction.counterAccountId ?? '';
    }

    final document = ExportDocument(
      title: t(
        'حركات ${widget.account.name}',
        '${widget.account.name} transactions',
      ),
      subtitle: t(
        'البيانات المطابقة للفلاتر النشطة',
        'Dataset matching active filters',
      ),
      language: ar ? 'ar' : 'en',
      currency: widget.account.currency,
      metadata: <String, Object?>{
        t('الصندوق', 'Cashbox'): widget.account.name,
        t('عدد الحركات', 'Transaction count'): transactions.length,
      },
      columns: <ExportColumn>[
        ExportColumn(key: 'voucher', label: t('السند', 'Voucher')),
        ExportColumn(
          key: 'date',
          label: t('التاريخ والوقت', 'Date / time'),
          type: ExportValueType.dateTime,
        ),
        ExportColumn(key: 'direction', label: t('الاتجاه', 'Direction')),
        ExportColumn(key: 'type', label: t('النوع', 'Type')),
        ExportColumn(
          key: 'amount',
          label: t('المبلغ', 'Amount'),
          type: ExportValueType.money,
        ),
        ExportColumn(key: 'currency', label: t('العملة', 'Currency')),
        ExportColumn(key: 'partner', label: t('الطرف', 'Partner')),
        ExportColumn(
          key: 'counter',
          label: t('الحساب المقابل', 'Counter account'),
        ),
        ExportColumn(key: 'source', label: t('المصدر', 'Source module')),
        ExportColumn(key: 'reference', label: t('المرجع', 'Reference')),
        ExportColumn(
          key: 'payment',
          label: t('طريقة الدفع', 'Payment type'),
        ),
        ExportColumn(key: 'user', label: t('المستخدم', 'User')),
        ExportColumn(key: 'notes', label: t('ملاحظات', 'Notes')),
      ],
      rows: transactions
          .map(
            (transaction) => <Object?>[
              transaction.voucherNumber,
              transaction.transactionDate,
              transaction.isReceipt ? t('داخل', 'In') : t('خارج', 'Out'),
              transaction.category,
              transaction.amount,
              transaction.currency,
              transaction.partyName,
              counterName(transaction),
              CashboxTransactionFilter.sourceModuleOf(transaction),
              transaction.referenceId,
              _paymentMethod(transaction.paymentMethod),
              transaction.performedBy,
              transaction.notes,
            ],
          )
          .toList(growable: false),
    );
    try {
      await ExcelExportService().save(document);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: AppText(userFacingError(error, isArabic: ar))),
      );
    }
  }
}

class _CashboxMovementChart extends StatelessWidget {
  const _CashboxMovementChart({
    required this.transactions,
    required this.currency,
    this.compact = false,
  });

  final List<CashTransactionModel> transactions;
  final String currency;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ar = context.l10n.isArabic;
    String t(String arabic, String english) => ar ? arabic : english;
    final movements = CashboxDailyMovement.fromTransactions(transactions);
    final scheme = Theme.of(context).colorScheme;
    if (movements.isEmpty) {
      return Container(
        height: compact ? 42 : 88,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: .25),
          borderRadius: BorderRadius.circular(10),
        ),
        child: AppText(
          t('لا حركة ضمن الفترة', 'No movement in this period'),
          style: Theme.of(context).textTheme.labelSmall,
        ),
      );
    }
    final maxAmount = movements.fold<double>(0, (max, item) {
      final candidate = item.cashIn > item.cashOut ? item.cashIn : item.cashOut;
      return candidate > max ? candidate : max;
    });
    return Container(
      padding: EdgeInsets.all(compact ? 6 : 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (!compact)
            Row(
              children: <Widget>[
                Expanded(
                  child: AppText(
                    t('اتجاه التدفق النقدي', 'Cash movement trend'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                _legend(context, t('داخل', 'In'), scheme.primary),
                const SizedBox(width: 8),
                _legend(context, t('خارج', 'Out'), scheme.error),
              ],
            ),
          if (!compact) const SizedBox(height: 8),
          SizedBox(
            height: compact ? 44 : 112,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: movements.map((movement) {
                  final inHeight = maxAmount <= 0
                      ? 2.0
                      : (movement.cashIn / maxAmount) * (compact ? 28 : 64);
                  final outHeight = maxAmount <= 0
                      ? 2.0
                      : (movement.cashOut / maxAmount) * (compact ? 28 : 64);
                  return SizedBox(
                    width: compact ? 18 : 72,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        if (!compact)
                          AppText(
                            ErpDisplayFormatter.formatMoney(
                              movement.netMovement,
                              currency,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: <Widget>[
                            Container(
                              width: compact ? 5 : 12,
                              height: inHeight
                                  .clamp(2, compact ? 28 : 64)
                                  .toDouble(),
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: .75),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            SizedBox(width: compact ? 2 : 4),
                            Container(
                              width: compact ? 5 : 12,
                              height: outHeight
                                  .clamp(2, compact ? 28 : 64)
                                  .toDouble(),
                              decoration: BoxDecoration(
                                color: scheme.error.withValues(alpha: .72),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ],
                        ),
                        if (!compact) ...<Widget>[
                          const SizedBox(height: 3),
                          AppText(
                            ErpDisplayFormatter.formatDate(movement.day),
                            style: const TextStyle(fontSize: 8.5),
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(growable: false),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _legend(BuildContext context, String label, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      AppText(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}
