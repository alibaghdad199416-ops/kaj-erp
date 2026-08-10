import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'package:quality_line_erp/core/events/app_data_change_bus.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/core/widgets/app_top_navigation.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';
import 'package:quality_line_erp/design_system/kaj_signature_components.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_entry_components.dart';
import 'package:quality_line_erp/features/global_search/models/global_search_result.dart';
import 'package:quality_line_erp/features/global_search/repositories/global_search_repository.dart';

import 'package:quality_line_erp/core/errors/user_facing_error.dart';

class GlobalSearchPage extends StatefulWidget {
  const GlobalSearchPage({super.key});

  @override
  State<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends State<GlobalSearchPage> {
  final GlobalSearchRepository _repository = GlobalSearchRepository();
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  StreamSubscription<AppDataChangeEvent>? _changeSubscription;
  List<GlobalSearchResult> _results = const [];
  final Map<String, ({DateTime loadedAt, List<GlobalSearchResult> rows})>
  _queryCache = {};
  String _selectedType = '__all__';
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
    _changeSubscription = AppDataChangeBus.instance.events.listen((_) {
      _queryCache.clear();
      final query = _controller.text.trim();
      if (query.length >= 3) unawaited(_search(query));
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_changeSubscription != null) {
      unawaited(_changeSubscription!.cancel());
      _changeSubscription = null;
    }
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 480), () => _search(value));
    setState(() {
      if (value.trim().length < 3) {
        _results = const [];
        _loading = false;
        _error = null;
      } else {
        _loading = true;
      }
    });
  }

  Future<void> _search(String query) async {
    final normalized = query.trim();
    if (normalized.length < 3) return;
    try {
      final access = context.read<AccessController>();
      final key = normalized.toLowerCase();
      final cached = _queryCache[key];
      final results =
          cached != null &&
              DateTime.now().difference(cached.loadedAt) <
                  const Duration(seconds: 45)
          ? cached.rows
          : await _repository.search(normalized);
      if (cached == null || !identical(results, cached.rows)) {
        _queryCache[key] = (loadedAt: DateTime.now(), rows: results);
      }
      if (!mounted || _controller.text.trim() != normalized) return;
      setState(() {
        _results = results
            .where((result) => access.hasPermission(result.permission))
            .toList();
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      AppLogger.debug('Global search failed: $error');
      setState(
        () => _error = userFacingError(
          error,
          isArabic: context.l10n.isArabic,
          arabicFallback: 'تعذر تنفيذ البحث الشامل.',
          englishFallback: 'Unable to complete the global search.',
        ),
      );
    } finally {
      if (mounted && _controller.text.trim() == normalized) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final types = <String>{
      '__all__',
      ..._results.map((result) => result.type),
    }.toList();
    if (!types.contains(_selectedType)) _selectedType = '__all__';
    final visible = _selectedType == '__all__'
        ? _results
        : _results.where((result) => result.type == _selectedType).toList();

    final ar = context.l10n.isArabic;
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          KajSignaturePageHero(
            eyebrow: ar ? 'مركز الوصول السريع' : 'UNIFIED DISCOVERY',
            title: context.l10n.text('globalSearch'),
            subtitle: ar
                ? 'ابحث بأمان في المركبات والمنتجات والشركاء والأوامر والمستندات المالية من مكان واحد.'
                : 'Securely discover vehicles, products, partners, orders and financial documents from one place.',
            icon: Icons.manage_search_rounded,
            metrics: <KajSignatureMetricData>[
              KajSignatureMetricData(
                label: ar ? 'النتائج' : 'RESULTS',
                value: '${_results.length}',
                icon: Icons.view_list_rounded,
              ),
              KajSignatureMetricData(
                label: ar ? 'الأنواع' : 'CATEGORIES',
                value: '${types.length - 1}',
                icon: Icons.category_outlined,
                accent: KajDesignTokens.champagne,
              ),
            ],
          ),
          const SizedBox(height: 18),
          KajSignatureSearchSurface(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: context.l10n.text('globalSearch'),
                hintText: context.l10n.text('globalSearchHint'),
                prefixIcon: const Icon(Icons.manage_search_rounded),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: context.l10n.text('clearSearch'),
                        onPressed: () {
                          _controller.clear();
                          _onChanged('');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_results.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: types
                  .map(
                    (type) => ChoiceChip(
                      selected: _selectedType == type,
                      onSelected: (_) => setState(() => _selectedType = type),
                      label: AppText(
                        type == '__all__'
                            ? (ar
                                  ? 'الكل (${_results.length})'
                                  : 'All (${_results.length})')
                            : '$type (${_results.where((result) => result.type == type).length})',
                      ),
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: 16),
          if (_loading)
            const KajActivitySkeleton(rows: 5)
          else if (_error != null)
            _SearchState(
              icon: Icons.error_outline_rounded,
              title: ar ? 'تعذر البحث' : 'Search unavailable',
              message: _error!,
            )
          else if (_controller.text.trim().length < 3)
            _SearchState(
              icon: Icons.search_rounded,
              title: ar
                  ? 'ابحث في جميع بيانات النظام'
                  : 'Search across the entire workspace',
              message: ar
                  ? 'اكتب ثلاثة أحرف على الأقل للبحث في السيارات والمنتجات والمخازن والشركاء والصيانة والمبيعات والمشتريات والقيود.'
                  : 'Enter at least three characters to search vehicles, products, warehouses, partners, maintenance, sales, purchases and journal entries.',
            )
          else if (visible.isEmpty)
            _SearchState(
              icon: Icons.search_off_rounded,
              title: ar ? 'لا توجد نتائج' : 'No matching results',
              message: ar
                  ? 'جرّب رقم مستند أو اسم طرف أو رقم شاصي أو كود منتج مختلف.'
                  : 'Try another document number, partner name, VIN or product code.',
            )
          else
            ...visible.map(
              (result) => _SearchResultCard(
                result: result,
                query: _controller.text.trim(),
              ),
            ),
        ],
      ),
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({required this.result, required this.query});

  final GlobalSearchResult result;
  final String query;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => AppModuleNavigation.open(context, result.route),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              CircleAvatar(child: Icon(result.icon)),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _HighlightedText(
                          text: result.title,
                          query: query,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15.5,
                          ),
                        ),
                        Chip(
                          visualDensity: VisualDensity.compact,
                          side: BorderSide.none,
                          label: AppText(
                            result.type,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                        if (result.status?.isNotEmpty ?? false)
                          Chip(
                            visualDensity: VisualDensity.compact,
                            side: BorderSide.none,
                            label: AppText(
                              result.status!,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _HighlightedText(text: result.subtitle, query: query),
                    if (result.amount != null ||
                        (result.date?.isNotEmpty ?? false)) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 14,
                        children: [
                          if (result.amount != null && result.currency != null)
                            AppText(
                              MoneyFormatter.withCurrency(
                                result.amount!,
                                result.currency!,
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          if (result.date?.isNotEmpty ?? false)
                            AppText(
                              result.date!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.open_in_new_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({required this.text, required this.query, this.style});

  final String text;
  final String query;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final displayText = AppTranslation.translate(text);
    final rawQuery = query.trim();
    final localizedQuery = AppTranslation.translate(rawQuery).trim();
    final match = _findMatch(displayText, [rawQuery, localizedQuery]);
    if (match == null) return AppText(displayText, style: style);

    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final highlightStyle = baseStyle.copyWith(
      backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
      fontWeight: FontWeight.w900,
    );
    return RichText(
      text: TextSpan(
        style: baseStyle,
        children: [
          if (match.$1 > 0) TextSpan(text: displayText.substring(0, match.$1)),
          TextSpan(
            text: displayText.substring(match.$1, match.$2),
            style: highlightStyle,
          ),
          if (match.$2 < displayText.length)
            TextSpan(text: displayText.substring(match.$2)),
        ],
      ),
    );
  }

  static (int, int)? _findMatch(String value, List<String> candidates) {
    final lower = value.toLowerCase();
    for (final candidate in candidates) {
      final token = candidate.trim();
      if (token.isEmpty) continue;
      final start = lower.indexOf(token.toLowerCase());
      if (start >= 0) return (start, start + token.length);
    }
    return null;
  }
}

class _SearchState extends StatelessWidget {
  const _SearchState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 56),
        child: Column(
          children: [
            Icon(icon, size: 52, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 14),
            AppText(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 7),
            AppText(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
