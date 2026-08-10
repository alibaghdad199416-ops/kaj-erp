import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_shell_components.dart';

/// Stage 04 inventory primitives. Every inventory workflow uses the same
/// hierarchy, spacing, responsive behavior and state language.
class KajInventoryPageHeader extends StatelessWidget {
  const KajInventoryPageHeader({
    super.key,
    required this.titleAr,
    required this.titleEn,
    required this.subtitleAr,
    required this.subtitleEn,
    required this.icon,
    this.actions = const <Widget>[],
  });

  final String titleAr;
  final String titleEn;
  final String subtitleAr;
  final String subtitleEn;
  final IconData icon;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final ar = context.l10n.isArabic;
    final brightness = Theme.of(context).brightness;
    return KajShellSurface(
      emphasized: true,
      padding: const EdgeInsets.all(22),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final heading = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: KajDesignTokens.primaryGradient(brightness),
                  borderRadius: BorderRadius.circular(KajDesignTokens.radiusMd),
                  boxShadow: KajDesignTokens.softShadow(brightness),
                ),
                child: Icon(icon, color: Colors.white, size: 25),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    AppText(
                      ar ? titleAr : titleEn,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 5),
                    AppText(
                      ar ? subtitleAr : subtitleEn,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                heading,
                if (actions.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 18),
                  Wrap(spacing: 10, runSpacing: 10, children: actions),
                ],
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: heading),
              if (actions.isNotEmpty) ...<Widget>[
                const SizedBox(width: 18),
                Flexible(
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 10,
                    runSpacing: 10,
                    children: actions,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class KajInventorySection extends StatelessWidget {
  const KajInventorySection({
    super.key,
    required this.titleAr,
    required this.titleEn,
    required this.icon,
    required this.child,
    this.descriptionAr,
    this.descriptionEn,
  });
  final String titleAr;
  final String titleEn;
  final String? descriptionAr;
  final String? descriptionEn;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ar = context.l10n.isArabic;
    return KajShellSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                icon,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: AppText(
                  ar ? titleAr : titleEn,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          if ((ar ? descriptionAr : descriptionEn)?.isNotEmpty ==
              true) ...<Widget>[
            const SizedBox(height: 5),
            AppText(
              (ar ? descriptionAr : descriptionEn)!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class KajInventoryResponsiveFields extends StatelessWidget {
  const KajInventoryResponsiveFields({
    super.key,
    required this.children,
    this.minFieldWidth = 250,
  });
  final List<Widget> children;
  final double minFieldWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1050
          ? 3
          : constraints.maxWidth >= 650
          ? 2
          : 1;
      final gap = 14.0;
      final width = columns == 1
          ? constraints.maxWidth
          : (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: children
            .map(
              (child) => SizedBox(
                width: width < minFieldWidth ? constraints.maxWidth : width,
                child: child,
              ),
            )
            .toList(),
      );
    },
  );
}

class KajInventoryScreen extends StatelessWidget {
  const KajInventoryScreen({
    super.key,
    required this.children,
    this.maxWidth = 1320,
    this.padding = const EdgeInsets.all(20),
  });
  final List<Widget> children;
  final double maxWidth;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: KajDesignTokens.pageBackground(Theme.of(context).brightness),
    child: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: ListView(padding: padding, children: children),
        ),
      ),
    ),
  );
}

class KajInventoryLoadingState extends StatelessWidget {
  const KajInventoryLoadingState({super.key, this.rows = 5});
  final int rows;

  @override
  Widget build(BuildContext context) => KajShellSurface(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final count = rows < 1 ? 1 : rows;
        final bounded =
            constraints.hasBoundedHeight && constraints.maxHeight.isFinite;
        final gap = 8.0;
        final natural = 58.0;
        final height = bounded
            ? ((constraints.maxHeight - gap * (count - 1)) / count).clamp(
                24.0,
                natural,
              )
            : natural;
        final children = List<Widget>.generate(
          count,
          (index) => Container(
            height: height,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: .55),
              borderRadius: BorderRadius.circular(KajDesignTokens.radiusMd),
            ),
          ),
        );
        if (bounded) {
          return Column(
            mainAxisSize: MainAxisSize.max,
            children: <Widget>[
              for (var index = 0; index < children.length; index++) ...<Widget>[
                children[index],
                if (index != children.length - 1) const SizedBox(height: 8),
              ],
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (var index = 0; index < children.length; index++) ...<Widget>[
              children[index],
              if (index != children.length - 1) const SizedBox(height: 8),
            ],
          ],
        );
      },
    ),
  );
}

class KajInventoryEmptyState extends StatelessWidget {
  const KajInventoryEmptyState({
    super.key,
    required this.titleAr,
    required this.titleEn,
    required this.messageAr,
    required this.messageEn,
    this.action,
  });
  final String titleAr, titleEn, messageAr, messageEn;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final ar = context.l10n.isArabic;
    return KajSystemState(
      icon: Icons.inventory_2_outlined,
      title: ar ? titleAr : titleEn,
      message: ar ? messageAr : messageEn,
      action: action,
    );
  }
}
