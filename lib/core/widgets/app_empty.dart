import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:flutter/material.dart';

class AppEmpty extends StatelessWidget {
  const AppEmpty({
    super.key,
    this.title = 'لا توجد بيانات',
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });
  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.hasBoundedHeight && constraints.maxHeight < 220;
        if (!compact) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _content(
                context,
                iconSize: 34,
                iconGap: 10,
                messageGap: 6,
                actionGap: 14,
              ),
            ),
          );
        }

        final veryShort = constraints.maxHeight < 120;
        final verticalPadding = veryShort ? 4.0 : 8.0;
        final availableHeight = (constraints.maxHeight - verticalPadding * 2)
            .clamp(0.0, double.infinity);
        return SingleChildScrollView(
          key: const ValueKey('app-empty-bounded-scroll'),
          padding: EdgeInsets.symmetric(
            horizontal: veryShort ? 8 : 12,
            vertical: verticalPadding,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: availableHeight),
            child: Center(
              child: _content(
                context,
                iconSize: veryShort ? 20 : 26,
                iconGap: veryShort ? 3 : 5,
                messageGap: veryShort ? 2 : 4,
                actionGap: veryShort ? 4 : 7,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _content(
    BuildContext context, {
    required double iconSize,
    required double iconGap,
    required double messageGap,
    required double actionGap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          icon,
          size: iconSize,
          color: Theme.of(context).colorScheme.outline,
        ),
        SizedBox(height: iconGap),
        AppText(
          AppTranslation.translate(title),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (message != null) ...<Widget>[
          SizedBox(height: messageGap),
          AppText(
            AppTranslation.translate(message!),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (action != null) ...<Widget>[SizedBox(height: actionGap), action!],
      ],
    );
  }
}
