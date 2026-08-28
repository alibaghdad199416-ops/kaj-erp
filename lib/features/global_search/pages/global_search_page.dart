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
    final subscription = _changeSubscription;
    _changeSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
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
        _error = null;
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
      final results = cached != null &&
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
    // Do not mutate State during build. If a previously selected category
    // disappeared from the latest result set, use the canonical all-results
    // view for this frame and let the next user interaction choose again.
    final selectedType = types.contains(_selectedType) ? _selectedType : '__all__';
    final visible = selectedType == '__all__'
        ? _results
        : _results.where((result) => result.type == selectedType).toList();

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
                      selected: selectedType == type,
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
