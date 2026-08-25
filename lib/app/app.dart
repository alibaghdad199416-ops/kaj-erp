import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/preferences/app_preferences_controller.dart';
import 'package:quality_line_erp/core/widgets/app_background.dart';
import 'package:quality_line_erp/core/widgets/app_scroll_behavior.dart';
import 'routes.dart';
import 'theme.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.select<AppPreferencesController, ThemeMode>(
      (preferences) => preferences.themeMode,
    );
    final locale = context.select<AppPreferencesController, Locale>(
      (preferences) => preferences.locale,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scrollBehavior: const AppScrollBehavior(),
      onGenerateTitle: (context) => context.l10n.text('appName'),
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        return Directionality(
          textDirection: context.l10n.textDirection,
          child: AppBackground(child: child ?? const SizedBox.shrink()),
        );
      },
      initialRoute: AppRoutes.login,
      routes: AppRoutes.routes,
    );
  }
}
