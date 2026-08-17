import 'package:flutter/material.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';
import 'package:provider/provider.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';

import 'package:quality_line_erp/features/accounting/controllers/accounting_controller.dart';
import 'package:quality_line_erp/features/accounting/models/account_model.dart';
import 'package:quality_line_erp/features/accounting/models/account_statement_result.dart';
import 'package:quality_line_erp/design_system/kaj_finance_stage7_components.dart';
import 'package:quality_line_erp/design_system/kaj_shell_components.dart';

class AccountStatementPage extends StatefulWidget {
  const AccountStatementPage({super.key});

  @override
  State<AccountStatementPage> createState() => _AccountStatementPageState();
}

class _AccountStatementPageState extends State<AccountStatementPage> {
  AccountModel? _selectedAccount;
  DateTime _fromDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _toDate = DateTime.now();
  Future<AccountStatementResult>? _statementFuture;

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _fromDate : _toDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
        if (_toDate.isBefore(_fromDate)) _toDate = picked;
      } else {
        _toDate = picked;
      }
      _statementFuture = null;
    });
  }

  void _loadStatement() {
    final account = _selectedAccount;
    if (account == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            context.l10n.isArabic
                ? 'يرجى اختيار الحساب أولًا.'
                : 'Select an account first.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _statementFuture = context
          .read<AccountingController>()
          .loadAccountStatement(
            account: account,
            fromDate: _fromDate,
            toDate: _toDate,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AccountingController>();

    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
          children: [
            _buildHeader(),
            const SizedBox(height: 12),
            _buildFilters(controller.accounts),
            const SizedBox(height: 12),
            if (_statementFuture == null)
              const _EmptyStatement()
            else
              FutureBuilder<AccountStatementResult>(
                future: _statementFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return KajFinanceState(
                      icon: Icons.sync_rounded,
                      title: context.l10n.isArabic
                          ? 'جارٍ إعداد كشف الحساب'
                          : 'Preparing account statement',
                      message: context.l10n.isArabic
                          ? 'يتم احتساب الرصيد والحركات ضمن الفترة المختارة.'
                          : 'Calculating balances and movements for the selected period.',
                    );
                  }
                  if (snapshot.hasError) {
                    return Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: AppText(
                          context.l10n.isArabic
                              ? 'تعذر تحميل كشف الحساب: ${snapshot.error}'
                              : 'Unable to load the account statement: ${snapshot.error}',
                        ),
                      ),
                    );
                  }
                  final result = snapshot.data;
                  if (result == null) return const _EmptyStatement();
                  return _buildStatement(result);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final ar = context.l10n.isArabic;
    final scheme = Theme.of(context).colorScheme;
    return KajShellSurface(
      emphasized: true,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.receipt_long_outlined,
              color: scheme.onPrimaryContainer,
              size: 21,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  ar ? 'كشف حساب تفصيلي' : 'Detailed account statement',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 3),
                AppText(
                  ar
                      ? 'عرض الحركات والمدين والدائن والرصيد المتحرك خلال فترة محددة.'
                      : 'Review movements, debit, credit and running balance for a selected period.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(List<AccountModel> accounts) {
    final ar = context.l10n.isArabic;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 760;
            final fields = <Widget>[
              DropdownButtonFormField<AccountModel>(
                initialValue: _selectedAccount,
                decoration: InputDecoration(
                  labelText: ar ? 'الحساب' : 'Account',
                  prefixIcon: const Icon(Icons.account_balance_outlined),
                  border: const OutlineInputBorder(),
                ),
                isExpanded: true,
                items: accounts
                    .where((account) => account.isActive)
                    .map(
                      (account) => DropdownMenuItem(
                        value: account,
                        child: AppText('${account.code} - ${account.name}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedAccount = value;
                    _statementFuture = null;
                  });
                },
              ),
              _dateField(
                label: ar ? 'من تاريخ' : 'From date',
                value: _fromDate,
                onTap: () => _pickDate(isFrom: true),
              ),
              _dateField(
                label: ar ? 'إلى تاريخ' : 'To date',
                value: _toDate,
                onTap: () => _pickDate(isFrom: false),
              ),
              FilledButton.icon(
                onPressed: _loadStatement,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                icon: const Icon(Icons.search),
                label: AppText(ar ? 'عرض الكشف' : 'View statement'),
              ),
            ];

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(flex: 2, child: fields[0]),
                  const SizedBox(width: 10),
                  Expanded(child: fields[1]),
                  const SizedBox(width: 10),
                  Expanded(child: fields[2]),
                  const SizedBox(width: 10),
                  SizedBox(width: 150, child: fields[3]),
                ],
              );
            }

            return Column(
              children: [
                for (var index = 0; index < fields.length; index++) ...[
                  fields[index],
                  if (index != fields.length - 1) const SizedBox(height: 10),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _dateField({
    required String label,
    required DateTime value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_month_outlined),
          border: const OutlineInputBorder(),
        ),
        child: AppText(_formatDate(value)),
      ),
    );
  }

  Widget _buildStatement(AccountStatementResult result) {
    final account = _selectedAccount!;
    final lines = result.lines;
    final totalDebit = lines.fold<double>(0, (sum, line) => sum + line.debit);
    final totalCredit = lines.fold<double>(0, (sum, line) => sum + line.credit);
    final closingBalance = result.closingBalance;
    final ar = context.l10n.isArabic;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _summaryCard(ar ? 'عدد الحركات' : 'Movements', lines.length.toString()),
            _summaryCard(
              ar ? 'رصيد أول المدة' : 'Opening balance',
              '${_formatAmount(result.openingBalance, account.currency)} ${account.currency}',
            ),
            _summaryCard(
              ar ? 'إجمالي المدين' : 'Total debit',
              _formatAmount(totalDebit, account.currency),
            ),
            _summaryCard(
              ar ? 'إجمالي الدائن' : 'Total credit',
              _formatAmount(totalCredit, account.currency),
            ),
            _summaryCard(
              ar ? 'الرصيد الختامي' : 'Closing balance',
              '${_formatAmount(closingBalance, account.currency)} ${account.currency}',
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (lines.isEmpty)
          _EmptyStatement(
            message: ar
                ? 'لا توجد حركات لهذا الحساب خلال الفترة المحددة.'
                : 'There are no movements for this account in the selected period.',
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  DataColumn(label: AppText(ar ? 'التاريخ' : 'Date')),
                  DataColumn(label: AppText(ar ? 'رقم القيد' : 'Entry no.')),
                  DataColumn(label: AppText(ar ? 'البيان' : 'Description')),
                  DataColumn(label: AppText(ar ? 'مدين' : 'Debit'), numeric: true),
                  DataColumn(label: AppText(ar ? 'دائن' : 'Credit'), numeric: true),
                  DataColumn(label: AppText(ar ? 'الرصيد' : 'Balance'), numeric: true),
                  DataColumn(label: AppText(ar ? 'العملة' : 'Currency')),
                ],
                rows: lines
                    .map(
                      (line) => DataRow(
                        cells: [
                          DataCell(AppText(_formatDate(line.entryDate))),
                          DataCell(AppText(line.entryNumber)),
                          DataCell(
                            SizedBox(
                              width: 260,
                              child: AppText(
                                line.description,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(AppText(_formatAmount(line.debit, line.currency))),
                          DataCell(AppText(_formatAmount(line.credit, line.currency))),
                          DataCell(AppText(_formatAmount(line.runningBalance, line.currency))),
                          DataCell(AppText(line.currency)),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
      ],
    );
  }

  Widget _summaryCard(String title, String value) {
    return SizedBox(
      width: 184,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 3),
              AppText(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }

  String _formatAmount(double value, String currency) =>
      MoneyFormatter.format(value, currency: currency);
}

class _EmptyStatement extends StatelessWidget {
  const _EmptyStatement({
    this.message = 'اختر الحساب والفترة ثم اضغط على عرض الكشف.',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    final effectiveMessage = context.l10n.isArabic
        ? message
        : message == 'اختر الحساب والفترة ثم اضغط على عرض الكشف.'
        ? 'Select an account and period, then choose View statement.'
        : message;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 52,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            AppText(
              effectiveMessage,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
