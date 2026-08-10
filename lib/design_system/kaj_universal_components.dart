import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';

import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';

/// Universal KAJ Signature building blocks used by every module during the
/// full visual migration. They intentionally carry no business logic.
class KajPageFrame extends StatelessWidget {
  const KajPageFrame({
    super.key,
    required this.child,
    this.maxWidth = 1640,
    this.padding,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final media = MediaQuery.sizeOf(context);
    final horizontal = media.width >= 1440
        ? 28.0
        : media.width >= 900
        ? 20.0
        : 12.0;
    return ColoredBox(
      color: KajDesignTokens.workspace(brightness),
      child: SafeArea(
        top: false,
        child: Align(
          alignment: AlignmentDirectional.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding:
                  padding ??
                  EdgeInsets.fromLTRB(horizontal, 18, horizontal, 24),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class KajStatePanel extends StatelessWidget {
  const KajStatePanel({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.tone,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final Color? tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final accent = tone ?? theme.colorScheme.primary;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 18 : 28),
      decoration: BoxDecoration(
        gradient: KajDesignTokens.surfaceGradient(brightness),
        borderRadius: BorderRadius.circular(KajDesignTokens.radiusLg),
        border: Border.all(color: KajDesignTokens.border(brightness)),
        boxShadow: KajDesignTokens.softShadow(brightness),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: compact ? 46 : 58,
            height: compact ? 46 : 58,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(KajDesignTokens.radiusMd),
              border: Border.all(color: accent.withValues(alpha: .26)),
            ),
            child: Icon(icon, color: accent, size: compact ? 22 : 28),
          ),
          const SizedBox(height: 14),
          AppText(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: AppText(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ),
          if (action != null) ...<Widget>[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}

class KajLoadingPanel extends StatelessWidget {
  const KajLoadingPanel({super.key, required this.label, this.compact = false});
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) => KajStatePanel(
    icon: Icons.auto_awesome_rounded,
    title: label,
    message: '',
    compact: compact,
    action: const SizedBox(
      width: 210,
      child: LinearProgressIndicator(minHeight: 3),
    ),
  );
}

class KajResponsiveActionBar extends StatelessWidget {
  const KajResponsiveActionBar({
    super.key,
    required this.primary,
    this.secondary = const <Widget>[],
    this.leading,
  });

  final Widget primary;
  final List<Widget> secondary;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 760;
      final actions = <Widget>[...secondary, primary];
      if (narrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (leading != null) ...<Widget>[
              leading!,
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: actions,
            ),
          ],
        );
      }
      return Row(
        children: <Widget>[
          if (leading != null) Expanded(child: leading!) else const Spacer(),
          const SizedBox(width: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: actions,
          ),
        ],
      );
    },
  );
}
