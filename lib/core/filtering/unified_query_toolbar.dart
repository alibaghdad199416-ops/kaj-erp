import 'dart:async';

import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/filtering/unified_query.dart';

/// Shared search/filter/sort surface for ERP list screens.
///
/// The toolbar owns presentation only. Query state remains in the supplied
/// [UnifiedQueryController], so modules do not maintain parallel search state.
/// Optional labels keep the component reusable for Arabic/English screens
/// without creating separate search/filter implementations.
class UnifiedQueryToolbar extends StatefulWidget {
  const UnifiedQueryToolbar({
    super.key,
    required this.controller,
    this.searchHint = 'بحث...',
    this.filters = const <UnifiedQueryFilterOption>[],
    this.sorts = const <UnifiedQuerySortOption>[],
    this.filterBuilder,
    this.sortBuilder,
    this.compact = false,
    this.padding = EdgeInsets.zero,
    this.filterButtonLabel = 'فلترة',
    this.sortButtonLabel = 'فرز',
    this.clearAllLabel = 'مسح الكل',
    this.clearSearchTooltip = 'مسح البحث',
    this.ascendingLabel = 'تصاعدي',
    this.descendingLabel = 'تنازلي',
  });

  final UnifiedQueryController controller;
  final String searchHint;
  final List<UnifiedQueryFilterOption> filters;
  final List<UnifiedQuerySortOption> sorts;
  final WidgetBuilder? filterBuilder;
  final WidgetBuilder? sortBuilder;
  final bool compact;
  final EdgeInsetsGeometry padding;
  final String filterButtonLabel;
  final String sortButtonLabel;
  final String clearAllLabel;
  final String clearSearchTooltip;
  final String ascendingLabel;
  final String descendingLabel;

  @override
  State<UnifiedQueryToolbar> createState() => _UnifiedQueryToolbarState();
}

class _UnifiedQueryToolbarState extends State<UnifiedQueryToolbar> {
  late final TextEditingController _searchController;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: widget.controller.state.search,
    );
    widget.controller.addListener(_syncSearch);
  }

  @override
  void didUpdateWidget(covariant UnifiedQueryToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_syncSearch);
    widget.controller.addListener(_syncSearch);
    _debounce?.cancel();
    _syncSearch();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncSearch);
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _syncSearch() {
    final value = widget.controller.state.search;
    if (_searchController.text == value) return;
    _searchController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _commitSearch(String value) {
    _debounce?.cancel();
    final normalized = value.trim();
    if (_searchController.text != normalized) {
      _searchController.value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
    }
    widget.controller.setSearch(normalized);
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      widget.controller.setSearch('');
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) _commitSearch(value);
    });
  }

  Future<void> _addFilter() async {
    if (widget.filters.isEmpty || !mounted) return;
    final option = await showModalBottomSheet<UnifiedQueryFilterOption>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: widget.filters
              .map(
                (option) => ListTile(
                  leading: Icon(option.icon ?? Icons.filter_alt_outlined),
                  title: Text(option.label),
                  subtitle: Text(option.valueLabel),
                  onTap: () => Navigator.pop(context, option),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (!mounted || option == null) return;
    widget.controller.addFilter(option.token);
  }

  Future<void> _addSort() async {
    if (widget.sorts.isEmpty || !mounted) return;
    final option = await showModalBottomSheet<UnifiedQuerySortOption>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: widget.sorts
              .map(
                (option) => ListTile(
                  leading: Icon(option.icon ?? Icons.sort),
                  title: Text(option.label),
                  subtitle: Text(
                    option.descending
                        ? widget.descendingLabel
                        : widget.ascendingLabel,
                  ),
                  onTap: () => Navigator.pop(context, option),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (!mounted || option == null) return;
    widget.controller.addSort(option.rule);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        final hasSearchText = _searchController.text.trim().isNotEmpty;
        final chips = <Widget>[
          ...state.filters.map(
            (token) => InputChip(
              label: Text('${token.label}: ${token.valueLabel}'),
              onDeleted: () => widget.controller.removeFilter(token),
            ),
          ),
          ...state.sorts.map(
            (rule) => InputChip(
              avatar: Icon(
                rule.descending ? Icons.south_rounded : Icons.north_rounded,
                size: 16,
              ),
              label: Text('${rule.label} ${rule.descending ? '↓' : '↑'}'),
              onDeleted: () => widget.controller.removeSort(rule.field),
            ),
          ),
        ];

        return Padding(
          padding: widget.padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = widget.compact || constraints.maxWidth < 700;
                  final search = TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    onSubmitted: _commitSearch,
                    textDirection: Directionality.of(context),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: widget.searchHint,
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: hasSearchText
                          ? IconButton(
                              tooltip: widget.clearSearchTooltip,
                              onPressed: () {
                                _debounce?.cancel();
                                _searchController.clear();
                                widget.controller.setSearch('');
                              },
                              icon: const Icon(Icons.clear_rounded),
                            )
                          : null,
                      isDense: true,
                    ),
                  );

                  final filterControl = widget.filterBuilder?.call(context);
                  final sortControl = widget.sortBuilder?.call(context);
                  final actions = Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (filterControl != null)
                        filterControl
                      else if (widget.filters.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: _addFilter,
                          icon: const Icon(Icons.filter_alt_outlined),
                          label: Text(widget.filterButtonLabel),
                        ),
                      if (sortControl != null)
                        sortControl
                      else if (widget.sorts.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: _addSort,
                          icon: const Icon(Icons.sort),
                          label: Text(widget.sortButtonLabel),
                        ),
                      if (!state.isEmpty)
                        TextButton.icon(
                          onPressed: widget.controller.clear,
                          icon: const Icon(Icons.clear_all_rounded),
                          label: Text(widget.clearAllLabel),
                        ),
                    ],
                  );

                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [search, const SizedBox(height: 8), actions],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: search),
                      const SizedBox(width: 8),
                      actions,
                    ],
                  );
                },
              ),
              if (chips.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: chips),
              ],
            ],
          ),
        );
      },
    );
  }
}

class UnifiedQueryFilterOption {
  const UnifiedQueryFilterOption({
    required this.token,
    this.icon,
  });

  final UnifiedFilterToken token;
  final IconData? icon;

  String get label => token.label;
  String get valueLabel => token.valueLabel;
}

class UnifiedQuerySortOption {
  const UnifiedQuerySortOption({
    required this.rule,
    this.icon,
  });

  final UnifiedSortRule rule;
  final IconData? icon;

  String get label => rule.label;
  bool get descending => rule.descending;
}
