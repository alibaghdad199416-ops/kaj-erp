import 'dart:async';

import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/filtering/unified_query.dart';

/// Shared search/filter/sort surface for ERP list screens.
///
/// The toolbar owns presentation only. Query state remains in the supplied
/// [UnifiedQueryController], so modules do not maintain parallel search state.
class UnifiedQueryToolbar extends StatefulWidget {
  const UnifiedQueryToolbar({
    super.key,
    required this.controller,
    this.searchHint = 'بحث...',
    this.filters = const <UnifiedQueryFilterOption>[],
    this.sorts = const <UnifiedQuerySortOption>[],
    this.padding = EdgeInsets.zero,
  });

  final UnifiedQueryController controller;
  final String searchHint;
  final List<UnifiedQueryFilterOption> filters;
  final List<UnifiedQuerySortOption> sorts;
  final EdgeInsetsGeometry padding;

  @override
  State<UnifiedQueryToolbar> createState() => _UnifiedQueryToolbarState();
}

class _UnifiedQueryToolbarState extends State<UnifiedQueryToolbar> {
  late final TextEditingController _searchController;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.controller.state.search);
    widget.controller.addListener(_syncSearch);
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

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) widget.controller.setSearch(value);
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
    if (option != null) widget.controller.addFilter(option.token);
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
                  subtitle: Text(option.descending ? 'تنازلي' : 'تصاعدي'),
                  onTap: () => Navigator.pop(context, option),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (option != null) widget.controller.addSort(option.rule);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        final chips = <Widget>[
          ...state.filters.map(
            (token) => InputChip(
              label: Text('${token.label}: ${token.valueLabel}'),
              onDeleted: () => widget.controller.removeFilter(token),
            ),
          ),
          ...state.sorts.asMap().entries.map(
            (entry) => InputChip(
              avatar: const Icon(Icons.sort, size: 16),
              label: Text(
                '${entry.value.label} ${entry.value.descending ? '↓' : '↑'}',
              ),
              onDeleted: () => widget.controller.removeSort(entry.value.field),
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
                  final compact = constraints.maxWidth < 700;
                  final search = TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    textDirection: Directionality.of(context),
                    decoration: InputDecoration(
                      hintText: widget.searchHint,
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: state.search.trim().isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'مسح البحث',
                              onPressed: () {
                                _debounce?.cancel();
                                _searchController.clear();
                                widget.controller.setSearch('');
                              },
                              icon: const Icon(Icons.clear),
                            ),
                    ),
                  );
                  final actions = Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (widget.filters.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: _addFilter,
                          icon: const Icon(Icons.filter_alt_outlined),
                          label: const Text('فلترة'),
                        ),
                      if (widget.sorts.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: _addSort,
                          icon: const Icon(Icons.sort),
                          label: const Text('فرز'),
                        ),
                      if (!state.isEmpty)
                        TextButton.icon(
                          onPressed: widget.controller.clear,
                          icon: const Icon(Icons.filter_alt_off_outlined),
                          label: const Text('مسح الكل'),
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
