import 'dart:async';

import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_page_lifecycle_scope.dart';

/// Close command rendered inside a module page's own command row.
class AppWindowCloseButton extends StatelessWidget {
  const AppWindowCloseButton({super.key});

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    key: const ValueKey<String>('module-inline-close'),
    onPressed: () =>
        unawaited(AppWorkspaceWindowScope.requestCloseCurrent(context)),
    icon: const Icon(Icons.close_rounded, size: 17),
    label: AppText(context.l10n.isArabic ? 'إغلاق' : 'Close'),
  );
}
