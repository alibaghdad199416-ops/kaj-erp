from pathlib import Path

root = Path('.')

# Business partners: remove the duplicated module hero.
p = root / 'lib/features/business_partners/pages/business_partners_page.dart'; s = p.read_text()
start = s.index('          Padding(\n            padding: EdgeInsetsDirectional.fromSTEB(12, 8, 12, 8),\n            child: KajRelationshipHero(')
end = s.index('          Padding(\n            padding: EdgeInsetsDirectional.fromSTEB(12, 2, 12, 6),', start)
s = s[:start] + s[end:]
s = s.replace("import 'package:quality_line_erp/design_system/kaj_relationship_stage5_components.dart';\n", '')
p.write_text(s)

# Dashboard: keep KPIs, but remove the large module hero container.
p = root / 'lib/features/dashboard/pages/dashboard_page.dart'; s = p.read_text()
start = s.index('                    KajSignaturePageHero(')
end = s.index('                    if (controller.isLoading) ...[', start)
replacement = '''                    Wrap(\n                      spacing: 8,\n                      runSpacing: 8,\n                      children: [\n                        if (can('todaySales'))\n                          Chip(\n                            avatar: const Icon(Icons.trending_up_rounded, size: 17),\n                            label: AppText(\n                              '${context.l10n.isArabic ? 'مبيعات اليوم' : 'Today sales'}: ${CurrencyTotalsFormatter.format(dashboard.todaySalesByCurrency)}',\n                            ),\n                          ),\n                        if (can('availableCars'))\n                          Chip(\n                            avatar: const Icon(Icons.directions_car_filled_outlined, size: 17),\n                            label: AppText(\n                              '${context.l10n.isArabic ? 'السيارات المتوفرة' : 'Available vehicles'}: ${dashboard.availableCars}',\n                            ),\n                          ),\n                        if (can('overdueInstallments'))\n                          Chip(\n                            avatar: const Icon(Icons.schedule_rounded, size: 17),\n                            label: AppText(\n                              '${context.l10n.isArabic ? 'الأقساط المتأخرة' : 'Overdue installments'}: ${dashboard.overdueInstallments}',\n                            ),\n                          ),\n                      ],\n                    ),\n'''
s = s[:start] + replacement + s[end:]
p.write_text(s)

# Notifications: replace the large hero with a compact information strip.
p = root / 'lib/features/notifications/pages/notification_center_page.dart'; s = p.read_text()
start = s.index('            KajSignaturePageHero(')
end = s.index('            const SizedBox(height: 10),', start)
replacement = '''            Wrap(\n              spacing: 8,\n              runSpacing: 8,\n              children: [\n                Chip(\n                  avatar: const Icon(Icons.mark_email_unread_outlined, size: 17),\n                  label: AppText('${ar ? 'غير مقروء' : 'Unread'}: $_unreadCount'),\n                ),\n                Chip(\n                  avatar: Icon(Icons.crisis_alert_rounded, size: 17, color: KajDesignTokens.danger),\n                  label: AppText('${ar ? 'حرج' : 'Critical'}: $critical'),\n                ),\n                Chip(\n                  avatar: Icon(Icons.warning_amber_rounded, size: 17, color: KajDesignTokens.warning),\n                  label: AppText('${ar ? 'تحذيرات' : 'Warnings'}: $warning'),\n                ),\n              ],\n            ),\n'''
s = s[:start] + replacement + s[end:]
p.write_text(s)

# Sales: remove the duplicated commercial hero; the app shell remains the module title surface.
p = root / 'lib/features/sales/pages/sales_page.dart'; s = p.read_text()
start = s.index('            Padding(\n              padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),\n              child: KajCommercialHero(')
end = s.index('            Card(\n              margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),', start)
s = s[:start] + s[end:]
p.write_text(s)

# Purchases: remove the duplicated commercial hero; retain the existing compact KPI strip.
p = root / 'lib/features/purchases/pages/purchases_page.dart'; s = p.read_text()
start = s.index('          KajCommercialHero(\n')
end = s.index('          const SizedBox(height: 10),\n          Wrap(', start)
s = s[:start] + s[end:]
p.write_text(s)

