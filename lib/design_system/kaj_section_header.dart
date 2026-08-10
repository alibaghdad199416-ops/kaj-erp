import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'kaj_design_tokens.dart';

/// Premium section identity used by module lists and management pages.
class KajSectionHeader extends StatelessWidget {
  const KajSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.actions = const <Widget>[],
    this.compact = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> actions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Container(
            width: compact ? 38 : 44,
            height: compact ? 38 : 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: <Color>[
                  KajDesignTokens.electricBlue.withValues(alpha: .22),
                  KajDesignTokens.electricBlue.withValues(alpha: .06),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: KajDesignTokens.electricBlue.withValues(alpha: .36),
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: KajDesignTokens.electricBlue.withValues(alpha: .08),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              icon,
              size: compact ? 18 : 21,
              color: KajDesignTokens.electricBlue,
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppText(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.35,
                  fontSize: compact ? 18 : 22,
                ),
              ),
              if (subtitle?.trim().isNotEmpty == true) ...<Widget>[
                const SizedBox(height: 4),
                AppText(
                  subtitle ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );

    if (actions.isEmpty) return heading;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              heading,
              const SizedBox(height: KajDesignTokens.space12),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Wrap(
                  spacing: KajDesignTokens.space8,
                  runSpacing: KajDesignTokens.space8,
                  children: actions,
                ),
              ),
            ],
          );
        }
        return Row(
          children: <Widget>[
            Expanded(child: heading),
            const SizedBox(width: KajDesignTokens.space16),
            Wrap(
              spacing: KajDesignTokens.space8,
              runSpacing: KajDesignTokens.space8,
              children: actions,
            ),
          ],
        );
      },
    );
  }
}
