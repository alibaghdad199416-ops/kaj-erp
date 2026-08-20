import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'settings hub keeps one horizontal primary strip and one full-height active section',
    () {
      final source = File(
        'lib/features/settings/pages/settings_hub_page.dart',
      ).readAsStringSync();

      expect(source, contains("ValueKey('settings-hub-full-workspace')"));
      expect(source, contains('maxWidth: double.infinity'));
      expect(source, contains('fillAvailableHeight: true'));
      expect(
        source,
        contains("ValueKey('settings-primary-horizontal-sections')"),
      );
      expect(source, contains('scrollDirection: Axis.horizontal'));
      expect(
        source,
        contains("ValueKey('settings-active-section-full-viewport')"),
      );
      expect(source, contains('child: IndexedStack('));
    },
  );

  test(
    'system model uses a horizontal section strip and an expanded active viewport',
    () {
      final source = File(
        'lib/features/settings/pages/settings_page.dart',
      ).readAsStringSync();

      expect(
        source,
        contains("ValueKey('system-model-full-height-workspace')"),
      );
      expect(source, contains("ValueKey('system-model-horizontal-sections')"));
      expect(source, contains('scrollDirection: Axis.horizontal'));
      expect(
        source,
        contains("ValueKey('system-model-active-section-viewport')"),
      );
      expect(source, contains('Expanded(\n              child: TabBarView('));
    },
  );

  test(
    'company settings fill the available page instead of a narrow centered form card',
    () {
      final source = File(
        'lib/features/settings/pages/settings_page.dart',
      ).readAsStringSync();

      expect(source, contains("ValueKey('settings-company-full-page-scroll')"));
      expect(source, contains('constraints.maxHeight > 14'));
      expect(source, contains('constraints.maxHeight - 14'));
      expect(source, contains('final compact = constraints.maxWidth < 760'));
      expect(source, contains('(constraints.maxWidth - gap) / 2'));
      expect(
        source,
        isNot(contains('constraints: const BoxConstraints(maxWidth: 900)')),
      );
    },
  );

  test(
    'branches and currencies use actual-width responsive grids with full-page scrolling',
    () {
      final source = File(
        'lib/features/settings/pages/settings_page.dart',
      ).readAsStringSync();

      expect(
        source,
        contains("ValueKey('settings-branches-full-page-scroll')"),
      );
      expect(
        source,
        contains("ValueKey('settings-currencies-full-page-scroll')"),
      );
      expect(source, contains('const minCardWidth = 300.0'));
      expect(source, contains('const minCardWidth = 280.0'));
      expect(source, contains('.clamp(1, 4)'));
      expect(source, contains('SliverGridDelegateWithFixedCrossAxisCount('));
    },
  );

  test(
    'backup workspace has one full-page scroll surface and compact records',
    () {
      final source = File(
        'lib/features/settings/pages/settings_page.dart',
      ).readAsStringSync();

      expect(source, contains("ValueKey('settings-backups-full-page-scroll')"));
      expect(source, contains('visualDensity: VisualDensity.compact'));
      expect(
        source,
        contains('padding: const EdgeInsets.fromLTRB(2, 2, 2, 12)'),
      );
    },
  );
}
