import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_entity_page.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:quality_line_erp/features/settings/access/pages/users_page.dart';
import 'package:quality_line_erp/features/settings/reports/pages/reports_page.dart';
import 'package:quality_line_erp/features/settings/recycle_bin/pages/recycle_bin_page.dart';
import 'package:quality_line_erp/features/settings/operational_periods/pages/operational_periods_page.dart';
import 'package:quality_line_erp/features/settings/system_monitor/pages/system_monitor_page.dart';

import 'settings_page.dart';

class SettingsHubPage extends StatefulWidget {
  const SettingsHubPage({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<SettingsHubPage> createState() => _SettingsHubPageState();
}

class _SettingsHubPageState extends State<SettingsHubPage> {
  late int _selected;
  late final List<Widget?> _sectionCache;

  static const _sections = <({String ar, String en, IconData icon})>[
    (
      ar: 'إعدادات النظام والمودلات',
      en: 'System and modules',
      icon: Icons.tune_outlined,
    ),
    (
      ar: 'المستخدمون والصلاحيات',
      en: 'Users and permissions',
      icon: Icons.admin_panel_settings_outlined,
    ),
    (
      ar: 'مراقبة النظام',
      en: 'System monitoring',
      icon: Icons.monitor_heart_outlined,
    ),
    (ar: 'التقارير', en: 'Reports', icon: Icons.assessment_outlined),
    (
      ar: 'الجدول الزمني',
      en: 'Operational timeline',
      icon: Icons.timeline_outlined,
    ),
    (ar: 'سلة المحذوفات', en: 'Recycle bin', icon: Icons.delete_sweep_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _selected = widget.initialIndex.clamp(0, _sections.length - 1);
    _sectionCache = List<Widget?>.filled(_sections.length, null);
    _sectionCache[_selected] = _buildSection(_selected);
  }

  Widget _buildSection(int index) => _guardSection(index, switch (index) {
    0 => const SettingsPage(embedded: true),
    1 => const UsersPage(),
    2 => const SystemMonitorPage(),
    3 => const ReportsPage(),
    4 => const OperationalPeriodsPage(),
    5 => const RecycleBinPage(),
    _ => const SizedBox.shrink(),
  });

  void _selectSection(int index) {
    setState(() {
      _selected = index;
      _sectionCache[index] ??= _buildSection(index);
    });
  }

  Widget _guardSection(int index, Widget child) {
    switch (index) {
      case 0:
        return FieldPermissionVisibility(
          resource: 'settings',
          field: 'companyProfile',
          child: child,
        );
      case 1:
        return PermissionVisibility(permission: 'users.view', child: child);
      case 2:
        return FieldPermissionVisibility(
          resource: 'settings',
          field: 'systemMonitor',
          viewPermission: 'settings.view',
          child: child,
        );
      case 3:
        return PermissionVisibility(permission: 'reports.view', child: child);
      case 4:
        return FieldPermissionVisibility(
          resource: 'settings',
          field: 'operationalPeriods',
          viewPermission: 'periods.view',
          child: child,
        );
      case 5:
        return FieldPermissionVisibility(
          resource: 'settings',
          field: 'recycleBin',
          viewPermission: 'settings.recycle_bin.view',
          child: child,
        );
      default:
        return child;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = context.l10n.isArabic;
    return AppEntityPage(
      key: const ValueKey('settings-hub-full-workspace'),
      hideHeader: true,
      title: 'الإعدادات والإدارة',
      subtitle: isArabic
          ? 'إدارة النظام والمستخدمين والمراقبة والتقارير.'
          : 'Manage the system, users, monitoring, and reports.',
      leading: const Icon(Icons.settings_suggest_outlined, size: 20),
      showBackButton: false,
      maxWidth: double.infinity,
      fillAvailableHeight: true,
      bodyPadding: const EdgeInsetsDirectional.fromSTEB(12, 4, 12, 10),
      toolbar: SizedBox(
        key: const ValueKey('settings-primary-horizontal-sections'),
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _sections.length,
          separatorBuilder: (_, _) => const SizedBox(width: 7),
          itemBuilder: (context, index) {
            final section = _sections[index];
            return _guardSection(
              index,
              ChoiceChip(
                selected: _selected == index,
                onSelected: (_) => _selectSection(index),
                avatar: Icon(section.icon, size: 17),
                label: AppText(isArabic ? section.ar : section.en),
                visualDensity: const VisualDensity(
                  horizontal: -3,
                  vertical: -3,
                ),
              ),
            );
          },
        ),
      ),
      body: SizedBox.expand(
        key: const ValueKey('settings-active-section-full-viewport'),
        child: IndexedStack(
          index: _selected,
          children: List<Widget>.generate(
            _sections.length,
            (index) => _sectionCache[index] ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
