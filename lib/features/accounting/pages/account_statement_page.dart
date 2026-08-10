import 'package:flutter/material.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';
import 'package:provider/provider.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';

import 'package:quality_line_erp/features/accounting/controllers/accounting_controller.dart';
import 'package:quality_line_erp/features/accounting/models/account_model.dart';
import 'package:quality_line_erp/features/accounting/models/account_statement_result.dart';
import 'package:quality_line_erp/design_system/kaj_finance_stage7_components.dart';

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
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      if (isFrom) {
        _fromDate = picked;
        if (_toDate.isBefore(_fromDate)) {
          _toDate = picked;
        }
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
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildFilters(controller.accounts),
            const SizedBox(height: 16),
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
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: AppText(
                          'تعذر تحميل كشف الحساب: ${snapshot.error}',
                        ),
                      ),
                    );
                  }
                  final result = snapshot.data;
                  if (result == null) {
                    return const _EmptyStatement();
                  }
                  return _buildStatement(result);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.white,
            child: Icon(Icons.receipt_long_outlined, color: Colors.black),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  'كشف حساب تفصيلي',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                AppText(
                  'عرض الحركات والمدين والدائن والرصيد المتحرك خلال فترة محددة.',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(List<AccountModel> accounts) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 760;
            final fields = <Widget>[
              DropdownButtonFormField<AccountModel>(
                initialValue: _selectedAccount,
                decoration: InputDecoration(
                  labelText: AppTranslation.translate('الحساب'),
                  prefixIcon: Icon(Icons.account_balance_outlined),
                  border: OutlineInputBorder(),
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
                label: 'من تاريخ',
                value: _fromDate,
                onTap: () => _pickDate(isFrom: true),
              ),
              _dateField(
                label: 'إلى تاريخ',
                value: _toDate,
                onTap: () => _pickDate(isFrom: false),
              ),
              FilledButton.icon(
                onPressed: _loadStatement,
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  minimumSize: const Size.fromHeight(56),
                ),
                icon: const Icon(Icons.search),
                label: const AppText('عرض الكشف'),
              ),
            ];

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(flex: 2, child: fields[0]),
                  const SizedBox(width: 12),
                  Expanded(child: fields[1]),
                  const SizedBox(width: 12),
                  Expanded(child: fields[2]),
                  const SizedBox(width: 12),
                  SizedBox(width: 150, child: fields[3]),
                ],
              );
            }

            return Column(
              children: [
                for (var index = 0; index < fields.length; index++) ...[
                  fields[index],
                  if (index != fields.length - 1) const SizedBox(height: 12),
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
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: AppTranslation.translate(label),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _summaryCard('عدد الحركات', lines.length.toString()),
            _summaryCard(
              'رصيد أول المدة',
              '${_formatAmount(result.openingBalance, account.currency)} ${account.currency}',
            ),
            _summaryCard(
              'إجمالي المدين',
              _formatAmount(totalDebit, account.currency),
            ),
            _summaryCard(
              'إجمالي الدائن',
              _formatAmount(totalCredit, account.currency),
            ),
            _summaryCard(
              'الرصيد الختامي',
              '${_formatAmount(closingBalance, account.currency)} ${account.currency}',
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (lines.isEmpty)
          const _EmptyStatement(
            message: 'لا توجد حركات لهذا الحساب خلال الفترة المحددة.',
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: AppText('التاريخ')),
                  DataColumn(label: AppText('رقم القيد')),
                  DataColumn(label: AppText('البيان')),
                  DataColumn(label: AppText('مدين'), numeric: true),
                  DataColumn(label: AppText('دائن'), numeric: true),
                  DataColumn(label: AppText('الرصيد'), numeric: true),
                  DataColumn(label: AppText('العملة')),
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
                          DataCell(
                            AppText(_formatAmount(line.debit, line.currency)),
                          ),
                          DataCell(
                            AppText(_formatAmount(line.credit, line.currency)),
                          ),
                          DataCell(
                            AppText(
                              _formatAmount(line.runningBalance, line.currency),
                            ),
                          ),
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

  String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }

  String _formatAmount(double value, String currency) {
    return MoneyFormatter.format(value, currency: currency);
  }
}

class _EmptyStatement extends StatelessWidget {
  const _EmptyStatement({
    this.message = 'اختر الحساب والفترة ثم اضغط على عرض الكشف.',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(50),
        child: Column(
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 64,
              color: Colors.grey.shade500,
            ),
            const SizedBox(height: 14),
            AppText(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }
}
