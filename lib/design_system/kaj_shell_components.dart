import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';

export 'package:quality_line_erp/design_system/kaj_universal_components.dart';
export 'package:quality_line_erp/design_system/kaj_completion_components.dart';

import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';

/// Shared shell controls for the full redesign. Business modules should use
/// these components instead of creating isolated visual treatments.
class KajShellSurface extends StatelessWidget {
  const KajShellSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = KajDesignTokens.radiusLg,
    this.emphasized = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        gradient: emphasized
            ? LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: <Color>[
                  KajDesignTokens.surface(brightness),
                  KajDesignTokens.electricBlue.withValues(alpha: .035),
                ],
              )
            : KajDesignTokens.surfaceGradient(brightness),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: KajDesignTokens.border(brightness)),
        boxShadow: KajDesignTokens.softShadow(brightness),
      ),
      child: child,
    );
  }
}

class KajPrimaryAction extends StatelessWidget {
  const KajPrimaryAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? const SizedBox.square(
            dimension: 17,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : AppText(label, maxLines: 1, overflow: TextOverflow.ellipsis);
    return FilledButton.icon(
      onPressed: busy ? null : onPressed,
      icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 18),
      label: child,
    );
  }
}

class KajSecondaryAction extends StatelessWidget {
  const KajSecondaryAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool destructive;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    style: destructive
        ? OutlinedButton.styleFrom(
            foregroundColor: KajDesignTokens.danger,
            side: BorderSide(
              color: KajDesignTokens.danger.withValues(alpha: .45),
            ),
          )
        : null,
    icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 18),
    label: AppText(label, maxLines: 1, overflow: TextOverflow.ellipsis),
  );
}

class KajField extends StatelessWidget {
  const KajField({
    super.key,
    this.controller,
    this.initialValue,
    this.label,
    this.hint,
    this.leading,
    this.trailing,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.readOnly = false,
    this.obscureText = false,
    this.maxLines = 1,
    this.keyboardType,
    this.validator,
    this.textInputAction,
  });

  final TextEditingController? controller;
  final String? initialValue;
  final String? label;
  final String? hint;
  final IconData? leading;
  final Widget? trailing;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final bool readOnly;
  final bool obscureText;
  final int maxLines;
  final TextInputType? keyboardType;
  final FormFieldValidator<String>? validator;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    initialValue: controller == null ? initialValue : null,
    enabled: enabled,
    readOnly: readOnly,
    obscureText: obscureText,
    maxLines: obscureText ? 1 : maxLines,
    keyboardType: keyboardType,
    validator: validator,
    textInputAction: textInputAction,
    onChanged: onChanged,
    onFieldSubmitted: onSubmitted,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: leading == null ? null : Icon(leading, size: 19),
      suffixIcon: trailing,
    ),
  );
}

class KajTableFrame extends StatelessWidget {
  const KajTableFrame({
    super.key,
    required this.child,
    this.header,
    this.footer,
    this.minWidth = 760,
  });

  final Widget child;
  final Widget? header;
  final Widget? footer;
  final double minWidth;

  @override
  Widget build(BuildContext context) => KajShellSurface(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (header != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: header,
          ),
        if (header != null)
          Divider(
            height: 1,
            color: KajDesignTokens.border(Theme.of(context).brightness),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: minWidth),
            child: child,
          ),
        ),
        if (footer != null) ...<Widget>[
          Divider(
            height: 1,
            color: KajDesignTokens.border(Theme.of(context).brightness),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: footer,
          ),
        ],
      ],
    ),
  );
}

class KajSystemState extends StatelessWidget {
  const KajSystemState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.tone,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final color = tone ?? Theme.of(context).colorScheme.primary;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: KajShellSurface(
          emphasized: true,
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(KajDesignTokens.radiusMd),
                  border: Border.all(color: color.withValues(alpha: .28)),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: 16),
              AppText(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 7),
              AppText(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              if (action != null) ...<Widget>[
                const SizedBox(height: 18),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
