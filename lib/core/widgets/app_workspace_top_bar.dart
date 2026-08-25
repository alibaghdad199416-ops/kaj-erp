import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/app/route_names.dart';
import 'package:quality_line_erp/core/cloud/erp_runtime_capabilities_controller.dart';
import 'package:quality_line_erp/core/events/app_data_refresh_coordinator.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/notifications/notification_unread_state.dart';
import 'package:quality_line_erp/core/preferences/app_preferences_controller.dart';
import 'package:quality_line_erp/core/widgets/app_user_avatar.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';
import 'package:quality_line_erp/features/settings/access/pages/current_user_profile_page.dart';

import 'app_top_navigation.dart';

/// Desktop workspace bar matching the approved V4 reference boards: quick
/// search on the leading side, compact system actions in the middle, and the
/// authenticated user name and job title on the trailing side.
class AppWorkspaceTopBar extends StatelessWidget {
  const AppWorkspaceTopBar({super.key, required this.currentRoute});

  final String currentRoute;

  @override
  Widget build(BuildContext context) {
    final preferences = context.watch<AppPreferencesController>();
    final access = context.watch<AccessController>();
    final user = access.currentUser;
    final canChangeLanguage = access.canEditField(
      'settings',
      'language',
      viewPermission: 'settings.view',
      writePermission: 'settings.view',
    );
    final canChangeTheme = access.canEditField(
      'settings',
      'theme',
      viewPermission: 'settings.view',
      writePermission: 'settings.view',
    );
    final ar = context.l10n.isArabic;
    final brightness = Theme.of(context).brightness;
    final dark = brightness == Brightness.dark;
    final title = _routeTitle(context, currentRoute);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 1240;
        final veryCompact = constraints.maxWidth < 920;
        return Container(
          height: veryCompact ? 62 : 68,
          margin: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 0),
          padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 12, 8),
          decoration: BoxDecoration(
            color: KajDesignTokens.surface(
              brightness,
            ).withValues(alpha: dark ? .96 : .94),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: KajDesignTokens.border(brightness)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? .30 : .08),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              if (!veryCompact)
                _ModuleIdentity(title: title, icon: _routeIcon(currentRoute)),
              if (!veryCompact) const SizedBox(width: 14),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: _QuickSearch(currentRoute: currentRoute),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              if (!compact) _ConnectionIndicator(currentRoute: currentRoute),
              if (!compact) const _RefreshWorkspaceButton(),
              if (!compact)
                _TopIconButton(
                  tooltip: ar ? 'أسعار الصرف' : 'Exchange rates',
                  icon: Icons.currency_exchange_rounded,
                  onPressed: () => AppModuleNavigation.open(
                    context,
                    AppRouteNames.accounting,
                    currentRoute: currentRoute,
                  ),
                ),
              if (canChangeTheme)
                _TopIconButton(
                  tooltip: context.l10n.text('theme'),
                  icon: preferences.isDarkMode
                      ? Icons.dark_mode_outlined
                      : Icons.light_mode_outlined,
                  onPressed: preferences.toggleTheme,
                ),
              _NotificationButton(currentRoute: currentRoute),
              if (canChangeLanguage)
                _TopIconButton(
                  tooltip: context.l10n.text('language'),
                  text: preferences.isArabic ? 'EN' : 'ع',
                  onPressed: preferences.toggleLocale,
                ),
              _TopIconButton(
                tooltip: context.l10n.text('logout'),
                icon: Icons.logout_rounded,
                onPressed: () async {
                  final access = context.read<AccessController>();
                  await context
                      .read<AppPreferencesController>()
                      .useGuestPreferences();
                  if (!context.mounted) return;
                  await Navigator.of(
                    context,
                    rootNavigator: true,
                  ).pushNamedAndRemoveUntil(AppRouteNames.login, (_) => false);
                  unawaited(access.logout());
                },
              ),
              if (!compact) const SizedBox(width: 8),
              if (!compact)
                Container(
                  width: 1,
                  height: 34,
                  color: KajDesignTokens.border(brightness),
                ),
              if (!compact) const SizedBox(width: 12),
              if (!compact)
                _UserIdentity(
                  title: user?.fullName.trim().isNotEmpty == true
                      ? user?.fullName.trim() ?? ''
                      : (ar ? 'مدير النظام' : 'System administrator'),
                  subtitle: user?.jobTitle.trim().isNotEmpty == true
                      ? user?.jobTitle.trim() ?? ''
                      : (user?.roleName.trim().isNotEmpty == true
                            ? user?.roleName.trim() ?? ''
                            : (ar ? 'مستخدم معتمد' : 'Authorized user')),
                ),
              const SizedBox(width: 10),
              InkWell(
                borderRadius: BorderRadius.circular(11),
                onTap: () => showCurrentUserProfileEditor(context),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: AppUserAvatar(
                    radius: 18,
                    avatarBase64: user?.avatarBase64,
                    fallbackText:
                        user?.fullName ?? (ar ? 'مدير النظام' : 'Admin'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ModuleIdentity extends StatelessWidget {
  const _ModuleIdentity({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: LinearGradient(
            colors: <Color>[
              KajDesignTokens.electricBlue.withValues(alpha: .22),
              KajDesignTokens.electricBlue.withValues(alpha: .06),
            ],
          ),
          border: Border.all(
            color: KajDesignTokens.electricBlue.withValues(alpha: .34),
          ),
        ),
        child: Icon(icon, color: KajDesignTokens.electricBlue, size: 18),
      ),
      const SizedBox(width: 9),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 150),
        child: AppText(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    ],
  );
}

class _QuickSearch extends StatelessWidget {
  const _QuickSearch({required this.currentRoute});

  final String currentRoute;

  @override
  Widget build(BuildContext context) {
    final ar = context.l10n.isArabic;
    return TextField(
      readOnly: true,
      onTap: () => AppModuleNavigation.open(
        context,
        AppRouteNames.globalSearch,
        currentRoute: currentRoute,
      ),
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 12,
      ),
      decoration: InputDecoration(
        isDense: true,
        hintText: ar ? 'بحث سريع...' : 'Quick search...',
        prefixIcon: const Icon(Icons.search_rounded, size: 19),
        suffixIcon: Container(
          margin: const EdgeInsets.all(7),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: .72),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: KajDesignTokens.border(Theme.of(context).brightness),
            ),
          ),
          child: AppText(
            'Ctrl + K',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        filled: true,
        fillColor: Theme.of(
          context,
        ).colorScheme.surfaceContainerHigh.withValues(alpha: .72),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: KajDesignTokens.border(Theme.of(context).brightness),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: KajDesignTokens.border(Theme.of(context).brightness),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: KajDesignTokens.electricBlue),
        ),
      ),
    );
  }
}

