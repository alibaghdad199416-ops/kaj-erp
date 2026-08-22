import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';
import 'package:quality_line_erp/core/widgets/compact_metric_pill.dart';
import 'package:quality_line_erp/design_system/kaj_finance_stage7_components.dart';
import 'package:quality_line_erp/design_system/kaj_shell_components.dart';
import 'package:quality_line_erp/features/accounting/controllers/accounting_controller.dart';
import 'package:quality_line_erp/features/accounting/models/account_model.dart';
import 'package:quality_line_erp/features/accounting/models/account_statement_result.dart';

class AccountStatementPage extends StatefulWidget {
  const AccountStatementPage({
    super.key,
    this.embedded = false,
    this.continuous = false,
  });

  final bool embedded;
  final bool continuous;

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

    Widget statementResult() {
      if (_statementFuture == null) return const _EmptyStatement();
      return FutureBuilder<AccountStatementResult>(
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
          if (snapshot.hasError) return _statementError(snapshot.error!);
          final result = snapshot.data;
          if (result == null) return const _EmptyStatement();
          return _buildStatement(result);
        },
      );
    }

    Widget content;
    if (widget.embedded && !widget.continuous) {
      content = Column(
        key: const ValueKey('account-statement-full-height-column'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFilters(controller.accounts),
          const SizedBox(height: 8),
          Expanded(child: _embeddedStatementViewport()),
        ],
      );
    } else {
      content = ListView(
        shrinkWrap: widget.continuous,
        physics: widget.continuous
            ? const NeverScrollableScrollPhysics()
            : null,
        padding: widget.embedded
            ? const EdgeInsets.fromLTRB(0, 0, 0, 16)
            : const EdgeInsets.fromLTRB(16, 4, 16, 18),
        children: [
          if (!widget.embedded) ...[_buildHeader(), const SizedBox(height: 12)],
          _buildFilters(controller.accounts),
          const SizedBox(height: 10),
          statementResult(),
        ],
      );
    }

    return Directionality(
      textDirection: Directionality.of(context),
      child: widget.embedded ? content : Scaffold(body: content),
    );
  }

  Widget _embeddedStatementViewport() {
    final scheme = Theme.of(context).colorScheme;
    final future = _statementFuture;

    Widget child;
    if (future == null) {
      child = const Center(child: _EmptyStatement(compact: true));
    } else {
      child = FutureBuilder<AccountStatementResult>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: KajFinanceState(
                icon: Icons.sync_rounded,
                title: context.l10n.isArabic
                    ? 'جارٍ إعداد كشف الحساب'
                    : 'Preparing account statement',
                message: context.l10n.isArabic
                    ? 'يتم احتساب الرصيد والحركات ضمن الفترة المختارة.'
                    : 'Calculating balances and movements for the selected period.',
              ),
            );
          }
          if (snapshot.hasError) return _statementError(snapshot.error!);
          final result = snapshot.data;
          if (result == null) {
            return const Center(child: _EmptyStatement(compact: true));
          }
          return _buildStatementWorkspace(result);
        },
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .72)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(13), child: child),
    );
  }

  Widget _statementError(Object error) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: AppText(
            context.l10n.isArabic
                ? 'تعذر تحميل كشف الحساب: $error'
                : 'Unable to load the account statement: $error',
            textAlign: TextAlign.center,
          ),
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
    final filters = LayoutBuilder(
      key: const ValueKey('account-statement-horizontal-filterbar'),
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 880;
        final fields = <Widget>[
          DropdownButtonFormField<AccountModel>(
            initialValue: _selectedAccount,
            decoration: InputDecoration(
              isDense: true,
              labelText: ar ? 'الحساب' : 'Account',
              prefixIcon: const Icon(Icons.account_balance_outlined, size: 19),
              border: const OutlineInputBorder(),
            ),
            isExpanded: true,
            items: accounts
                .where((account) => account.isActive)
                .map(
                  (account) => DropdownMenuItem(
                    value: account,
                    child: AppText(
                      '${account.code} - ${account.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
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
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(150, 44),
            ),
            icon: const Icon(Icons.search_rounded, size: 18),
            label: AppText(ar ? 'عرض الكشف' : 'View statement'),
          ),
        ];

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(flex: 2, child: fields[0]),
              const SizedBox(width: 8),
              Expanded(child: fields[1]),
              const SizedBox(width: 8),
              Expanded(child: fields[2]),
              const SizedBox(width: 8),
              SizedBox(width: 150, child: fields[3]),
            ],
          );
        }

        return Column(
          children: [
            for (var index = 0; index < fields.length; index++) ...[
              fields[index],
              if (index != fields.length - 1) const SizedBox(height: 8),
            ],
          ],
        );
      },
    );

    if (widget.embedded) return filters;
    return Card(
      child: Padding(padding: const EdgeInsets.all(14), child: filters),
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
          isDense: true,
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_month_outlined, size: 19),
          border: const OutlineInputBorder(),
        ),
        child: AppText(_formatDate(value)),
      ),
    );
  }

  Widget _buildStatementWorkspace(AccountStatementResult result) {
    final lines = result.lines;
    final ar = context.l10n.isArabic;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Column(
        key: const ValueKey('account-statement-result-full-height-column'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSummaryGrid(result),
          const SizedBox(height: 8),
          Expanded(
            child: lines.isEmpty
                ? Center(
                    child: _EmptyStatement(
                      compact: true,
                      message: ar
                          ? 'لا توجد حركات لهذا الحساب خلال الفترة المحددة.'
                          : 'There are no movements for this account in the selected period.',
                    ),
                  )
                : _statementTableViewport(result),
          ),
        ],
      ),
    );
  }

  Widget _buildStatement(AccountStatementResult result) {
    final lines = result.lines;
    final ar = context.l10n.isArabic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSummaryGrid(result),
        const SizedBox(height: 10),
        if (lines.isEmpty)
          _EmptyStatement(
            message: ar
                ? 'لا توجد حركات لهذا الحساب خلال الفترة المحددة.'
                : 'There are no movements for this account in the selected period.',
          )
        else
          _statementTable(result),
      ],
    );
  }

  Widget _buildSummaryGrid(AccountStatementResult result) {
    final account = _selectedAccount!;
    final lines = result.lines;
    final totalDebit = lines.fold<double>(0, (sum, line) => sum + line.debit);
    final totalCredit = lines.fold<double>(0, (sum, line) => sum + line.credit);
    final ar = context.l10n.isArabic;
    final metrics = <(IconData, String, String)>[
      (
        Icons.format_list_numbered_rounded,
        ar ? 'عدد الحركات' : 'Movements',
        lines.length.toString(),
      ),
      (
        Icons.first_page_rounded,
        ar ? 'رصيد أول المدة' : 'Opening balance',
        '${_formatAmount(result.openingBalance, account.currency)} ${account.currency}',
      ),
      (
        Icons.south_west_rounded,
        ar ? 'إجمالي المدين' : 'Total debit',
        _formatAmount(totalDebit, account.currency),
      ),
      (
        Icons.north_east_rounded,
        ar ? 'إجمالي الدائن' : 'Total credit',
        _formatAmount(totalCredit, account.currency),
      ),
      (
        Icons.account_balance_wallet_outlined,
        ar ? 'الرصيد الختامي' : 'Closing balance',
        '${_formatAmount(result.closingBalance, account.currency)} ${account.currency}',
      ),
    ];

    return LayoutBuilder(
      key: const ValueKey('account-statement-responsive-summary-grid'),
      builder: (context, constraints) {
        const gap = 8.0;
        const minWidth = 175.0;
        final columns = ((constraints.maxWidth + gap) / (minWidth + gap))
            .floor()
            .clamp(1, 5);
        final width = (constraints.maxWidth - ((columns - 1) * gap)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: metrics
              .map(
                (metric) => SizedBox(
                  width: width,
                  child: CompactMetricPill(
                    icon: metric.$1,
                    label: metric.$2,
                    value: metric.$3,
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }

  Widget _statementTableViewport(AccountStatementResult result) {
    return Scrollbar(
      child: SingleChildScrollView(
        key: const ValueKey('account-statement-full-height-scroll'),
        child: _statementTable(result),
      ),
    );
  }

  Widget _statementTable(AccountStatementResult result) {
    final lines = result.lines;
    final ar = context.l10n.isArabic;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 40,
        dataRowMinHeight: 40,
        dataRowMaxHeight: 44,
        columnSpacing: 24,
        horizontalMargin: 12,
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
                      width: 300,
                      child: AppText(
                        line.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  DataCell(AppText(_formatAmount(line.debit, line.currency))),
                  DataCell(AppText(_formatAmount(line.credit, line.currency))),
                  DataCell(
                    AppText(_formatAmount(line.runningBalance, line.currency)),
                  ),
                  DataCell(AppText(line.currency)),
                ],
              ),
            )
            .toList(growable: false),
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
    this.compact = false,
  });

  final String message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final effectiveMessage = context.l10n.isArabic
        ? message
        : message == 'اختر الحساب والفترة ثم اضغط على عرض الكشف.'
        ? 'Select an account and period, then choose View statement.'
        : message;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: compact ? 12 : 22,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: compact ? 32 : 46,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          SizedBox(height: compact ? 7 : 10),
          AppText(
            effectiveMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
