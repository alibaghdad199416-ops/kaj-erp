import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:quality_line_erp/core/utils/thousands_input_formatter.dart';

import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';
import 'package:quality_line_erp/core/widgets/app_dialog.dart';

import 'package:quality_line_erp/core/widgets/app_module_dialog.dart';
import 'package:quality_line_erp/core/widgets/unified_document_details_dialog.dart';
import 'package:provider/provider.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:quality_line_erp/design_system/kaj_finance_stage7_components.dart';

import 'package:quality_line_erp/features/accounting/cashbox/controllers/cashbox_controller.dart';
import 'package:quality_line_erp/features/accounting/cashbox/models/cash_account_model.dart';
import 'package:quality_line_erp/features/accounting/cashbox/models/cash_transaction_model.dart';
import 'package:quality_line_erp/features/accounting/cashbox/services/cash_voucher_pdf_service.dart';
import 'package:quality_line_erp/core/widgets/app_responsive.dart';
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
      CashAccountModel? target;
      for (final account in controller.cashAccounts) {
        if (account.id == id) {
          target = account;
          break;
        }
      }
      if (target != null) await _openCashboxDetail(target, controller);
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
              title: context.l10n.isArabic
                  ? 'جارٍ مزامنة الصناديق'
                  : 'Synchronizing cashboxes',
              message: context.l10n.isArabic
                  ? 'يتم تحميل الصناديق والأرصدة المرتبطة.'
                  : 'Loading cashboxes and linked balances.',
            ),
          );
        }
        if (controller.errorMessage != null &&
            controller.cashAccounts.isEmpty) {
          return Center(
            child: _message(Icons.error_outline, controller.errorMessage!),
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
            if (!widget.embedded) ...[_header(), const SizedBox(height: 16)],
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

  Future<void> _showDetails(CashTransactionModel transaction) {
    return showUnifiedDocumentDetails(
      context: context,
      title: transaction.isReceipt ? 'سند قبض' : 'سند صرف',
      documentNumber: transaction.voucherNumber,
      status: 'معتمد',
      icon: transaction.isReceipt
          ? Icons.south_west_rounded
          : Icons.north_east_rounded,
      sections: [
        UnifiedDocumentSection(
          title: 'بيانات المستند',
          fields: [
            UnifiedDocumentField(
              'التصنيف',
              transaction.category,
              icon: Icons.category_outlined,
            ),
            UnifiedDocumentField(
              'التاريخ',
              _documentDate(transaction.transactionDate),
              icon: Icons.calendar_today_outlined,
            ),
            UnifiedDocumentField(
              'المبلغ',
              MoneyFormatter.withCurrency(
                transaction.amount,
                transaction.currency,
              ),
              icon: Icons.payments_outlined,
            ),
            UnifiedDocumentField(
              'طريقة الدفع',
              _documentPaymentMethod(transaction.paymentMethod),
              icon: Icons.account_balance_wallet_outlined,
            ),
          ],
        ),
        UnifiedDocumentSection(
          title: 'الطرف والربط',
          fields: [
            UnifiedDocumentField('الطرف', transaction.partyName),
            UnifiedDocumentField('نوع الطرف', transaction.partyType),
            UnifiedDocumentField(
              'نوع المستند المرتبط',
              transaction.referenceType,
            ),
          ],
        ),
        UnifiedDocumentSection(
          title: 'معلومات إضافية',
          fields: [
            UnifiedDocumentField(
              'الملاحظات',
              transaction.notes,
              icon: Icons.notes_outlined,
            ),
            UnifiedDocumentField(
              'تاريخ الإنشاء',
              _documentDate(transaction.transactionDate),
              icon: Icons.schedule_outlined,
            ),
            UnifiedDocumentField(
              'آخر تحديث',
              transaction.updatedAt == null
                  ? null
                  : _documentDate(transaction.updatedAt!),
              icon: Icons.update_outlined,
            ),
          ],
        ),
      ],
    );
  }

  String _documentDate(DateTime value) =>
      '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';

  String _documentPaymentMethod(String value) {
    final ar = context.l10n.isArabic;
    switch (value) {
      case 'bank_transfer':
        return ar ? 'تحويل مصرفي' : 'Bank transfer';
      case 'card':
        return ar ? 'بطاقة' : 'Card';
      case 'cheque':
        return ar ? 'صك' : 'Cheque';
      default:
        return ar ? 'نقدي' : 'Cash';
    }
  }

  Widget _header() {
    final isArabic = context.l10n.isArabic;
    final access = context.read<AccessController>();
    final canTransfer = access.canPerformAction(
      'cashbox',
      'transfer',
      legacyPermission: 'accounting.update',
    );
    return KajFinanceSection(
      title: isArabic
          ? 'الصناديق والحسابات النقدية'
          : 'Cashboxes & Cash Accounts',
      subtitle: isArabic
          ? 'إدارة سندات القبض والصرف والتحويلات متعددة العملات.'
          : 'Manage receipts, payments and multi-currency transfers.',
      icon: Icons.account_balance_wallet_outlined,
      trailing: canTransfer
          ? IconButton(
              tooltip: isArabic
                  ? 'تحويل بين الصناديق'
                  : 'Transfer between cashboxes',
              onPressed: _openTransfer,
              icon: const Icon(Icons.swap_horiz_rounded),
            )
          : null,
      child: const SizedBox.shrink(),
    );
  }

  // Retained for compact embedded finance surfaces.
  // ignore: unused_element
  Widget _stats(CashboxController controller) {
    final usd = controller.usdSummary;
    final iqd = controller.iqdSummary;
    final ar = context.l10n.isArabic;

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        const minWidth = 210.0;
        final columns = ((constraints.maxWidth + gap) / (minWidth + gap))
            .floor()
            .clamp(1, 4);
        final width = (constraints.maxWidth - ((columns - 1) * gap)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            _stat(
              ar ? 'رصيد USD' : 'USD balance',
              MoneyFormatter.format(usd['balance'] ?? 0, currency: 'USD'),
              Icons.attach_money_rounded,
              width,
            ),
            _stat(
              ar ? 'مقبوضات USD' : 'USD receipts',
              MoneyFormatter.format(usd['receipts'] ?? 0, currency: 'USD'),
              Icons.south_west_rounded,
              width,
            ),
            _stat(
              ar ? 'رصيد IQD' : 'IQD balance',
              MoneyFormatter.format(iqd['balance'] ?? 0, currency: 'IQD'),
              Icons.payments_outlined,
              width,
            ),
            _stat(
              ar ? 'مصروفات IQD' : 'IQD payments',
              MoneyFormatter.format(iqd['payments'] ?? 0, currency: 'IQD'),
              Icons.north_east_rounded,
              width,
            ),
          ],
        );
      },
    );
  }

  Widget _stat(String title, String value, IconData icon, double width) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: Container(
        constraints: const BoxConstraints(minHeight: 62),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: .72),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: scheme.primary),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  AppText(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _message(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: Colors.grey),
          const SizedBox(height: 8),
          AppText(text, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Future<void> _openTransfer() async {
    if (!await _requireCashboxAction(
      'transfer',
      legacyPermission: 'accounting.update',
    ))
      return;
    if (!mounted) return;
    final controller = context.read<CashboxController>();
    final ar = context.l10n.isArabic;
    String t(String arabic, String english) => ar ? arabic : english;
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
    String toId =
        accounts.first.linkedCashAccountId != null &&
            accounts.any((a) => a.id == accounts.first.linkedCashAccountId)
        ? accounts.first.linkedCashAccountId!
        : accounts[1].id;
    final source = TextEditingController();
    final target = TextEditingController();
    final rate = TextEditingController(text: '1');
    final notes = TextEditingController();
    final formKey = GlobalKey<FormState>();
    DateTime transferDate = DateTime.now();

    CashAccountModel accountById(String id) =>
        accounts.firstWhere((account) => account.id == id);

    bool sameCurrency() =>
        accountById(fromId).currency.toUpperCase() ==
        accountById(toId).currency.toUpperCase();

    CashAccountModel? configuredLinkedAccount(CashAccountModel sourceAccount) {
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

    List<CashAccountModel> allowedTargets(CashAccountModel sourceAccount) {
      final linked = configuredLinkedAccount(sourceAccount);
      return accounts
          .where((account) {
            if (account.id == sourceAccount.id) return false;
            if (account.currency.toUpperCase() ==
                sourceAccount.currency.toUpperCase()) {
              return true;
            }
            return linked != null && account.id == linked.id;
          })
          .toList(growable: false);
    }

    void normalizeDestinationForSource() {
      final sourceAccount = accountById(fromId);
      final targets = allowedTargets(sourceAccount);
      if (targets.isEmpty) return;
      if (!targets.any((account) => account.id == toId)) {
        toId = configuredLinkedAccount(sourceAccount)?.id ?? targets.first.id;
      }
    }

    void recalculateTarget() {
      final sourceValue = double.tryParse(source.text.replaceAll(',', '')) ?? 0;
      final isSameCurrency = sameCurrency();
      if (isSameCurrency) rate.text = '1';
      final rateValue = isSameCurrency
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
            normalizeDestinationForSource();
            final from = accountById(fromId);
            final to = accountById(toId);
            final targets = allowedTargets(from);
            final linked = configuredLinkedAccount(from);
            final isSameCurrency = sameCurrency();

            Future<void> pickTransferDate() async {
              final date = await showDatePicker(
                context: context,
                initialDate: transferDate,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                helpText: t('اختر تاريخ التحويل', 'Select transfer date'),
              );
              if (date == null || !context.mounted) return;
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(transferDate),
                helpText: t('اختر وقت التحويل', 'Select transfer time'),
              );
              if (!context.mounted) return;
              final selectedTime = time ?? TimeOfDay.fromDateTime(transferDate);
              setDialogState(() {
                transferDate = DateTime(
                  date.year,
                  date.month,
                  date.day,
                  selectedTime.hour,
                  selectedTime.minute,
                );
              });
            }

            void selectFrom(String? value) {
              if (value == null) return;
              setDialogState(() {
                fromId = value;
                normalizeDestinationForSource();
                recalculateTarget();
              });
            }

            void selectTo(String? value) {
              if (value == null) return;
              setDialogState(() {
                toId = value;
                if (toId == fromId) {
                  fromId = accounts.firstWhere((a) => a.id != toId).id;
                }
                recalculateTarget();
              });
            }

            return AlertDialog(
              title: AppText(
                t(
                  'تحويل أموال بين الصناديق',
                  'Transfer funds between cashboxes',
                ),
              ),
              content: Form(
                key: formKey,
                child: SizedBox(
                  width: AppResponsive.dialogWidth(context, 540),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _securedCashboxField(
                          'transferFrom',
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            key: ValueKey<String>('from:$fromId:$toId'),
                            initialValue: fromId,
                            decoration: InputDecoration(
                              labelText: t('من صندوق', 'From cashbox'),
                              helperText: t(
                                '${from.name} — ${from.currency.toUpperCase()}',
                                '${from.name} — ${from.currency.toUpperCase()}',
                              ),
                            ),
                            items: accounts
                                .map(
                                  (account) => DropdownMenuItem<String>(
                                    value: account.id,
                                    child: AppText(
                                      '${account.name} (${account.currency.toUpperCase()})',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: selectFrom,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _securedCashboxField(
                          'transferTo',
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            key: ValueKey<String>('to:$fromId:$toId'),
                            initialValue: toId,
                            decoration: InputDecoration(
                              labelText: t('إلى صندوق', 'To cashbox'),
                              helperText: !isSameCurrency && linked != null
                                  ? t(
                                      'هذا هو الصندوق المرتبط المحدد في تعريف ${from.name}.',
                                      'This is the linked cashbox configured for ${from.name}.',
                                    )
                                  : t(
                                      '${to.name} — ${to.currency.toUpperCase()}',
                                      '${to.name} — ${to.currency.toUpperCase()}',
                                    ),
                            ),
                            items: targets
                                .map(
                                  (account) => DropdownMenuItem<String>(
                                    value: account.id,
                                    child: AppText(
                                      '${account.name} (${account.currency.toUpperCase()})',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: selectTo,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _securedCashboxField(
                          'amount',
                          TextFormField(
                            controller: source,

                            inputFormatters: <TextInputFormatter>[
                              ThousandsInputFormatter(decimalDigits: 2),
                            ],
                            decoration: InputDecoration(
                              labelText: t(
                                'المبلغ الخارج (${from.currency.toUpperCase()})',
                                'Source amount (${from.currency.toUpperCase()})',
                              ),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            validator: _positiveAmount,
                            onChanged: (_) => setDialogState(recalculateTarget),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _securedCashboxField(
                          'exchangeRate',
                          TextFormField(
                            controller: rate,
                            enabled: !isSameCurrency,

                            inputFormatters: <TextInputFormatter>[
                              ThousandsInputFormatter(decimalDigits: 20),
                            ],
                            decoration: InputDecoration(
                              labelText: t(
                                'سعر التحويل: ${to.currency.toUpperCase()} لكل ${from.currency.toUpperCase()}',
                                'Conversion rate: ${to.currency.toUpperCase()} per ${from.currency.toUpperCase()}',
                              ),
                              helperText: isSameCurrency
                                  ? t(
                                      'التحويل بالعملة نفسها يستخدم سعر 1.',
                                      'Same-currency transfers use rate 1.',
                                    )
                                  : t(
                                      'يُحسب المبلغ الداخل تلقائيًا.',
                                      'The target amount is calculated automatically.',
                                    ),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            validator: _positiveAmount,
                            onChanged: (_) => setDialogState(recalculateTarget),
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
                                'المبلغ الداخل (${to.currency.toUpperCase()})',
                                'Target amount (${to.currency.toUpperCase()})',
                              ),
                            ),
                            validator: _positiveAmount,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _securedCashboxField(
                          'operationalDate',
                          InkWell(
                            onTap: pickTransferDate,
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: t(
                                  'التاريخ والوقت التشغيلي',
                                  'Operational date and time',
                                ),
                                prefixIcon: const Icon(
                                  Icons.event_available_outlined,
                                ),
                                border: const OutlineInputBorder(),
                              ),
                              child: AppText(
                                DateFormat(
                                  'yyyy-MM-dd HH:mm',
                                ).format(transferDate),
                              ),
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
                    recalculateTarget();
                    if (formKey.currentState?.validate() == true) {
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
      recalculateTarget();
      final sourceAmount = double.parse(source.text.replaceAll(',', ''));
      final targetAmount = double.parse(target.text.replaceAll(',', ''));
      final exchangeRate = sameCurrency()
          ? 1.0
          : double.parse(rate.text.replaceAll(',', ''));
      if (!sameCurrency()) {
        final linked = configuredLinkedAccount(accountById(fromId));
        if (linked == null || linked.id != toId) {
          throw StateError(
            t(
              'الصندوق الوجهة ليس الرابط المحدد للصندوق المصدر. افتح تعريف الصندوق واحفظ الربط بين الصندوقين ثم أعد المحاولة.',
              'The destination is not the configured link for the source cashbox. Save the reciprocal link in cashbox settings and try again.',
            ),
          );
        }
      }
      await controller.transferBetweenAccounts(
        fromAccountId: fromId,
        toAccountId: toId,
        sourceAmount: sourceAmount,
        targetAmount: targetAmount,
        exchangeRate: exchangeRate,
        transferDate: transferDate,
        notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            t(
              'تم تنفيذ التحويل وتحديث الصندوقين.',
              'The transfer completed and both cashboxes were refreshed.',
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: AppText(
            userFacingError(error, isArabic: context.l10n.isArabic),
          ),
        ),
      );
    } finally {
      source.dispose();
      target.dispose();
      rate.dispose();
      notes.dispose();
    }
  }

  String? _positiveAmount(String? value) {
    final number = double.tryParse((value ?? '').replaceAll(',', ''));
    if (number != null && number > 0) return null;
    return context.l10n.isArabic
        ? 'أدخل قيمة أكبر من صفر'
        : 'Enter a value greater than zero';
  }

  Future<void> _openAdd(String type, {String? cashAccountId}) async {
    final legacyPermission = type == 'receipt'
        ? 'cashbox.receipt'
        : 'cashbox.payment';
    if (!await _requireCashboxAction(
      type,
      legacyPermission: legacyPermission,
    )) {
      return;
    }
    if (!mounted) return;
    final result = await showAppModuleDialog<bool>(
      context: context,
      title: type == 'receipt' ? 'إضافة سند قبض' : 'إضافة سند صرف',
      windowKey: 'cashbox:add:$type',
      builder: (_) => AddCashTransactionPage(
        initialType: type,
        initialCashAccountId: cashAccountId,
      ),
    );
    if (mounted && result == true) {
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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: AppText(
            context.l10n.isArabic
                ? 'ليس لديك صلاحية لتنفيذ هذه العملية.'
                : 'You do not have permission to perform this action.',
          ),
        ),
      );
    return false;
  }

  Future<void> _openEdit(CashTransactionModel transaction) async {
    if (!await _requireCashboxAction(
      'transaction.edit',
      legacyPermission: 'accounting.update',
    )) {
      return;
    }
    if (!mounted) return;
    final result = await showAppModuleDialog<bool>(
      context: context,
      title: 'تعديل حركة صندوق',
      windowKey: 'cashbox:edit:${transaction.id}',
      builder: (_) => AddCashTransactionPage(transaction: transaction),
    );
    if (mounted && result == true) {
      await context.read<CashboxController>().loadTransactions();
    }
  }

  Future<void> _delete(CashTransactionModel transaction) async {
    if (!await _requireCashboxAction(
      'transaction.delete',
      legacyPermission: 'accounting.delete',
    )) {
      return;
    }
    if (!mounted) return;
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'حذف حركة الصندوق',
      message: 'هل تريد حذف السند ${transaction.voucherNumber}؟',
      confirmLabel: 'حذف',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<CashboxController>().deleteTransaction(transaction.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            context.read<CashboxController>().errorMessage ?? 'تعذر حذف الحركة',
          ),
        ),
      );
    }
  }

  Widget _cashAccounts(CashboxController controller) {
    final scheme = Theme.of(context).colorScheme;
    final ar = context.l10n.isArabic;

    Widget accountCard(CashAccountModel account, double itemWidth) {
      final reconciliation = controller.reconciliation[account.id];
      final subledger =
          reconciliation?['subledger'] ??
          (controller.balances[account.id] ?? account.openingBalance);
      final ledger = reconciliation?['ledger'] ?? 0;
      final difference = reconciliation?['difference'] ?? 0;
      final isReconciled = difference.abs() <= 0.01;
      final balance = controller.balances[account.id] ?? account.openingBalance;
      final accountTransactions = controller.transactions
          .where((transaction) => transaction.cashAccountId == account.id)
          .toList(growable: false);
      final cashIn = accountTransactions
          .where((transaction) => transaction.isReceipt)
          .fold<double>(0, (sum, transaction) => sum + transaction.amount);
      final cashOut = accountTransactions
          .where((transaction) => transaction.isPayment)
          .fold<double>(0, (sum, transaction) => sum + transaction.amount);
      final access = context.read<AccessController>();
      final canViewReconciliation = access.canViewField(
        'cashbox',
        'reconciliation',
        viewPermission: 'accounting.view',
      );
      final canViewAmount = access.canViewField(
        'cashbox',
        'amount',
        viewPermission: 'accounting.view',
      );
      final canViewCurrency = access.canViewField(
        'cashbox',
        'currency',
        viewPermission: 'accounting.view',
      );
      final canEditAccount = access.canPerformAction(
        'cashbox',
        'account.edit',
        legacyPermission: 'accounting.update',
      );

      return SizedBox(
        width: itemWidth,
        child: Material(
          color: scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
            side: BorderSide(
              color: !canViewReconciliation || isReconciled
                  ? scheme.outlineVariant.withValues(alpha: .72)
                  : scheme.error.withValues(alpha: .35),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _openCashboxDetail(account, controller),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 9),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          account.type == 'bank'
                              ? Icons.account_balance_outlined
                              : Icons.account_balance_wallet_outlined,
                          size: 18,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(width: 9),
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
                        field: 'isActive',
                        viewPermission: 'accounting.view',
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: account.isActive
                                ? Colors.green.withValues(alpha: .09)
                                : scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: AppText(
                            account.isActive
                                ? (ar ? 'فعال' : 'Active')
                                : (ar ? 'غير فعال' : 'Inactive'),
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: account.isActive
                                      ? Colors.green.shade700
                                      : scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: FieldPermissionVisibility(
                          resource: 'cashbox',
                          field: 'balance',
                          viewPermission: 'accounting.view',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (canViewCurrency)
                                AppText(
                                  account.currency.toUpperCase(),
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              if (canViewCurrency) const SizedBox(height: 1),
                              AppText(
                                MoneyFormatter.format(
                                  balance,
                                  currency: canViewCurrency
                                      ? account.currency
                                      : null,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                            ],
                          ),
                        ),
                      ),
                      FieldPermissionVisibility(
                        resource: 'cashbox',
                        field: 'reconciliation',
                        viewPermission: 'accounting.view',
                        child: IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: ar
                              ? 'تفاصيل المطابقة'
                              : 'Reconciliation details',
                          icon: const Icon(Icons.balance_outlined, size: 18),
                          onPressed: () => _showReconciliationDetails(
                            accountName: account.name,
                            currency: account.currency,
                            subledger: subledger,
                            ledger: ledger,
                            difference: difference,
                          ),
                        ),
                      ),
                      if (canEditAccount)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: ar ? 'تعديل الصندوق' : 'Edit cash account',
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () => _editCashAccount(account),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (canViewAmount)
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: <Widget>[
                        _cashboxMetric(
                          ar ? 'إجمالي الداخل' : 'Total Cash In',
                          cashIn,
                          canViewCurrency ? account.currency : '',
                          Icons.south_west_rounded,
                        ),
                        _cashboxMetric(
                          ar ? 'إجمالي الخارج' : 'Total Cash Out',
                          cashOut,
                          canViewCurrency ? account.currency : '',
                          Icons.north_east_rounded,
                        ),
                      ],
                    ),
                  if (canViewAmount) const SizedBox(height: 8),
                  if (canViewAmount) _cashboxTrend(accountTransactions),
                  const SizedBox(height: 6),
                  FieldPermissionVisibility(
                    resource: 'cashbox',
                    field: 'reconciliationDifference',
                    viewPermission: 'accounting.view',
                    child: Row(
                      children: [
                        Icon(
                          isReconciled
                              ? Icons.check_circle_outline_rounded
                              : Icons.warning_amber_rounded,
                          size: 15,
                          color: isReconciled
                              ? Colors.green.shade700
                              : scheme.error,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: AppText(
                            isReconciled
                                ? (ar
                                      ? 'مطابق مع دفتر الأستاذ'
                                      : 'Reconciled with general ledger')
                                : (ar
                                      ? 'فرق: ${MoneyFormatter.format(difference, currency: account.currency)} ${account.currency}'
                                      : 'Difference: ${MoneyFormatter.format(difference, currency: account.currency)} ${account.currency}'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: isReconciled
                                      ? Colors.green.shade700
                                      : scheme.error,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              size: 18,
              color: scheme.primary,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: AppText(
                ar ? 'الصناديق النقدية' : 'Cash accounts',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            if (context.read<AccessController>().canPerformAction(
              'cashbox',
              'account.create',
              legacyPermission: 'accounting.create',
            ))
              FilledButton.icon(
                onPressed: () => _editCashAccount(null),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: const Icon(Icons.add, size: 17),
                label: AppText(ar ? 'صندوق جديد' : 'New cash account'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (controller.cashAccounts.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            child: AppText(
              ar
                  ? 'لا توجد صناديق نقدية معرفة.'
                  : 'No cash accounts have been defined.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 10.0;
              const minWidth = 280.0;
              final columns = ((constraints.maxWidth + gap) / (minWidth + gap))
                  .floor()
                  .clamp(1, 4);
              final itemWidth =
                  (constraints.maxWidth - ((columns - 1) * gap)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: controller.cashAccounts
                    .map((account) => accountCard(account, itemWidth))
                    .toList(growable: false),
              );
            },
          ),
      ],
    );
  }

  Widget _cashboxMetric(
    String label,
    double amount,
    String currency,
    IconData icon,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .38),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: scheme.primary),
          const SizedBox(width: 5),
          AppText(
            '$label: ${MoneyFormatter.format(amount, currency: currency)} $currency',
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _cashboxTrend(List<CashTransactionModel> transactions) {
    final scheme = Theme.of(context).colorScheme;
    final ordered = List<CashTransactionModel>.of(transactions)
      ..sort((a, b) => a.transactionDate.compareTo(b.transactionDate));
    final recent = ordered.length <= 10
        ? ordered
        : ordered.sublist(ordered.length - 10);
    final maxValue = recent.fold<double>(
      0,
      (value, item) => item.amount > value ? item.amount : value,
    );
    return SizedBox(
      height: 28,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: recent.isEmpty
            ? <Widget>[
                Expanded(
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      color: scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ]
            : recent
                  .map(
                    (item) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1.5),
                        child: Container(
                          height: maxValue <= 0
                              ? 2
                              : (4 + (20 * item.amount / maxValue)),
                          decoration: BoxDecoration(
                            color:
                                (item.isReceipt ? scheme.primary : scheme.error)
                                    .withValues(alpha: .7),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
      ),
    );
  }

  Future<void> _openCashboxDetail(
    CashAccountModel account,
    CashboxController controller,
  ) async {
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
        builder: (detailContext) {
          final detailAccess = detailContext.read<AccessController>();
          final canViewName = detailAccess.canViewField(
            'cashbox',
            'name',
            viewPermission: 'accounting.view',
          );
          final canViewCurrency = detailAccess.canViewField(
            'cashbox',
            'currency',
            viewPermission: 'accounting.view',
          );
          final titleParts = <String>[
            if (canViewName && account.name.trim().isNotEmpty) account.name,
            if (canViewCurrency && account.currency.trim().isNotEmpty)
              account.currency,
          ];
          return Scaffold(
            appBar: AppBar(
              title: Row(
                children: <Widget>[
                  const Icon(Icons.account_balance_wallet_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppText(
                      titleParts.isEmpty
                          ? (detailContext.l10n.isArabic
                                ? 'تفاصيل الصندوق'
                                : 'Cashbox Details')
                          : titleParts.join(' • '),
                    ),
                  ),
                ],
              ),
            ),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Consumer<CashboxController>(
                  builder: (context, current, _) =>
                      _cashboxDetailBody(account, current),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _cashboxDetailBody(
    CashAccountModel account,
    CashboxController controller,
  ) {
    final ar = context.l10n.isArabic;
    final access = context.read<AccessController>();
    final canViewAmount = access.canViewField(
      'cashbox',
      'amount',
      viewPermission: 'accounting.view',
    );
    final canViewBalance = access.canViewField(
      'cashbox',
      'balance',
      viewPermission: 'accounting.view',
    );
    final canViewCurrency = access.canViewField(
      'cashbox',
      'currency',
      viewPermission: 'accounting.view',
    );
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
    final canEditAccount = access.canPerformAction(
      'cashbox',
      'account.edit',
      legacyPermission: 'accounting.update',
    );
    final canPrintTransaction = access.canPerformAction(
      'cashbox',
      'transaction.print',
      legacyPermission: 'accounting.view',
    );
    final transactions =
        controller.transactions
            .where((transaction) => transaction.cashAccountId == account.id)
            .toList(growable: false)
          ..sort((a, b) => b.transactionDate.compareTo(a.transactionDate));
    final cashIn = transactions
        .where((transaction) => transaction.isReceipt)
        .fold<double>(0, (sum, transaction) => sum + transaction.amount);
    final cashOut = transactions
        .where((transaction) => transaction.isPayment)
        .fold<double>(0, (sum, transaction) => sum + transaction.amount);
    final balance = controller.balances[account.id] ?? account.openingBalance;

    String counterName(CashTransactionModel transaction) {
      for (final ledger in controller.ledgerAccounts) {
        if (ledger.id == transaction.counterAccountId) {
          return '${ledger.code} — ${ledger.name}';
        }
      }
      return transaction.counterAccountId ?? '—';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            if (canViewAmount)
              _cashboxMetric(
                ar ? 'إجمالي الداخل' : 'Total Cash In',
                cashIn,
                canViewCurrency ? account.currency : '',
                Icons.south_west_rounded,
              ),
            if (canViewAmount)
              _cashboxMetric(
                ar ? 'إجمالي الخارج' : 'Total Cash Out',
                cashOut,
                canViewCurrency ? account.currency : '',
                Icons.north_east_rounded,
              ),
            if (canViewBalance)
              _cashboxMetric(
                ar ? 'الرصيد الحالي' : 'Current Balance',
                balance,
                canViewCurrency ? account.currency : '',
                Icons.account_balance_wallet_outlined,
              ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            if (canReceive)
              FilledButton.icon(
                onPressed: () => _openAdd('receipt', cashAccountId: account.id),
                icon: const Icon(Icons.south_west_rounded, size: 17),
                label: AppText(ar ? 'سند قبض' : 'Cash In'),
              ),
            if (canPay)
              OutlinedButton.icon(
                onPressed: () => _openAdd('payment', cashAccountId: account.id),
                icon: const Icon(Icons.north_east_rounded, size: 17),
                label: AppText(ar ? 'سند صرف' : 'Cash Out'),
              ),
            if (canEditAccount)
              OutlinedButton.icon(
                onPressed: () => _editCashAccount(account),
                icon: const Icon(Icons.edit_outlined, size: 17),
                label: AppText(ar ? 'تعديل الصندوق' : 'Edit Cashbox'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: transactions.isEmpty
              ? Center(
                  child: KajFinanceState(
                    icon: Icons.receipt_long_outlined,
                    title: ar
                        ? 'لا توجد حركات لهذا الصندوق'
                        : 'No transactions for this cashbox',
                    message: ar
                        ? 'أنشئ سند قبض أو صرف من هذا الصندوق.'
                        : 'Create a cash-in or cash-out voucher for this cashbox.',
                  ),
                )
              : Scrollbar(
                  child: SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: <DataColumn>[
                          DataColumn(
                            label: AppText(ar ? 'المرجع' : 'Reference'),
                          ),
                          DataColumn(
                            label: AppText(
                              ar ? 'التاريخ والوقت' : 'Date / time',
                            ),
                          ),
                          DataColumn(
                            label: AppText(ar ? 'داخل/خارج' : 'In / Out'),
                          ),
                          DataColumn(label: AppText(ar ? 'المبلغ' : 'Amount')),
                          DataColumn(
                            label: AppText(ar ? 'العملة' : 'Currency'),
                          ),
                          DataColumn(
                            label: AppText(
                              ar ? 'الحساب المقابل' : 'Counter account',
                            ),
                          ),
                          DataColumn(
                            label: AppText(
                              ar ? 'المستند المرتبط' : 'Related document',
                            ),
                          ),
                          DataColumn(label: AppText(ar ? 'المستخدم' : 'User')),
                          DataColumn(
                            label: AppText(ar ? 'الملاحظات' : 'Notes'),
                          ),
                          DataColumn(label: AppText(ar ? 'الحالة' : 'Status')),
                          DataColumn(
                            label: AppText(ar ? 'الإجراءات' : 'Actions'),
                          ),
                        ],
                        rows: transactions
                            .map((transaction) {
                              final canEdit = access.canPerformAction(
                                'cashbox',
                                'transaction.edit',
                                legacyPermission: 'accounting.update',
                              );
                              final canDelete = access.canPerformAction(
                                'cashbox',
                                'transaction.delete',
                                legacyPermission: 'accounting.delete',
                              );
                              return DataRow(
                                cells: <DataCell>[
                                  DataCell(
                                    _securedCashboxField(
                                      'documentNumber',
                                      AppText(transaction.voucherNumber),
                                    ),
                                  ),
                                  DataCell(
                                    _securedCashboxField(
                                      'operationalDate',
                                      AppText(
                                        DateFormat('yyyy-MM-dd HH:mm').format(
                                          transaction.transactionDate.toLocal(),
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    _securedCashboxField(
                                      'transactionType',
                                      AppText(
                                        transaction.isReceipt
                                            ? (ar ? 'داخل' : 'In')
                                            : (ar ? 'خارج' : 'Out'),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    _securedCashboxField(
                                      'amount',
                                      AppText(
                                        MoneyFormatter.format(
                                          transaction.amount,
                                          currency: transaction.currency,
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    _securedCashboxField(
                                      'currency',
                                      AppText(transaction.currency),
                                    ),
                                  ),
                                  DataCell(
                                    _securedCashboxField(
                                      'counterAccount',
                                      AppText(counterName(transaction)),
                                    ),
                                  ),
                                  DataCell(
                                    _securedCashboxField(
                                      'reference',
                                      AppText(
                                        '${transaction.referenceType ?? '—'} • ${transaction.referenceId ?? '—'}',
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    _securedCashboxField(
                                      'performedBy',
                                      AppText(transaction.performedBy ?? '—'),
                                    ),
                                  ),
                                  DataCell(
                                    _securedCashboxField(
                                      'notes',
                                      AppText(transaction.notes ?? '—'),
                                    ),
                                  ),
                                  DataCell(
                                    _securedCashboxField(
                                      'transactionStatus',
                                      AppText(ar ? 'معتمد' : 'Posted'),
                                    ),
                                  ),
                                  DataCell(
                                    Wrap(
                                      spacing: 2,
                                      children: <Widget>[
                                        IconButton(
                                          tooltip: ar ? 'عرض' : 'View',
                                          onPressed: () =>
                                              _showDetails(transaction),
                                          icon: const Icon(
                                            Icons.visibility_outlined,
                                            size: 18,
                                          ),
                                        ),
                                        if (canPrintTransaction)
                                          IconButton(
                                            tooltip: ar ? 'طباعة' : 'Print',
                                            onPressed: () async {
                                              await const CashVoucherPdfService()
                                                  .printVoucher(
                                                    transaction,
                                                    arabic: ar,
                                                    cashAccountName:
                                                        account.name,
                                                    counterAccountName:
                                                        counterName(
                                                          transaction,
                                                        ),
                                                    journalEntryNumber:
                                                        transaction
                                                            .journalEntryId,
                                                  );
                                            },
                                            icon: const Icon(
                                              Icons.print_outlined,
                                              size: 18,
                                            ),
                                          ),
                                        if (canEdit)
                                          IconButton(
                                            tooltip: ar ? 'تعديل' : 'Edit',
                                            onPressed: () =>
                                                _openEdit(transaction),
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                              size: 18,
                                            ),
                                          ),
                                        if (canDelete)
                                          IconButton(
                                            tooltip: ar ? 'حذف' : 'Delete',
                                            onPressed: () =>
                                                _delete(transaction),
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              size: 18,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            })
                            .toList(growable: false),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _showReconciliationDetails({
    required String accountName,
    required String currency,
    required double subledger,
    required double ledger,
    required double difference,
  }) async {
    final reconciled = difference.abs() <= 0.01;
    await showAppWorkspaceDialogBuilder<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const AppText('مطابقة الصندوق مع دفتر الأستاذ'),
        content: SizedBox(
          width: 470,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppText(
                accountName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14),
              FieldPermissionVisibility(
                resource: 'cashbox',
                field: 'balance',
                viewPermission: 'accounting.view',
                child: _reconciliationRow(
                  'رصيد سجل الصندوق',
                  '${MoneyFormatter.format(subledger, currency: currency)} $currency',
                ),
              ),
              FieldPermissionVisibility(
                resource: 'cashbox',
                field: 'ledgerBalance',
                viewPermission: 'accounting.view',
                child: _reconciliationRow(
                  'رصيد دفتر الأستاذ',
                  '${MoneyFormatter.format(ledger, currency: currency)} $currency',
                ),
              ),
              FieldPermissionVisibility(
                resource: 'cashbox',
                field: 'reconciliationDifference',
                viewPermission: 'accounting.view',
                child: _reconciliationRow(
                  'الفرق',
                  '${MoneyFormatter.format(difference, currency: currency)} $currency',
                  emphasize: true,
                  positive: reconciled,
                ),
              ),
              const SizedBox(height: 10),
              AppText(
                reconciled
                    ? 'الرصيد مطابق مع دفتر الأستاذ.'
                    : 'يوجد فرق يحتاج إلى مراجعة القيود أو الرصيد الافتتاحي.',
                style: TextStyle(
                  color: reconciled
                      ? Colors.green.shade700
                      : Colors.red.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const AppText('إغلاق'),
          ),
        ],
      ),
    );
  }

  Widget _reconciliationRow(
    String label,
    String value, {
    bool emphasize = false,
    bool positive = true,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: AppText(label)),
          AppText(
            value,
            style: TextStyle(
              fontWeight: emphasize ? FontWeight.bold : FontWeight.w600,
              color: emphasize
                  ? (positive ? Colors.green.shade700 : Colors.red.shade700)
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editCashAccount(dynamic account) async {
    final changed = await showAppWorkspaceDialogBuilder<bool>(
      context: context,
      barrierDismissible: true,
      useRootNavigator: true,
      builder: (dialogContext) => CashAccountForm(account: account),
    );
    if (changed == true && mounted) {
      await context.read<CashboxController>().loadTransactions();
    }
  }
}
