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
import 'package:quality_line_erp/features/accounting/cashbox/widgets/cash_transaction_card.dart';
import 'package:quality_line_erp/features/accounting/cashbox/services/cash_voucher_pdf_service.dart';
import 'package:quality_line_erp/core/widgets/app_responsive.dart';
import 'add_cash_transaction_page.dart';
import 'cash_account_form.dart';

class CashboxPage extends StatefulWidget {
  const CashboxPage({super.key});

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

  final _searchController = TextEditingController();
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<CashboxController>().loadTransactions();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Consumer<CashboxController>(
          builder: (context, controller, _) {
            final transactions = controller.transactions.where((item) {
              return _filter == 'all' || item.type == _filter;
            }).toList();

            return RefreshIndicator(
              onRefresh: controller.loadTransactions,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                children: [
                  _header(),
                  const SizedBox(height: 16),
                  _cashAccounts(controller),
                  const SizedBox(height: 16),
                  _stats(controller),
                  const SizedBox(height: 16),
                  _actions(),
                  const SizedBox(height: 16),
                  _filters(controller),
                  const SizedBox(height: 16),
                  if (controller.isLoading && controller.transactions.isEmpty)
                    KajFinanceState(
                      icon: Icons.sync_rounded,
                      title: context.l10n.isArabic
                          ? 'جارٍ مزامنة الصناديق'
                          : 'Synchronizing cashboxes',
                      message: context.l10n.isArabic
                          ? 'يتم تحميل الحركات والأرصدة المرتبطة.'
                          : 'Loading linked transactions and balances.',
                    )
                  else if (controller.errorMessage != null &&
                      controller.transactions.isEmpty)
                    _message(Icons.error_outline, controller.errorMessage!)
                  else if (transactions.isEmpty)
                    KajFinanceState(
                      icon: Icons.account_balance_wallet_outlined,
                      title: context.l10n.isArabic
                          ? 'لا توجد حركات مطابقة'
                          : 'No matching transactions',
                      message: context.l10n.isArabic
                          ? 'غيّر الفلاتر أو أنشئ سندًا ماليًا جديدًا.'
                          : 'Adjust the filters or create a new financial voucher.',
                    )
                  else
                    ...transactions.map(
                      (transaction) => CashTransactionCard(
                        transaction: transaction,
                        onView: () => _showDetails(transaction),
                        onPrint: () async {
                          String? cashAccountName;
                          for (final account in controller.cashAccounts) {
                            if (account.id == transaction.cashAccountId) {
                              cashAccountName = account.name;
                              break;
                            }
                          }
                          String? counterAccountName;
                          for (final account in controller.ledgerAccounts) {
                            if (account.id == transaction.counterAccountId) {
                              counterAccountName =
                                  '${account.code} — ${account.name}';
                              break;
                            }
                          }
                          await const CashVoucherPdfService().printVoucher(
                            transaction,
                            arabic: context.l10n.isArabic,
                            cashAccountName: cashAccountName,
                            counterAccountName: counterAccountName,
                            journalEntryNumber: transaction.journalEntryId,
                          );
                        },
                        onEdit: () => _openEdit(transaction),
                        onDelete:
                            PermissionAction.allowed(
                              context,
                              'accounting.delete',
                            )
                            ? () => _delete(transaction)
                            : null,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
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
    switch (value) {
      case 'bank_transfer':
        return 'تحويل مصرفي';
      case 'card':
        return 'بطاقة';
      case 'cheque':
        return 'صك';
      default:
        return 'نقدي';
    }
  }

  Widget _header() {
    final isArabic = context.l10n.isArabic;
    return KajFinanceSection(
      title: isArabic
          ? 'الصناديق والحسابات النقدية'
          : 'Cashboxes & Cash Accounts',
      subtitle: isArabic
          ? 'إدارة سندات القبض والصرف والتحويلات متعددة العملات.'
          : 'Manage receipts, payments and multi-currency transfers.',
      icon: Icons.account_balance_wallet_outlined,
      child: const SizedBox.shrink(),
    );
  }

  Widget _stats(CashboxController controller) {
    final usd = controller.usdSummary;
    final iqd = controller.iqdSummary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 900
            ? (constraints.maxWidth - 36) / 4
            : constraints.maxWidth >= 520
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _stat(
              'رصيد USD',
              MoneyFormatter.format(usd['balance'] ?? 0, currency: 'USD'),
              Icons.attach_money,
              width,
            ),
            _stat(
              'مقبوضات USD',
              MoneyFormatter.format(usd['receipts'] ?? 0, currency: 'USD'),
              Icons.south_west_rounded,
              width,
            ),
            _stat(
              'رصيد IQD',
              MoneyFormatter.format(iqd['balance'] ?? 0, currency: 'IQD'),
              Icons.payments_outlined,
              width,
            ),
            _stat(
              'مصروفات IQD',
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
    return SizedBox(
      width: width,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      title,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 4),
                    AppText(
                      value,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actions() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final receipt = FilledButton.icon(
          onPressed: () => _openAdd('receipt'),
          icon: const Icon(Icons.south_west_rounded),
          label: const AppText('سند قبض'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.green.shade700,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 40),
          ),
        );
        final payment = FilledButton.icon(
          onPressed: () => _openAdd('payment'),
          icon: const Icon(Icons.north_east_rounded),
          label: const AppText('سند صرف'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red.shade700,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 40),
          ),
        );
        final transfer = FilledButton.icon(
          onPressed: _openTransfer,
          icon: const Icon(Icons.swap_horiz_rounded),
          label: const AppText(
            '\u062a\u062d\u0648\u064a\u0644 \u0628\u064a\u0646 \u0627\u0644\u0635\u0646\u0627\u062f\u064a\u0642',
          ),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
        );
        if (constraints.maxWidth >= 780) {
          return Row(
            children: [
              Expanded(child: receipt),
              const SizedBox(width: 12),
              Expanded(child: payment),
              const SizedBox(width: 12),
              Expanded(child: transfer),
            ],
          );
        }
        return Column(
          children: [
            receipt,
            const SizedBox(height: 12),
            payment,
            const SizedBox(height: 12),
            transfer,
          ],
        );
      },
    );
  }

  Widget _filters(CashboxController controller) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final search = TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: AppTranslation.translate('بحث'),
                hintText: AppTranslation.translate(
                  'رقم السند، التصنيف، الجهة أو الملاحظات',
                ),
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: controller.searchTransactions,
            );
            final filter = DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _filter,
              decoration: InputDecoration(
                labelText: AppTranslation.translate('نوع الحركة'),
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'all', child: AppText('الكل')),
                DropdownMenuItem(
                  value: 'receipt',
                  child: AppText('سندات القبض'),
                ),
                DropdownMenuItem(
                  value: 'payment',
                  child: AppText('سندات الصرف'),
                ),
              ],
              onChanged: (value) => setState(() => _filter = value ?? 'all'),
            );
            if (constraints.maxWidth >= 700) {
              return Row(
                children: [
                  Expanded(flex: 2, child: search),
                  const SizedBox(width: 12),
                  Expanded(child: filter),
                ],
              );
            }
            return Column(
              children: [search, const SizedBox(height: 12), filter],
            );
          },
        ),
      ),
    );
  }

  Widget _message(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.all(60),
      child: Column(
        children: [
          Icon(icon, size: 64, color: Colors.grey),
          const SizedBox(height: 14),
          AppText(text, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Future<void> _openTransfer() async {
    if (!await PermissionAction.require(context, 'accounting.update')) return;
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
    return number == null || number <= 0 ? 'أدخل قيمة أكبر من صفر' : null;
  }

  Future<void> _openAdd(String type) async {
    final result = await showAppModuleDialog<bool>(
      context: context,
      title: type == 'receipt' ? 'إضافة سند قبض' : 'إضافة سند صرف',
      windowKey: 'cashbox:add:$type',
      builder: (_) => AddCashTransactionPage(initialType: type),
    );
    if (mounted && result == true) {
      await context.read<CashboxController>().loadTransactions();
    }
  }

  Future<void> _openEdit(CashTransactionModel transaction) async {
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
    if (!await PermissionAction.require(context, 'accounting.delete')) return;
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
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined),
                const SizedBox(width: 8),
                const Expanded(
                  child: AppText(
                    'الصناديق النقدية وأرصدتها',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _editCashAccount(null),
                  icon: const Icon(Icons.add),
                  label: const AppText('صندوق جديد'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (controller.cashAccounts.isEmpty)
              const AppText('لا توجد صناديق نقدية معرفة.')
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: controller.cashAccounts.map((account) {
                  final reconciliation = controller.reconciliation[account.id];
                  final subledger =
                      reconciliation?['subledger'] ??
                      (controller.balances[account.id] ??
                          account.openingBalance);
                  final ledger = reconciliation?['ledger'] ?? 0;
                  final difference = reconciliation?['difference'] ?? 0;
                  final isReconciled = difference.abs() <= 0.01;
                  return SizedBox(
                    width: 320,
                    child: ListTile(
                      tileColor: Theme.of(context).cardColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Theme.of(context).dividerColor),
                      ),
                      leading: Icon(
                        account.type == 'bank'
                            ? Icons.account_balance_outlined
                            : Icons.payments_outlined,
                      ),
                      title: FieldPermissionVisibility(
                        resource: 'cashbox',
                        field: 'name',
                        viewPermission: 'accounting.view',
                        child: AppText(account.name),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FieldPermissionVisibility(
                            resource: 'cashbox',
                            field: 'balance',
                            viewPermission: 'accounting.view',
                            child: AppText(
                              '${MoneyFormatter.format(controller.balances[account.id] ?? account.openingBalance, currency: account.currency)} ${account.currency}${account.isActive ? '' : ' — غير فعال'}',
                            ),
                          ),
                          const SizedBox(height: 3),
                          FieldPermissionVisibility(
                            resource: 'cashbox',
                            field: 'reconciliationDifference',
                            viewPermission: 'accounting.view',
                            child: AppText(
                              isReconciled
                                  ? 'مطابق مع دفتر الأستاذ'
                                  : 'فرق مع دفتر الأستاذ: ${MoneyFormatter.format(difference, currency: account.currency)} ${account.currency}',
                              style: TextStyle(
                                fontSize: 12,
                                color: isReconciled
                                    ? Colors.green.shade700
                                    : Colors.red.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      onTap:
                          context.read<AccessController>().canViewField(
                            'cashbox',
                            'reconciliation',
                            viewPermission: 'accounting.view',
                          )
                          ? () => _showReconciliationDetails(
                              accountName: account.name,
                              currency: account.currency,
                              subledger: subledger,
                              ledger: ledger,
                              difference: difference,
                            )
                          : null,
                      trailing: Wrap(
                        spacing: 2,
                        children: [
                          FieldPermissionVisibility(
                            resource: 'cashbox',
                            field: 'reconciliation',
                            viewPermission: 'accounting.view',
                            child: IconButton(
                              tooltip: AppTranslation.translate(
                                'تفاصيل المطابقة',
                              ),
                              icon: const Icon(Icons.balance_outlined),
                              onPressed: () => _showReconciliationDetails(
                                accountName: account.name,
                                currency: account.currency,
                                subledger: subledger,
                                ledger: ledger,
                                difference: difference,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: AppTranslation.translate('تعديل الصندوق'),
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _editCashAccount(account),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
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
