import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';

/// Compact archive notice + search control used by the legacy commercial tabs.
///
/// This keeps the historical invoice archive explicit without reserving a
/// large nested panel inside the active sales/purchase workspace.
class LegacyCommercialArchiveToolbar extends StatelessWidget {
  const LegacyCommercialArchiveToolbar({
    super.key,
    required this.title,
    required this.message,
    required this.searchHint,
    required this.searchController,
    required this.onSearchChanged,
  });

  final String title;
  final String message;
  final String searchHint;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final notice = Container(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 11, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .34),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .62)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .09),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              Icons.history_outlined,
              size: 18,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AppText(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                AppText(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    height: 1.25,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final search = TextField(
      controller: searchController,
      onChanged: onSearchChanged,
      decoration: InputDecoration(
        isDense: true,
        hintText: searchHint,
        prefixIcon: const Icon(Icons.search_rounded, size: 19),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(11)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 11,
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[notice, const SizedBox(height: 7), search],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(flex: 6, child: notice),
            const SizedBox(width: 9),
            Expanded(flex: 5, child: search),
          ],
        );
      },
    );
  }
}
