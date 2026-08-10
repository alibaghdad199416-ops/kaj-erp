import 'package:flutter/material.dart';

import 'package:quality_line_erp/app/route_names.dart';
import 'package:quality_line_erp/core/widgets/app_page_lifecycle_scope.dart';

/// A consistent back button for ERP pages.
///
/// It pops the current route when navigation history exists. When a main
/// section was opened directly from the sidebar (so there is no route to pop),
/// it returns to the dashboard instead of leaving the user stranded.
class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    // Internal module windows are single-page workspaces. Their close command
    // is injected into the page command row, so a second back button would be
    // redundant and visually misleading.
    if (AppWorkspaceWindowScope.maybeOf(context) != null) {
      return const SizedBox.shrink();
    }
    return IconButton(
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      icon: Icon(
        Directionality.of(context) == TextDirection.rtl
            ? Icons.arrow_forward
            : Icons.arrow_back,
        color: color,
      ),
      onPressed: () async {
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.pop();
          return;
        }

        await Navigator.of(
          context,
          rootNavigator: true,
        ).pushNamedAndRemoveUntil(AppRouteNames.dashboard, (route) => false);
      },
    );
  }
}
