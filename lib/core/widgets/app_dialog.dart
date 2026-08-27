import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';

/// Compatibility wrapper retained for older module dialogs.
/// New code should prefer [showAppConfirmDialog] or the module-dialog helpers.
class AppDialog extends AlertDialog {
  AppDialog({
    super.key,
    required String title,
    Widget? content,
    List<Widget>? actions,
  }) : super(
          title: AppText(AppTranslation.translate(title)),
          content: content,
          actions: actions,
        );
}

Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'تأكيد',
  bool destructive = false,
}) async {
  final translatedTitle = AppTranslation.translate(title);
  final translatedMessage = AppTranslation.translate(message);
  final translatedConfirm = AppTranslation.translate(confirmLabel);
  final accent = destructive ? KajDesignTokens.danger : KajDesignTokens.electricBlue;

  return await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        barrierColor: Colors.black.withValues(alpha: .68),
        builder: (dialogContext) => AlertDialog(
          iconPadding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
          icon: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(KajDesignTokens.radiusSm),
                border: Border.all(color: accent.withValues(alpha: .28)),
              ),
              child: Icon(
                destructive ? Icons.delete_outline_rounded : Icons.verified_outlined,
                color: accent,
              ),
            ),
          ),
          titlePadding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
          title: AppText(translatedTitle, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          contentPadding: const EdgeInsets.fromLTRB(22, 10, 22, 8),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: AppText(translatedMessage, style: TextStyle(color: Theme.of(dialogContext).colorScheme.onSurfaceVariant, height: 1.5)),
          ),
          actions: <Widget>[
            OutlinedButton(onPressed: () => Navigator.pop(dialogContext, false), child: AppText(AppTranslation.translate('إلغاء'))),
            FilledButton.icon(
              style: destructive ? FilledButton.styleFrom(backgroundColor: KajDesignTokens.danger, foregroundColor: Colors.white) : null,
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: Icon(destructive ? Icons.delete_forever_outlined : Icons.check_rounded),
              label: AppText(translatedConfirm),
            ),
          ],
        ),
      ) ??
      false;
}