class _ConnectionIndicator extends StatelessWidget {
  const _ConnectionIndicator({required this.currentRoute});

  final String currentRoute;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ErpRuntimeCapabilitiesController>();
    final missing = controller.unavailableCapabilitiesForRoute(currentRoute);
    final checking = controller.isChecking;
    final failed = controller.checkFailed;
    final ready = controller.hasSnapshot && missing.isEmpty && !failed;
    final color = checking
        ? const Color(0xFFD3A42F)
        : ready
        ? const Color(0xFF2EB67D)
        : const Color(0xFFE15A5A);
    final arabic = context.l10n.isArabic;
    final message = checking
        ? (arabic ? 'جارٍ فحص الاتصال' : 'Checking connection')
        : failed
        ? (arabic
              ? 'تعذر التحقق من اتصال قاعدة البيانات'
              : 'Database connection could not be verified')
        : missing.isNotEmpty
        ? (arabic
              ? 'متطلبات ناقصة: ${missing.join(', ')}'
              : 'Missing capabilities: ${missing.join(', ')}')
        : (arabic ? 'Supabase متصل وجاهز' : 'Supabase connected and ready');

    return Tooltip(
      message: message,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: checking ? null : () => controller.check(force: true),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: .42)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              checking
                  ? SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: color,
                      ),
                    )
                  : Icon(
                      ready
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_off_outlined,
                      size: 17,
                      color: color,
                    ),
              const SizedBox(width: 6),
              AppText(
                ready
                    ? (arabic ? 'متصل' : 'Online')
                    : (arabic ? 'فحص' : 'Check'),
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RefreshWorkspaceButton extends StatefulWidget {
  const _RefreshWorkspaceButton();

  @override
  State<_RefreshWorkspaceButton> createState() =>
      _RefreshWorkspaceButtonState();
}

class _RefreshWorkspaceButtonState extends State<_RefreshWorkspaceButton> {
  bool _busy = false;

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await Future.wait<void>(<Future<void>>[
        context.read<AppDataRefreshCoordinator>().refreshAll(),
        context.read<ErpRuntimeCapabilitiesController>().check(force: true),
      ]);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _TopIconButton(
    tooltip: context.l10n.isArabic
        ? 'تحديث بيانات جميع الوحدات'
        : 'Refresh all module data',
    icon: _busy ? null : Icons.refresh_rounded,
    customIcon: _busy
        ? SizedBox.square(
            dimension: 17,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          )
        : null,
    onPressed: _busy ? () {} : _refresh,
  );
}

class _TopIconButton extends StatelessWidget {
  const _TopIconButton({
    required this.tooltip,
    required this.onPressed,
    this.icon,
    this.text,
    this.customIcon,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final IconData? icon;
  final String? text;
  final Widget? customIcon;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: IconButton(
      onPressed: onPressed,
      style: IconButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        hoverColor: KajDesignTokens.electricBlue.withValues(alpha: .14),
        highlightColor: KajDesignTokens.electricBlue.withValues(alpha: .10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon:
          customIcon ??
          (text == null
              ? Icon(icon, size: 20)
              : AppText(
                  text!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                )),
    ),
  );
}

class _NotificationButton extends StatelessWidget {
  const _NotificationButton({required this.currentRoute});

  final String currentRoute;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: NotificationUnreadState.count,
    builder: (context, count, _) => Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        _TopIconButton(
          tooltip: context.l10n.text('notifications'),
          icon: Icons.notifications_none_rounded,
          onPressed: () => AppModuleNavigation.open(
            context,
            AppRouteNames.notifications,
            currentRoute: currentRoute,
          ),
        ),
        if (count > 0)
          PositionedDirectional(
            top: 4,
            end: 3,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFE84E4E),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: const Color(0xFF071019), width: 1.5),
              ),
              child: AppText(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _UserIdentity extends StatelessWidget {
  const _UserIdentity({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AppText(
            title,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          AppText(
            subtitle,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      const SizedBox(width: 8),
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: KajDesignTokens.champagne.withValues(alpha: .10),
          border: Border.all(
            color: KajDesignTokens.champagne.withValues(alpha: .28),
          ),
        ),
        child: const Icon(
          Icons.workspace_premium_outlined,
          size: 18,
          color: KajDesignTokens.champagne,
        ),
      ),
    ],
  );
}

IconData _routeIcon(String route) => switch (route) {
  AppRouteNames.dashboard => Icons.dashboard_customize_outlined,
  AppRouteNames.inventory || AppRouteNames.products => Icons.warehouse_outlined,
  AppRouteNames.maintenance => Icons.build_circle_outlined,
  AppRouteNames.businessPartners => Icons.handshake_outlined,
  AppRouteNames.customerService => Icons.support_agent_outlined,
  AppRouteNames.sales => Icons.point_of_sale_outlined,
  AppRouteNames.purchases => Icons.shopping_cart_checkout_outlined,
  AppRouteNames.accounting => Icons.account_balance_outlined,
  AppRouteNames.settings => Icons.settings_suggest_outlined,
  AppRouteNames.reports => Icons.analytics_outlined,
  AppRouteNames.notifications => Icons.notifications_active_outlined,
  AppRouteNames.globalSearch => Icons.manage_search_rounded,
  _ => Icons.apps_rounded,
};

String _routeTitle(BuildContext context, String route) {
  final key = switch (route) {
    AppRouteNames.dashboard => 'dashboard',
    AppRouteNames.inventory => 'inventory',
    AppRouteNames.products => 'inventory',
    AppRouteNames.maintenance => 'maintenance',
    AppRouteNames.businessPartners => 'businessPartner',
    AppRouteNames.customerService => 'customerService',
    AppRouteNames.sales => 'sales',
    AppRouteNames.purchases => 'purchases',
    AppRouteNames.accounting => 'accounting',
    AppRouteNames.settings => 'settings',
    AppRouteNames.reports => 'settings',
    AppRouteNames.notifications => 'notifications',
    AppRouteNames.globalSearch => 'globalSearch',
    _ => 'appName',
  };
  return context.l10n.text(key);
}