# Accounting: remove the large executive hero from the module body.
p = root / 'lib/features/accounting/pages/accounting_center_page.dart'; s = p.read_text()
start = s.index('          Padding(\n            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),\n            child: KajExecutiveHero(')
end = s.index('          const SizedBox(height: 12),', start)
s = s[:start] + s[end:]
p.write_text(s)

# Maintenance list: remove the duplicated hero while preserving create/refresh actions.
p = root / 'lib/features/maintenance/pages/maintenance_page.dart'; s = p.read_text()
start = s.index('          KajRelationshipHero(\n', s.index('      toolbar: Column('))
end = s.index('          const SizedBox(height: 12),\n          TextField(', start)
replacement = '''          Align(\n            alignment: AlignmentDirectional.centerEnd,\n            child: Wrap(\n              spacing: 8,\n              runSpacing: 8,\n              children: [\n                if (PermissionAction.allowed(context, 'maintenance.create'))\n                  FilledButton.icon(\n                    onPressed: () => _open(),\n                    icon: const Icon(Icons.add_rounded),\n                    label: AppText(t('أمر صيانة جديد', 'New service order')),\n                  ),\n                OutlinedButton.icon(\n                  onPressed: () =>\n                      context.read<MaintenanceController>().loadOrders(force: true),\n                  icon: const Icon(Icons.refresh_rounded),\n                  label: AppText(t('تحديث مباشر', 'Live refresh')),\n                ),\n              ],\n            ),\n          ),\n'''
s = s[:start] + replacement + s[end:]
p.write_text(s)

# Maintenance create/edit: remove the hero and keep its status badge compact.
p = root / 'lib/features/maintenance/pages/add_maintenance_order_page.dart'; s = p.read_text()
start = s.index('            KajRelationshipHero(\n')
end = s.index('            const SizedBox(height: 12),\n            KajWorkflowStepper(', start)
replacement = '''            Align(\n              alignment: AlignmentDirectional.centerEnd,\n              child: KajStatusBadge(\n                label: _editing\n                    ? t('وضع التعديل', 'EDIT MODE')\n                    : t('مسودة جديدة', 'NEW DRAFT'),\n                color: _editing\n                    ? KajDesignTokens.warning\n                    : KajDesignTokens.electricBlue,\n                icon: _editing ? Icons.edit_outlined : Icons.add_task_rounded,\n              ),\n            ),\n'''
s = s[:start] + replacement + s[end:]
p.write_text(s)

# Maintenance details: remove the hero and retain its status badge.
p = root / 'lib/features/maintenance/pages/maintenance_order_details_dialog.dart'; s = p.read_text()
start = s.index('                KajRelationshipHero(\n')
end = s.index('                const SizedBox(height: 12),\n                KajWorkflowStepper(', start)
replacement = '''                Align(\n                  alignment: AlignmentDirectional.centerEnd,\n                  child: KajStatusBadge(\n                    label: order.workflowLabel(_arabic),\n                    color: order.isCancelled\n                        ? KajDesignTokens.danger\n                        : KajDesignTokens.success,\n                    icon: order.isCancelled\n                        ? Icons.cancel_outlined\n                        : Icons.verified_outlined,\n                  ),\n                ),\n'''
s = s[:start] + replacement + s[end:]
p.write_text(s)

# Remove imports that became unused after the hero removal.
for rel in [
    'lib/features/dashboard/pages/dashboard_page.dart',
    'lib/features/notifications/pages/notification_center_page.dart',
    'lib/features/sales/pages/sales_page.dart',
    'lib/features/purchases/pages/purchases_page.dart',
    'lib/features/accounting/pages/accounting_center_page.dart',
    'lib/features/maintenance/pages/maintenance_page.dart',
]:
    p = root / rel; s = p.read_text()
    for imp in [
        "import 'package:quality_line_erp/design_system/kaj_phase5_components.dart';\n",
        "import 'package:quality_line_erp/design_system/kaj_relationship_stage5_components.dart';\n",
    ]:
        if 'KajCommercialHero' not in s and 'KajSignaturePageHero' not in s and 'KajExecutiveHero' not in s and 'KajRelationshipHero' not in s:
            s = s.replace(imp, '')
    p.write_text(s)

print('phase_a_apply.py: Flutter module chrome migration prepared')
