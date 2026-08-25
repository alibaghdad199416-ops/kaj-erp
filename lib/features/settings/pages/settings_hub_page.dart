import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_entity_page.dart';
import 'package:quality_line_erp/design_system/kaj_admin_stage8_components.dart';
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
      hideHeader: true,
      title: 'الإعدادات والإدارة',
      subtitle: isArabic
          ? 'إدارة النظام والمستخدمين والمراقبة والتقارير.'
          : 'Manage the system, users, monitoring, and reports.',
      leading: const Icon(Icons.settings_suggest_outlined, size: 20),
      showBackButton: false,
      toolbar: SizedBox(
        height: 34,
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
                onSelected: (_) => setState(() => _selected = index),
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
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: KajAdminWorkspace(
              title: isArabic
                  ? 'مركز الإدارة والتحكم'
                  : 'Administration & Control Center',
              subtitle: isArabic
                  ? 'إدارة الإعدادات والمستخدمين والصلاحيات والمراقبة والسجلات والنسخ الاحتياطية من مساحة موحدة.'
                  : 'Manage settings, users, permissions, monitoring, audit records and backups from one unified workspace.',
              icon: Icons.settings_suggest_outlined,
              metrics: <KajAdminMetricData>[
                KajAdminMetricData(
                  label: isArabic ? 'الأقسام' : 'Sections',
                  value: _sections.length.toString(),
                  icon: Icons.dashboard_customize_outlined,
                ),
                KajAdminMetricData(
                  label: isArabic ? 'الوصول' : 'Access',
                  value: isArabic ? 'محكوم' : 'Governed',
                  icon: Icons.verified_user_outlined,
                ),
                KajAdminMetricData(
                  label: isArabic ? 'المراقبة' : 'Monitoring',
                  value: isArabic ? 'مباشر' : 'Live',
                  icon: Icons.monitor_heart_outlined,
                ),
                KajAdminMetricData(
                  label: isArabic ? 'الاستعادة' : 'Recovery',
                  value: isArabic ? 'جاهزة' : 'Ready',
                  icon: Icons.settings_backup_restore_outlined,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: IndexedStack(
              index: _selected,
              children: [
                _guardSection(0, const SettingsPage(embedded: true)),
                _guardSection(1, const UsersPage()),
                _guardSection(2, const SystemMonitorPage()),
                _guardSection(3, const ReportsPage()),
                _guardSection(4, const OperationalPeriodsPage()),
                _guardSection(5, const RecycleBinPage()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
