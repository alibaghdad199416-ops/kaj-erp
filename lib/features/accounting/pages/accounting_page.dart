import 'dart:async';
import 'package:quality_line_erp/core/utils/thousands_input_formatter.dart';

import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';
import 'package:quality_line_erp/core/widgets/app_dialog.dart';
import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';
import 'package:quality_line_erp/core/widgets/app_back_button.dart';
import 'package:provider/provider.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';

import 'package:quality_line_erp/features/accounting/controllers/accounting_controller.dart';
import 'package:quality_line_erp/features/accounting/models/journal_entry_model.dart';
import 'package:quality_line_erp/features/accounting/models/journal_line_model.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'account_statement_page.dart';
import 'add_journal_entry_page.dart';

class AccountingPage extends StatefulWidget {
  const AccountingPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<AccountingPage> createState() => _AccountingPageState();
}

class _AccountingPageState extends State<AccountingPage> {
  final _searchController = TextEditingController();
  String _currencyFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<AccountingController>().loadAccounting();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openAdd() async {
    final result = await showAppWorkspaceDialog<bool>(
      context: context,
      child: const AddJournalEntryPage(),
    );
    if (result == true && mounted) {
      await context.read<AccountingController>().loadAccounting();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        appBar: widget.embedded
            ? null
            : AppBar(
                leading: const AppBackButton(),
                title: const AppText('المحاسبة'),
                actions: [
                  IconButton(
                    tooltip: AppTranslation.translate('كشف حساب'),
                    onPressed: () async {
                      await showAppWorkspaceDialog<void>(
                        context: context,
                        child: const AccountStatementPage(),
                      );
                    },
                    icon: const Icon(Icons.receipt_long_outlined),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
        body: Consumer<AccountingController>(
          builder: (context, controller, _) {
            if (controller.isLoading && controller.entries.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            return RefreshIndicator(
              onRefresh: controller.loadAccounting,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (!widget.embedded) ...[
                    _header(),
                    const SizedBox(height: 16),
                  ],
                  _summary(controller),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: AppTranslation.translate(
                              'البحث في القيود',
                            ),
                            prefixIcon: const Icon(Icons.search),
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        onPressed: _openAdd,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const AppText('قيد جديد'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: ['ALL', 'IQD', 'USD']
                        .map(
                          (currency) => ChoiceChip(
                            selected: _currencyFilter == currency,
                            onSelected: (_) =>
                                setState(() => _currencyFilter = currency),
                            label: AppText(
                              currency == 'ALL' ? 'كل العملات' : currency,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 16),
                  if (controller.errorMessage != null)
                    Card(
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: AppText(controller.errorMessage!),
                      ),
                    ),
                  Builder(
                    builder: (context) {
                      final query = _searchController.text.trim().toLowerCase();
                      final entries = controller.entries
                          .where((entry) {
                            final matchesCurrency =
                                _currencyFilter == 'ALL' ||
                                entry.currency == _currencyFilter;
                            final matchesQuery =
                                query.isEmpty ||
                                entry.entryNumber.toLowerCase().contains(
                                  query,
                                ) ||
                                entry.description.toLowerCase().contains(
                                  query,
                                ) ||
                                (entry.referenceType ?? '')
                                    .toLowerCase()
                                    .contains(query);
                            return matchesCurrency && matchesQuery;
                          })
                          .toList(growable: false);
                      if (entries.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(50),
                          child: Center(child: AppText('لا توجد قيود مطابقة.')),
                        );
                      }
                      return Column(
                        children: entries
                            .map(
                              (entry) => _entryCard(context, controller, entry),
                            )
                            .toList(growable: false),
                      );
                    },
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.white,
            child: Icon(Icons.account_balance_outlined, color: Colors.black),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  'النظام المحاسبي',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                AppText(
                  'دليل الحسابات والقيود اليومية وميزان المراجعة.',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summary(AccountingController controller) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _summaryCard('الحسابات', controller.accounts.length.toString()),
        _summaryCard('القيود', controller.entries.length.toString()),
        _summaryCard(
          'ميزان USD',
          '${MoneyFormatter.format(controller.usdTrial['debit'] ?? 0, currency: 'USD')} / ${MoneyFormatter.format(controller.usdTrial['credit'] ?? 0, currency: 'USD')}',
        ),
        _summaryCard(
          'ميزان IQD',
          '${MoneyFormatter.format(controller.iqdTrial['debit'] ?? 0, currency: 'IQD')} / ${MoneyFormatter.format(controller.iqdTrial['credit'] ?? 0, currency: 'IQD')}',
        ),
        _currencySubledgerCard(
          context,
          'ذمم العملاء',
          controller.receivablesByCurrency,
          Icons.person_outline,
          receivables: true,
        ),
        _currencySubledgerCard(
          context,
          'ذمم الموردين',
          controller.payablesByCurrency,
          Icons.local_shipping_outlined,
          receivables: false,
        ),
      ],
    );
  }

  Widget _currencySubledgerCard(
    BuildContext context,
    String title,
    Map<String, double> balances,
    IconData icon, {
    required bool receivables,
  }) {
    final currencies =
        balances.entries
            .where((entry) => entry.value.abs() > 0.005)
            .toList(growable: false)
          ..sort((a, b) => a.key.compareTo(b.key));
    return SizedBox(
      width: 220,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showSubledgerDetails(
            context,
            title: title,
            receivables: receivables,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 17),
                    const SizedBox(width: 6),
                    Expanded(
                      child: AppText(
                        title,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                if (currencies.isEmpty)
                  const AppText(
                    'لا توجد أرصدة مستحقة',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  )
                else
                  ...currencies.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: AppText(
                        MoneyFormatter.format(entry.value, currency: entry.key),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 3),
                const AppText(
                  'الأرصدة معروضة حسب عملة المستند دون تحويل.',
                  maxLines: 2,
                  style: TextStyle(fontSize: 9.5, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    AppText('عرض التفاصيل', style: TextStyle(fontSize: 9.5)),
                    SizedBox(width: 3),
                    Icon(Icons.open_in_new, size: 13),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showSubledgerDetails(
    BuildContext context, {
    required String title,
    required bool receivables,
  }) async {
    final controller = context.read<AccountingController>();
    await showAppWorkspaceDialogBuilder<void>(
      context: context,
      builder: (dialogContext) => Scaffold(
        body: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 620),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      receivables
                          ? Icons.person_outline
                          : Icons.local_shipping_outlined,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppText(
                        '$title حسب الطرف والعملة',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: AppTranslation.translate('إغلاق'),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const AppText(
                  'لا يتم جمع العملات أو تحويلها داخل كشف الذمم.',
                  style: TextStyle(color: Colors.grey, fontSize: 11),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: controller.loadPartnerSubledgerDetails(
                      receivables: receivables,
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: AppText(
                            userFacingError(
                              snapshot.error!,
                              isArabic: context.l10n.isArabic,
                              arabicFallback: 'تعذر تحميل تفاصيل الذمم.',
                              englishFallback:
                                  'Unable to load balance details.',
                            ),
                          ),
                        );
                      }
                      final rows =
                          snapshot.data ?? const <Map<String, dynamic>>[];
                      if (rows.isEmpty) {
                        return const Center(
                          child: AppText('لا توجد أرصدة مستحقة.'),
                        );
                      }
                      return ListView.separated(
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          final partyId = (row['party_id'] ?? '').toString();
                          final partyName = (row['party_name'] ?? '')
                              .toString();
                          final currency = (row['currency'] ?? '')
                              .toString()
                              .trim()
                              .toUpperCase();
                          final validCurrency =
                              currency == 'USD' || currency == 'IQD';
                          final amount =
                              (row['outstanding_amount'] as num?)?.toDouble() ??
                              0;
                          final total =
                              (row['total_amount'] as num?)?.toDouble() ?? 0;
                          final paid =
                              (row['paid_amount'] as num?)?.toDouble() ?? 0;
                          final count =
                              (row['document_count'] as num?)?.toInt() ?? 0;
                          final payments =
                              (row['payment_count'] as num?)?.toInt() ?? 0;
                          final overdue =
                              (row['overdue_document_count'] as num?)
                                  ?.toInt() ??
                              0;
                          final progress = total <= 0
                              ? 0.0
                              : (paid / total).clamp(0.0, 1.0);
                          final dueRaw = row['oldest_due_date']?.toString();
                          final dueDate = dueRaw == null
                              ? null
                              : DateTime.tryParse(dueRaw)?.toLocal();
                          final dueLabel = dueDate == null
                              ? ''
                              : MaterialLocalizations.of(
                                  context,
                                ).formatShortDate(dueDate);
                          return ListTile(
                            dense: true,
                            onTap: partyId.isEmpty || !validCurrency
                                ? null
                                : () => _showSubledgerDocuments(
                                    dialogContext,
                                    controller: controller,
                                    receivables: receivables,
                                    partyId: partyId,
                                    partyName: partyName,
                                    currency: currency,
                                  ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            leading: CircleAvatar(
                              radius: 18,
                              child: AppText(
                                validCurrency ? currency : '—',
                                style: const TextStyle(fontSize: 9),
                              ),
                            ),
                            title: AppText(
                              partyName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AppText(
                                  '$count مستند مستحق • $payments دفعة${dueLabel.isEmpty ? '' : ' • أقدم استحقاق $dueLabel'}',
                                  style: const TextStyle(fontSize: 10.5),
                                ),
                                if (overdue > 0)
                                  AppText(
                                    '$overdue مستند متأخر',
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                LinearProgressIndicator(value: progress),
                              ],
                            ),
                            trailing: SizedBox(
                              width: 205,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        AppText(
                                          MoneyFormatter.format(
                                            amount,
                                            currency: currency,
                                          ),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        AppText(
                                          'مدفوع ${MoneyFormatter.format(paid, currency: currency)}',
                                          style: const TextStyle(
                                            fontSize: 9.5,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: AppTranslation.translateForLocale(
                                      'إدارة الدفعات غير المخصصة',
                                      context.l10n.locale.languageCode,
                                    ),
                                    onPressed: partyId.isEmpty || !validCurrency
                                        ? null
                                        : () => _showPartnerUnappliedPayments(
                                            dialogContext,
                                            controller: controller,
                                            receivables: receivables,
                                            partyId: partyId,
                                            partyName: partyName,
                                            currency: currency,
                                          ),
                                    icon: const Icon(
                                      Icons.account_balance_wallet_outlined,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showPartnerUnappliedPayments(
    BuildContext context, {
    required AccountingController controller,
    required bool receivables,
    required String partyId,
    required String partyName,
    required String currency,
  }) async {
    List<Map<String, dynamic>> rows = const [];
    bool loading = true;
    String? error;

    Future<void> load(StateSetter setDialogState) async {
      if (!context.mounted) return;
      setDialogState(() {
        loading = true;
        error = null;
      });
      try {
        final result = await controller.loadPartnerUnappliedPayments(
          receivables: receivables,
          partyId: partyId,
          currency: currency,
        );
        if (!context.mounted) return;
        setDialogState(() => rows = result);
      } catch (caught) {
        if (!context.mounted) return;
        setDialogState(() {
          error = userFacingError(
            caught,
            isArabic: context.l10n.isArabic,
            arabicFallback: 'تعذر تحميل الدفعات غير المخصصة.',
            englishFallback: 'Unable to load unapplied payments.',
          );
        });
      } finally {
        if (context.mounted) setDialogState(() => loading = false);
      }
    }

    await showAppWorkspaceDialogBuilder<void>(
      context: context,
      builder: (paymentDialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (loading && rows.isEmpty && error == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (paymentDialogContext.mounted) {
                unawaited(load(setDialogState));
              }
            });
          }
          return Scaffold(
            body: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760, maxHeight: 620),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.account_balance_wallet_outlined),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AppText(
                            context.l10n.isArabic
                                ? 'الدفعات غير المخصصة — $partyName ($currency)'
                                : 'Unapplied payments — $partyName ($currency)',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: AppTranslation.translate('تحديث'),
                          onPressed: loading
                              ? null
                              : () => load(setDialogState),
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                        IconButton(
                          tooltip: AppTranslation.translate('إغلاق'),
                          onPressed: () =>
                              Navigator.of(paymentDialogContext).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    AppText(
                      context.l10n.isArabic
                          ? 'هذه الدفعات بقيت في حساب العميل أو المورد بعد حذف المستند. يمكن تعديلها أو حذفها من هنا.'
                          : 'These payments remain on the partner account after document deletion. They can be edited or deleted here.',
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: loading
                          ? const Center(child: CircularProgressIndicator())
                          : error != null
                          ? Center(child: AppText(error!))
                          : rows.isEmpty
                          ? Center(
                              child: AppText(
                                context.l10n.isArabic
                                    ? 'لا توجد دفعات غير مخصصة.'
                                    : 'No unapplied payments.',
                              ),
                            )
                          : ListView.separated(
                              itemCount: rows.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final row = rows[index];
                                final id = (row['transaction_id'] ?? '')
                                    .toString();
                                final voucher = (row['voucher_number'] ?? id)
                                    .toString();
                                final amount =
                                    (row['amount'] as num?)?.toDouble() ?? 0;
                                final notes = (row['notes'] ?? '').toString();
                                final rawDate = row['transaction_date']
                                    ?.toString();
                                final date = DateTime.tryParse(
                                  rawDate ?? '',
                                )?.toLocal();
                                final dateLabel = date == null
                                    ? '—'
                                    : MaterialLocalizations.of(
                                        context,
                                      ).formatShortDate(date);
                                return ListTile(
                                  leading: const CircleAvatar(
                                    child: Icon(Icons.payments_outlined),
                                  ),
                                  title: AppText(voucher),
                                  subtitle: AppText(
                                    '$dateLabel${notes.isEmpty ? '' : ' • $notes'}',
                                  ),
                                  trailing: Wrap(
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      AppText(
                                        MoneyFormatter.format(
                                          amount,
                                          currency: currency,
                                        ),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: AppTranslation.translate(
                                          'تعديل',
                                        ),
                                        onPressed: () async {
                                          if (!await PermissionAction.require(
                                            paymentDialogContext,
                                            'accounting.update',
                                          )) {
                                            return;
                                          }
                                          if (!paymentDialogContext.mounted) {
                                            return;
                                          }
                                          final amountLabel =
                                              '${AppTranslation.translate('المبلغ')} ($currency)';
                                          final amountController =
                                              TextEditingController(
                                                text: amount.toString(),
                                              );
                                          final notesController =
                                              TextEditingController(
                                                text: notes,
                                              );
                                          DateTime selectedDate =
                                              date ?? DateTime.now();
                                          final accepted = await showDialog<bool>(
                                            context: paymentDialogContext,
                                            builder: (editContext) => StatefulBuilder(
                                              builder: (context, setEditState) => AlertDialog(
                                                title: AppText(
                                                  context.l10n.isArabic
                                                      ? 'تعديل الدفعة غير المخصصة'
                                                      : 'Edit unapplied payment',
                                                ),
                                                content: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    TextField(
                                                      controller:
                                                          amountController,
                                                      keyboardType:
                                                          const TextInputType.numberWithOptions(
                                                            decimal: true,
                                                          ),

                                                      inputFormatters:
                                                          <TextInputFormatter>[
                                                            ThousandsInputFormatter(
                                                              decimalDigits: 2,
                                                            ),
                                                          ],
                                                      decoration:
                                                          InputDecoration(
                                                            labelText:
                                                                amountLabel,
                                                          ),
                                                    ),
                                                    const SizedBox(height: 10),
                                                    ListTile(
                                                      contentPadding:
                                                          EdgeInsets.zero,
                                                      title: AppText(
                                                        context.l10n.isArabic
                                                            ? 'تاريخ الدفعة'
                                                            : 'Payment date',
                                                      ),
                                                      subtitle: AppText(
                                                        MaterialLocalizations.of(
                                                          context,
                                                        ).formatShortDate(
                                                          selectedDate,
                                                        ),
                                                      ),
                                                      trailing: const Icon(
                                                        Icons
                                                            .calendar_month_outlined,
                                                      ),
                                                      onTap: () async {
                                                        final picked =
                                                            await showDatePicker(
                                                              context: context,
                                                              initialDate:
                                                                  selectedDate,
                                                              firstDate:
                                                                  DateTime(
                                                                    2000,
                                                                  ),
                                                              lastDate:
                                                                  DateTime(
                                                                    2100,
                                                                  ),
                                                            );
                                                        if (picked != null) {
                                                          setEditState(
                                                            () => selectedDate =
                                                                picked,
                                                          );
                                                        }
                                                      },
                                                    ),
                                                    TextField(
                                                      controller:
                                                          notesController,
                                                      maxLines: 3,
                                                      decoration: InputDecoration(
                                                        labelText:
                                                            AppTranslation.translate(
                                                              'ملاحظات',
                                                            ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          editContext,
                                                          false,
                                                        ),
                                                    child: AppText(
                                                      AppTranslation.translate(
                                                        'إلغاء',
                                                      ),
                                                    ),
                                                  ),
                                                  FilledButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          editContext,
                                                          true,
                                                        ),
                                                    child: AppText(
                                                      AppTranslation.translate(
                                                        'حفظ',
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                          final nextAmount = double.tryParse(
                                            amountController.text.trim(),
                                          );
                                          final nextNotes = notesController.text
                                              .trim();
                                          amountController.dispose();
                                          notesController.dispose();
                                          if (accepted != true ||
                                              nextAmount == null ||
                                              nextAmount <= 0) {
                                            return;
                                          }
                                          await controller
                                              .updatePartnerUnappliedPayment(
                                                transactionId: id,
                                                amount: nextAmount,
                                                transactionDate: selectedDate,
                                                notes: nextNotes,
                                              );
                                          await load(setDialogState);
                                        },
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                      IconButton(
                                        tooltip: AppTranslation.translate(
                                          'حذف',
                                        ),
                                        onPressed: () async {
                                          if (!await PermissionAction.require(
                                            paymentDialogContext,
                                            'accounting.delete',
                                          )) {
                                            return;
                                          }
                                          if (!paymentDialogContext.mounted) {
                                            return;
                                          }
                                          final accepted = await showDialog<bool>(
                                            context: paymentDialogContext,
                                            builder: (deleteContext) => AlertDialog(
                                              title: AppText(
                                                context.l10n.isArabic
                                                    ? 'حذف الدفعة المالية'
                                                    : 'Delete payment',
                                              ),
                                              content: AppText(
                                                context.l10n.isArabic
                                                    ? 'سيُحذف سند الصندوق والقيد المرتبط بهذه الدفعة. لا يمكن التراجع.'
                                                    : 'The cash voucher and linked journal will be deleted. This cannot be undone.',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                        deleteContext,
                                                        false,
                                                      ),
                                                  child: AppText(
                                                    AppTranslation.translate(
                                                      'إلغاء',
                                                    ),
                                                  ),
                                                ),
                                                FilledButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                        deleteContext,
                                                        true,
                                                      ),
                                                  child: AppText(
                                                    AppTranslation.translate(
                                                      'حذف',
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (accepted != true) return;
                                          await controller
                                              .deletePartnerUnappliedPayment(
                                                id,
                                              );
                                          await load(setDialogState);
                                        },
                                        icon: Icon(
                                          Icons.delete_forever_outlined,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.error,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showSubledgerDocuments(
    BuildContext context, {
    required AccountingController controller,
    required bool receivables,
    required String partyId,
    required String partyName,
    required String currency,
  }) async {
    await showAppWorkspaceDialogBuilder<void>(
      context: context,
      builder: (documentDialogContext) => Scaffold(
        body: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 590),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.description_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppText(
                        'المستندات المستحقة — $partyName ($currency)',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: AppTranslation.translate('إغلاق'),
                      onPressed: () =>
                          Navigator.of(documentDialogContext).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const AppText(
                  'القيم معروضة بعملة المستند الأصلية دون تحويل، ولا تظهر أي مراجع تقنية.',
                  style: TextStyle(color: Colors.grey, fontSize: 11),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: controller.loadPartnerSubledgerDocuments(
                      receivables: receivables,
                      partyId: partyId,
                      currency: currency,
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: AppText(
                            'تعذر تحميل مستندات الذمم: ${snapshot.error}',
                          ),
                        );
                      }
                      final rows =
                          snapshot.data ?? const <Map<String, dynamic>>[];
                      if (rows.isEmpty) {
                        return const Center(
                          child: AppText('لا توجد مستندات مستحقة.'),
                        );
                      }
                      return ListView.separated(
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          final number = (row['document_number'] ?? 'بدون رقم')
                              .toString();
                          final total =
                              (row['total_amount'] as num?)?.toDouble() ?? 0;
                          final paid =
                              (row['paid_amount'] as num?)?.toDouble() ?? 0;
                          final outstanding =
                              (row['outstanding_amount'] as num?)?.toDouble() ??
                              0;
                          final payments =
                              (row['payment_count'] as num?)?.toInt() ?? 0;
                          final overdue = row['is_overdue'] == true;
                          DateTime? readDate(Object? raw) => DateTime.tryParse(
                            raw?.toString() ?? '',
                          )?.toLocal();
                          final documentDate = readDate(row['document_date']);
                          final dueDate = readDate(row['due_date']);
                          final localizations = MaterialLocalizations.of(
                            context,
                          );
                          final documentLabel = documentDate == null
                              ? '—'
                              : localizations.formatShortDate(documentDate);
                          final dueLabel = dueDate == null
                              ? '—'
                              : localizations.formatShortDate(dueDate);
                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            leading: CircleAvatar(
                              radius: 18,
                              child: Icon(
                                overdue
                                    ? Icons.warning_amber_rounded
                                    : Icons.receipt_long_outlined,
                                size: 18,
                              ),
                            ),
                            title: AppText(
                              number,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: AppText(
                              'التاريخ $documentLabel • الاستحقاق $dueLabel • $payments دفعة',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: overdue ? Colors.red : Colors.grey,
                              ),
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                AppText(
                                  MoneyFormatter.format(
                                    outstanding,
                                    currency: currency,
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                AppText(
                                  'الإجمالي ${MoneyFormatter.format(total, currency: currency)} • المدفوع ${MoneyFormatter.format(paid, currency: currency)}',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryCard(String title, String value) {
    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.grey, fontSize: 10.5),
              ),
              const SizedBox(height: 3),
              AppText(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _entryCard(
    BuildContext context,
    AccountingController controller,
    JournalEntryModel entry,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: AppText(
          '${entry.entryNumber} — ${entry.description}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(
              '${entry.entryDate.toLocal().toString().split(' ').first} • ${entry.currency} • ${MoneyFormatter.format(entry.totalDebit, currency: entry.currency)}',
            ),
            if ((entry.referenceType ?? '').trim().isNotEmpty)
              FieldPermissionVisibility(
                resource: 'accounting',
                field: 'reference',
                viewPermission: 'accounting.view',
                child: AppText(
                  '${context.l10n.isArabic ? 'المرجع' : 'Reference'}: ${entry.referenceType}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (PermissionAction.allowed(context, 'accounting.update'))
              IconButton(
                tooltip: AppTranslation.translate('تعديل القيد'),
                onPressed: () => _editEntry(context, controller, entry),
                icon: const Icon(Icons.edit_outlined),
              ),
            if (PermissionAction.allowed(context, 'accounting.delete'))
              IconButton(
                tooltip: AppTranslation.translate('حذف القيد'),
                onPressed: () => _confirmDelete(context, controller, entry),
                icon: const Icon(Icons.delete_outline, color: Colors.red),
              ),
          ],
        ),
        children: [
          FutureBuilder(
            future: controller.loadEntryLines(entry.id),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: AppText(
                    userFacingError(
                      snapshot.error!,
                      isArabic: context.l10n.isArabic,
                      arabicFallback:
                          'تعذر تحميل تفاصيل القيد. تحقق من صلاحيات وجدول أسطر القيود.',
                      englishFallback: 'Unable to load journal entry lines.',
                    ),
                  ),
                );
              }
              final lines = snapshot.data ?? <JournalLineModel>[];
              if (lines.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: AppText('لا توجد أسطر مرتبطة بهذا القيد.'),
                );
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: lines
                      .map(
                        (line) => ListTile(
                          dense: true,
                          title: AppText(
                            '${line.accountCode} - ${line.accountName}',
                          ),
                          subtitle: line.description == null
                              ? null
                              : AppText(line.description!),
                          trailing: AppText(
                            line.debit > 0
                                ? 'مدين ${MoneyFormatter.format(line.debit, currency: entry.currency)}'
                                : 'دائن ${MoneyFormatter.format(line.credit, currency: entry.currency)}',
                          ),
                        ),
                      )
                      .toList(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _editEntry(
    BuildContext context,
    AccountingController controller,
    JournalEntryModel entry,
  ) async {
    try {
      final lines = await controller.loadEntryLines(entry.id);
      if (!context.mounted) return;
      final changed = await showAppWorkspaceDialog<bool>(
        context: context,
        child: AddJournalEntryPage(entry: entry, initialLines: lines),
      );
      if (changed == true && context.mounted) {
        await controller.loadAccounting();
      }
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            userFacingError(error, isArabic: context.l10n.isArabic),
          ),
        ),
      );
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AccountingController controller,
    JournalEntryModel entry,
  ) async {
    if (!await PermissionAction.require(context, 'accounting.delete')) return;
    if (!context.mounted) return;
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'حذف القيد',
      message:
          entry.referenceType == null ||
              entry.referenceType!.trim().isEmpty ||
              const {
                'manual',
                'manual_journal',
              }.contains(entry.referenceType!.trim().toLowerCase())
          ? 'هل تريد حذف القيد ${entry.entryNumber}؟'
          : 'هذا القيد مرتبط بمستند تشغيلي. سيُحذف المستند المصدر وتُعكس ارتباطاته المحاسبية والمخزنية. هل تريد المتابعة؟',
      confirmLabel: 'حذف',
      destructive: true,
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.deleteEntry(entry.id);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            userFacingError(
              error,
              isArabic: context.l10n.isArabic,
              arabicFallback: 'تعذر حذف القيد أو المستند المصدر المرتبط.',
              englishFallback:
                  'Unable to delete the journal entry or its source document.',
            ),
          ),
        ),
      );
    }
  }
}
