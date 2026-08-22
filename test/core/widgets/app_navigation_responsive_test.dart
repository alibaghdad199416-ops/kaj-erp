import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quality_line_erp/app/route_names.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/preferences/app_preferences_controller.dart';
import 'package:quality_line_erp/core/widgets/app_module_shell.dart';
import 'package:quality_line_erp/core/widgets/app_top_navigation.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';

class _NavigationAccessController extends AccessController {
  @override
  bool hasPermission(String code) => true;

  @override
  bool canEditField(
    String resource,
    String field, {
    String? writePermission,
    String? viewPermission,
  }) => true;
}

Future<AppPreferencesController> _preferences({
  required Locale locale,
  bool collapsed = false,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final controller = AppPreferencesController();
  await controller.load();
  await controller.setLocale(locale);
  await controller.setSideNavigationCollapsed(collapsed);
  return controller;
}

Widget _host({
  required Widget child,
  required Locale locale,
  required AppPreferencesController preferences,
  required AccessController access,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppPreferencesController>.value(
        value: preferences,
      ),
      ChangeNotifierProvider<AccessController>.value(value: access),
    ],
    child: MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  for (final locale in const <Locale>[Locale('en'), Locale('ar')]) {
    for (final collapsed in const <bool>[false, true]) {
      testWidgets(
        'side navigation ${collapsed ? 'collapsed' : 'expanded'} fits in ${locale.languageCode}',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(1024, 800);
          addTearDown(tester.view.reset);
          final preferences = await _preferences(
            locale: locale,
            collapsed: collapsed,
          );
          final access = _NavigationAccessController();
          addTearDown(preferences.dispose);
          addTearDown(access.dispose);

          await tester.pumpWidget(
            _host(
              locale: locale,
              preferences: preferences,
              access: access,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: AppSideNavigation(currentRoute: AppRouteNames.dashboard),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.byIcon(Icons.dashboard_outlined), findsOneWidget);
          expect(
            find.byIcon(Icons.notifications_active_outlined),
            findsOneWidget,
          );
          expect(
            find.byIcon(
              collapsed
                  ? Icons.keyboard_double_arrow_right_rounded
                  : Icons.keyboard_double_arrow_left_rounded,
            ),
            findsOneWidget,
          );
        },
      );
    }

    testWidgets(
      'force-collapsed side navigation keeps its bounded toggle in ${locale.languageCode}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(800, 700);
        addTearDown(tester.view.reset);
        final preferences = await _preferences(locale: locale);
        final access = _NavigationAccessController();
        addTearDown(preferences.dispose);
        addTearDown(access.dispose);

        await tester.pumpWidget(
          _host(
            locale: locale,
            preferences: preferences,
            access: access,
            child: const Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppSideNavigation(
                currentRoute: AppRouteNames.dashboard,
                forceCollapsed: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.byIcon(Icons.keyboard_double_arrow_right_rounded),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'top navigation survives dynamic widths in ${locale.languageCode}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final preferences = await _preferences(locale: locale);
        await preferences.setNavigationPosition(AppNavigationPosition.top);
        final access = _NavigationAccessController();
        addTearDown(preferences.dispose);
        addTearDown(access.dispose);

        for (final width in const <double>[1920, 1440, 1024, 800, 390, 320]) {
          tester.view.physicalSize = Size(width, 800);
          await tester.pumpWidget(
            _host(
              locale: locale,
              preferences: preferences,
              access: access,
              child: const Align(
                alignment: Alignment.topCenter,
                child: AppTopNavigation(currentRoute: AppRouteNames.dashboard),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'navigation overflow at width $width',
          );
        }

        expect(find.byIcon(Icons.manage_search_rounded), findsOneWidget);
        expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
        await tester.tap(find.byIcon(Icons.more_vert_rounded));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'actual shell adapts side-item and brand during animated resize in ${locale.languageCode}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1024, 800);
        addTearDown(tester.view.reset);
        final preferences = await _preferences(locale: locale);
        final access = _NavigationAccessController();
        addTearDown(preferences.dispose);
        addTearDown(access.dispose);

        await tester.pumpWidget(
          _host(
            locale: locale,
            preferences: preferences,
            access: access,
            child: const AppModuleShell(
              route: AppRouteNames.dashboard,
              child: SizedBox.expand(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        tester.view.physicalSize = const Size(1200, 800);
        await tester.pump();
        expect(
          find.byKey(
            const ValueKey('side-item-compact-${AppRouteNames.dashboard}'),
          ),
          findsOneWidget,
          reason:
              'the expanded item must use icon-only content while animation leaves about 38px',
        );
        expect(tester.takeException(), isNull);
        for (final elapsed in const <Duration>[
          Duration(milliseconds: 16),
          Duration(milliseconds: 32),
          Duration(milliseconds: 48),
          Duration(milliseconds: 64),
          Duration(milliseconds: 80),
        ]) {
          await tester.pump(elapsed);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpAndSettle();

        await preferences.setSideNavigationCollapsed(true);
        for (var frame = 0; frame < 8; frame++) {
          await tester.pump(const Duration(milliseconds: 24));
          expect(tester.takeException(), isNull);
        }
        await tester.pumpAndSettle();

        await preferences.setSideNavigationCollapsed(false);
        await tester.pump();
        expect(
          find.byKey(
            const ValueKey('side-item-compact-${AppRouteNames.dashboard}'),
          ),
          findsOneWidget,
        );
        for (var frame = 0; frame < 8; frame++) {
          await tester.pump(const Duration(milliseconds: 24));
          expect(tester.takeException(), isNull);
        }
        await tester.pumpAndSettle();

        tester.view.physicalSize = const Size(800, 700);
        for (var frame = 0; frame < 10; frame++) {
          await tester.pump(const Duration(milliseconds: 24));
          expect(tester.takeException(), isNull);
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
