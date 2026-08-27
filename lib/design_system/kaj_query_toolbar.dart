import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/filtering/unified_query.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';

/// Shared search/filter/sort surface for ERP list pages.
///
/// Modules provide their own filter controls through [filterBuilder], while
/// the lifecycle and presentation of active conditions remains consistent.
class KajQueryToolbar extends StatefulWidget {
  const KajQueryToolbar({
    super.key,
    required this.controller,
    this.hintText = 'بحث في السجلات...',
    this.filterBuilder,
    this.sortBuilder,
    this.compact = false,
  });

  final UnifiedQueryController controller;
  final String hintText;
  final WidgetBuilder? filterBuilder;
  final WidgetBuilder? sortBuilder;
  final bool compact;

  @override
  State<KajQueryToolbar> createState() => _KajQueryToolbarState();
}

class _KajQueryToolbarState extends State<KajQueryToolbar> {
  late final TextEditingController _searchController =
      TextEditingController(text: widget.controller.state.search);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncSearch);
  }

  @override
  void didUpdateWidget(covariant KajQueryToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_syncSearch);
    widget.controller.addListener(_syncSearch);
    _setSearchText(widget.controller.state.search);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncSearch);
    _searchController.dispose();
    super.dispose();
  }

  void _setSearchText(String value) {
    if (_searchController.text == value) return;
    _searchController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _syncSearch() {
    if (!mounted) return;
    _setSearchText(widget.controller.state.search);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final brightness = Theme.of(context).brightness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: KajDesignTokens.space8,
          runSpacing: KajDesignTokens.space8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: widget.compact ? 220 : 320,
              child: TextField(
                key: const ValueKey('kaj-unified-search'),
                controller: _searchController,
                onChanged: widget.controller.setSearch,
                textDirection: Directionality.of(context),
                textAlign: TextAlign.start,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: state.search.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'مسح البحث',
                          onPressed: () => widget.controller.setSearch(''),
                          icon: const Icon(Icons.close_rounded),
                        ),
                  isDense: true,
                  filled: true,
                  fillColor: KajDesignTokens.raisedSurface(brightness),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      KajDesignTokens.radiusMd,
                    ),
                    borderSide: BorderSide(
                      color: KajDesignTokens.border(brightness),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.filterBuilder != null) widget.filterBuilder!(context),
            if (widget.sortBuilder != null) widget.sortBuilder!(context),
          ],
        ),
        if (state.filters.isNotEmpty || state.sorts.isNotEmpty) ...[
          const SizedBox(height: KajDesignTokens.space8),
          Wrap(
            spacing: KajDesignTokens.space6,
            runSpacing: KajDesignTokens.space6,
            children: [
              ...state.filters.map(
                (filter) => InputChip(
                  key: ValueKey('kaj-filter-${filter.key}-${filter.value}'),
                  label: Text('${filter.label}: ${filter.valueLabel}'),
                  onDeleted: () => widget.controller.removeFilter(filter),
                ),
              ),
              ...state.sorts.map(
                (sort) => InputChip(
                  key: ValueKey('kaj-sort-${sort.field}'),
                  avatar: Icon(
                    sort.descending
                        ? Icons.south_rounded
                        : Icons.north_rounded,
                    size: 15,
                  ),
                  label: Text(sort.label),
                  onDeleted: () => widget.controller.removeSort(sort.field),
                ),
              ),
              TextButton.icon(
                onPressed: widget.controller.clear,
                icon: const Icon(Icons.clear_all_rounded, size: 17),
                label: const Text('مسح الكل'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
