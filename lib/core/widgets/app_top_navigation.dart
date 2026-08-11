import 'dart:async';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/app/brand_identity.dart';
import 'package:quality_line_erp/app/route_names.dart';
import 'package:quality_line_erp/core/auth/app_logout_coordinator.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';
import 'package:quality_line_erp/core/notifications/notification_unread_state.dart';
import 'package:quality_line_erp/core/preferences/app_preferences_controller.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'app_logo.dart';
import 'app_navigation_layout_controller.dart';

const _accent = BrandIdentity.electricBlue;
const _expandedSideWidth = 258.0;
const _collapsedSideWidth = 76.0;

/// Performs a top-level module switch after closing any transient module window.
///
/// The switch is scheduled for the next frame so pointer and focus events can
/// settle before the root route is replaced.
class AppModuleNavigation {
  AppModuleNavigation._();

  static bool _switching = false;
  static String? _pendingRoute;

  static void open(BuildContext context, String route, {String? currentRoute}) {
    _pendingRoute = route;
    FocusManager.instance.primaryFocus?.unfocus();
    if (_switching) return;
    _switching = true;
    unawaited(_drain(context));
  }

  static Future<void> _drain(BuildContext context) async {
    try {
      // Coalesce all taps that occur before the next frame into the latest
      // requested module. The root Navigator is resolved only at execution
      // time and the returned route future is deliberately not awaited: that
      // future completes when the pushed route is later removed, not when the
      // navigation operation itself finishes.
      await WidgetsBinding.instance.endOfFrame;
      if (!context.mounted) return;

      final target = _pendingRoute;
      _pendingRoute = null;
      if (target == null) return;

      final rootNavigator = Navigator.of(context, rootNavigator: true);
      if (!rootNavigator.mounted) return;
      unawaited(rootNavigator.pushNamedAndRemoveUntil(target, (_) => false));
    } finally {
      _switching = false;
      if (_pendingRoute != null && context.mounted) {
        open(context, _pendingRoute!);
      }
    }
  }
}

class AppTopNavigation extends StatelessWidget {
  const AppTopNavigation({super.key, required this.currentRoute});

  final String currentRoute;

  @override
  Widget build(BuildContext context) {
    final items = _visibleItems(context);
    return Material(
      elevation: 0,
      color: const Color(0xFF050B10),
      child: SizedBox(
        height: 68,
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsetsDirectional.only(start: 14, end: 10),
              child: AppLogo(width: 76, height: 50, borderRadius: 12),
            ),
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 4,
                ),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 4),
                itemBuilder: (context, index) => _TopItem(
                  item: items[index],
                  selected: items[index].route == currentRoute,
                ),
              ),
            ),
            _NavigationActions(currentRoute: currentRoute),
          ],
        ),
      ),
    );
  }
}

class AppSideNavigation extends StatefulWidget {
  const AppSideNavigation({
    super.key,
    required this.currentRoute,
    this.forceCollapsed = false,
  });

  final String currentRoute;
  final bool forceCollapsed;

  @override
  State<AppSideNavigation> createState() => _AppSideNavigationState();
}

class _AppSideNavigationState extends State<AppSideNavigation> {
  bool _restoredScrollPosition = false;
  bool? _lastEffectiveCollapsed;
  AppPreferencesController? _preferencesController;

  late final ScrollController _scrollController = ScrollController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _preferencesController = context.read<AppPreferencesController>();
    if (_restoredScrollPosition) return;
    _restoredScrollPosition = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _preferencesController?.sideNavigationScrollOffset ?? 0;
      final maximum = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(target.clamp(0, maximum).toDouble());
    });
  }

  @override
  void didUpdateWidget(covariant AppSideNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.forceCollapsed != widget.forceCollapsed) {
      _scheduleSideWidthSync();
    }
  }

  @override
  void dispose() {
    if (_scrollController.hasClients) {
      unawaited(
        _preferencesController?.setSideNavigationScrollOffset(
          _scrollController.offset,
        ),
      );
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleSideWidthSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final preferences = context.read<AppPreferencesController>();
      final collapsed =
          widget.forceCollapsed || preferences.sideNavigationCollapsed;
      AppNavigationLayoutController.sideWidth.value = collapsed
          ? _collapsedSideWidth
          : _expandedSideWidth;
    });
  }

  Future<void> _toggleCollapsed() async {
    final preferences = context.read<AppPreferencesController>();
    final next = !preferences.sideNavigationCollapsed;
    await preferences.setSideNavigationCollapsed(next);
  }

  Future<void> _toggleFavorite(String route) =>
      context.read<AppPreferencesController>().toggleFavoriteRoute(route);

  Future<void> _toggleGroup(String group) => context
      .read<AppPreferencesController>()
      .toggleCollapsedNavigationGroup(group);

  void _open(_NavItem item) {
    if (_scrollController.hasClients) {
      unawaited(
        context.read<AppPreferencesController>().setSideNavigationScrollOffset(
          _scrollController.offset,
        ),
      );
    }
    AppModuleNavigation.open(
      context,
      item.route,
      currentRoute: widget.currentRoute,
    );
  }

  @override
  Widget build(BuildContext context) {
    final preferences = context.watch<AppPreferencesController>();
    final collapsed = preferences.sideNavigationCollapsed;
    final favorites = preferences.favoriteRoutes;
    final collapsedGroups = preferences.collapsedNavigationGroups;
    final effectiveCollapsed = widget.forceCollapsed || collapsed;

    if (_lastEffectiveCollapsed != effectiveCollapsed) {
      _lastEffectiveCollapsed = effectiveCollapsed;
      _scheduleSideWidthSync();
    }

    final items = _visibleItems(context);
    final favoriteItems = items
        .where((item) => favorites.contains(item.route))
        .toList();

    final grouped = <String, List<_NavItem>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.group, () => <_NavItem>[]).add(item);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: effectiveCollapsed ? _collapsedSideWidth : _expandedSideWidth,
      child: Material(
        elevation: 0,
        color: const Color(0xFF050A0F),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: effectiveCollapsed ? 8 : 12,
              ),
              child: Row(
                mainAxisAlignment: effectiveCollapsed
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  if (!effectiveCollapsed)
                    const Expanded(child: _V4BrandBlock())
                  else
                    const AppLogo(width: 48, height: 38, borderRadius: 10),
                  IconButton(
                    tooltip: context.l10n.text(
                      effectiveCollapsed
                          ? 'expandNavigation'
                          : 'collapseNavigation',
                    ),
                    onPressed: widget.forceCollapsed ? null : _toggleCollapsed,
                    color: Colors.white54,
                    iconSize: 18,
                    icon: Icon(
                      effectiveCollapsed
                          ? Icons.keyboard_double_arrow_right_rounded
                          : Icons.keyboard_double_arrow_left_rounded,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Divider(
              color: KajDesignTokens.electricBlue.withValues(alpha: .16),
              height: 1,
            ),
            Expanded(
              child: !preferences.isLoaded
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : ListView(
                      key: ValueKey(
                        'app-side-navigation-list-${preferences.activeUserId ?? 'guest'}',
                      ),
                      controller: _scrollController,
                      padding: EdgeInsets.symmetric(
                        horizontal: effectiveCollapsed ? 8 : 10,
                        vertical: 10,
                      ),
                      children: [
                        if (!collapsed && favoriteItems.isNotEmpty)
                          _QuickSection(
                            title: context.l10n.text('favorites'),
                            icon: Icons.star_rounded,
                            items: favoriteItems,
                            currentRoute: widget.currentRoute,
                            favorites: favorites,
                            onOpen: _open,
                            onFavorite: _toggleFavorite,
                          ),
                        if (items.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 36,
                              horizontal: 8,
                            ),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.search_off_rounded,
                                  color: Colors.white38,
                                  size: 34,
                                ),
                                const SizedBox(height: 8),
                                AppText(
                                  context.l10n.text('noResults'),
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (effectiveCollapsed)
                          ...items.map(
                            (item) => _SideItem(
                              item: item,
                              selected: item.route == widget.currentRoute,
                              collapsed: true,
                              favorite: favorites.contains(item.route),
                              onTap: () => _open(item),
                              onFavorite: () => _toggleFavorite(item.route),
                            ),
                          )
                        else
                          ...grouped.entries.map(
                            (entry) => _NavigationGroup(
                              name: entry.key,
                              items: entry.value,
                              collapsed: collapsedGroups.contains(entry.key),
                              currentRoute: widget.currentRoute,
                              favorites: favorites,
                              onToggle: () => _toggleGroup(entry.key),
                              onOpen: _open,
                              onFavorite: _toggleFavorite,
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _QuickSection extends StatelessWidget {
  const _QuickSection({
    required this.title,
    required this.icon,
    required this.items,
    required this.currentRoute,
    required this.favorites,
    required this.onOpen,
    required this.onFavorite,
  });

  final String title;
  final IconData icon;
  final List<_NavItem> items;
  final String currentRoute;
  final Set<String> favorites;
  final ValueChanged<_NavItem> onOpen;
  final ValueChanged<String> onFavorite;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 7, bottom: 5),
            child: Row(
              children: [
                Icon(icon, size: 15, color: _accent),
                const SizedBox(width: 6),
                AppText(
                  title,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          ...items.map(
            (item) => _SideItem(
              item: item,
              selected: item.route == currentRoute,
              favorite: favorites.contains(item.route),
              dense: true,
              onTap: () => onOpen(item),
              onFavorite: () => onFavorite(item.route),
            ),
          ),
          Divider(
            color: KajDesignTokens.electricBlue.withValues(alpha: .12),
            height: 12,
          ),
        ],
      ),
    );
  }
}

class _V4BrandBlock extends StatelessWidget {
  const _V4BrandBlock();

  @override
  Widget build(BuildContext context) {
    final ar = context.l10n.isArabic;
    return Row(
      children: <Widget>[
        const AppLogo(width: 72, height: 48, borderRadius: 10),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppText(
                ar ? 'خط الجودة' : 'Khat Al-Jawda',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              AppText(
                ar ? 'للتجارة العامة والسيارات' : 'General & Automotive Trade',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 8.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NavigationGroup extends StatelessWidget {
  const _NavigationGroup({
    required this.name,
    required this.items,
    required this.collapsed,
    required this.currentRoute,
    required this.favorites,
    required this.onToggle,
    required this.onOpen,
    required this.onFavorite,
  });

  final String name;
  final List<_NavItem> items;
  final bool collapsed;
  final String currentRoute;
  final Set<String> favorites;
  final VoidCallback onToggle;
  final ValueChanged<_NavItem> onOpen;
  final ValueChanged<String> onFavorite;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
              child: Row(
                children: [
                  Icon(_groupIcon(name), size: 16, color: Colors.white54),
                  const SizedBox(width: 7),
                  Expanded(
                    child: AppText(
                      context.l10n.text(name),
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: collapsed ? -.25 : 0,
                    duration: const Duration(milliseconds: 170),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: Colors.white38,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: Column(
              children: items
                  .map(
                    (item) => _SideItem(
                      item: item,
                      selected: item.route == currentRoute,
                      favorite: favorites.contains(item.route),
                      onTap: () => onOpen(item),
                      onFavorite: () => onFavorite(item.route),
                    ),
                  )
                  .toList(),
            ),
            secondChild: const SizedBox.shrink(),
            crossFadeState: collapsed
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 190),
          ),
        ],
      ),
    );
  }
}

class _TopItem extends StatelessWidget {
  const _TopItem({required this.item, required this.selected});
  final _NavItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.l10n.text(item.labelKey),
      child: InkWell(
        borderRadius: BorderRadius.circular(KajDesignTokens.radiusSm),
        hoverColor: _accent.withValues(alpha: 0.10),
        onTap: () {
          AppModuleNavigation.open(
            context,
            item.route,
            currentRoute: selected ? item.route : null,
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected
                ? _accent.withValues(alpha: 0.13)
                : Colors.transparent,
            border: selected
                ? Border.all(color: _accent.withValues(alpha: 0.75))
                : null,
            borderRadius: BorderRadius.circular(KajDesignTokens.radiusSm),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: _accent.withValues(alpha: 0.18),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              _NavigationIcon(
                item: item,
                size: 19,
                color: selected ? _accent : Colors.white70,
              ),
              const SizedBox(width: 7),
              AppText(
                context.l10n.text(item.labelKey),
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigationIcon extends StatelessWidget {
  const _NavigationIcon({
    required this.item,
    required this.color,
    required this.size,
  });

  final _NavItem item;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(item.icon, color: color, size: size);
    if (item.route != AppRouteNames.notifications) return icon;

    return ValueListenableBuilder<int>(
      valueListenable: NotificationUnreadState.count,
      builder: (context, count, _) {
        if (count <= 0) return icon;
        final label = count > 99 ? '99+' : '$count';
        return Stack(
          clipBehavior: Clip.none,
          children: [
            icon,
            PositionedDirectional(
              top: -9,
              end: -12,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                alignment: Alignment.center,
                child: AppText(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SideItem extends StatelessWidget {
  const _SideItem({
    required this.item,
    required this.selected,
    required this.favorite,
    required this.onTap,
    required this.onFavorite,
    this.collapsed = false,
    this.dense = false,
  });

  final _NavItem item;
  final bool selected;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final bool collapsed;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final content = InkWell(
      borderRadius: BorderRadius.circular(KajDesignTokens.radiusSm),
      hoverColor: _accent.withValues(alpha: 0.09),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        padding: collapsed
            ? const EdgeInsets.symmetric(vertical: 11)
            : EdgeInsetsDirectional.fromSTEB(
                12,
                dense ? 8 : 10,
                4,
                dense ? 8 : 10,
              ),
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(
                  begin: AlignmentDirectional.centerStart,
                  end: AlignmentDirectional.centerEnd,
                  colors: <Color>[
                    _accent.withValues(alpha: .28),
                    _accent.withValues(alpha: .10),
                  ],
                )
              : null,
          color: selected ? null : Colors.transparent,
          border: Border.all(
            color: selected
                ? _accent.withValues(alpha: .52)
                : Colors.transparent,
          ),
          borderRadius: BorderRadius.circular(KajDesignTokens.radiusSm),
          boxShadow: selected
              ? <BoxShadow>[
                  BoxShadow(
                    color: _accent.withValues(alpha: .10),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: collapsed
            ? Center(
                child: _NavigationIcon(
                  item: item,
                  color: selected ? _accent : Colors.white70,
                  size: 21,
                ),
              )
            : Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      color: selected
                          ? Colors.white.withValues(alpha: .07)
                          : Colors.transparent,
                    ),
                    alignment: Alignment.center,
                    child: _NavigationIcon(
                      item: item,
                      color: selected ? Colors.white : Colors.white70,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: AppText(
                      context.l10n.text(item.labelKey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? Colors.white : Colors.white70,
                        fontSize: dense ? 12 : 12.5,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 30,
                      height: 30,
                    ),
                    tooltip: AppTranslation.translate(
                      favorite ? 'إزالة من المفضلة' : 'إضافة إلى المفضلة',
                    ),
                    onPressed: onFavorite,
                    icon: Icon(
                      favorite ? Icons.star_rounded : Icons.star_border_rounded,
                      color: favorite
                          ? const Color(0xFFFFC857)
                          : Colors.white30,
                      size: 17,
                    ),
                  ),
                ],
              ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: collapsed
          ? Tooltip(message: context.l10n.text(item.labelKey), child: content)
          : content,
    );
  }
}

class _NavigationActions extends StatelessWidget {
  const _NavigationActions({required this.currentRoute});

  final String currentRoute;

  @override
  Widget build(BuildContext context) {
    final preferences = context.watch<AppPreferencesController>();
    final access = context.watch<AccessController>();
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
    final buttons = <Widget>[
      _ActionButton(
        tooltip: context.l10n.text('globalSearch'),
        icon: Icons.manage_search_rounded,
        onPressed: () => AppModuleNavigation.open(
          context,
          AppRouteNames.globalSearch,
          currentRoute: currentRoute,
        ),
      ),
      _ActionButton(
        tooltip: context.l10n.text(
          preferences.usesSideNavigation
              ? 'useTopNavigation'
              : 'useSideNavigation',
        ),
        icon: preferences.usesSideNavigation
            ? Icons.table_rows_outlined
            : Icons.view_sidebar_outlined,
        onPressed: preferences.toggleNavigationPosition,
      ),
      if (canChangeLanguage)
        _ActionButton(
          tooltip: context.l10n.text('language'),
          text: preferences.isArabic ? 'EN' : 'ع',
          onPressed: preferences.toggleLocale,
        ),
      if (canChangeTheme)
        _ActionButton(
          tooltip: context.l10n.text('theme'),
          icon: preferences.isDarkMode
              ? Icons.light_mode_outlined
              : Icons.dark_mode_outlined,
          onPressed: preferences.toggleTheme,
        ),
      _ActionButton(
        tooltip: context.l10n.text('logout'),
        icon: Icons.logout,
        onPressed: () async {
          final access = context.read<AccessController>();
          final preferences = context.read<AppPreferencesController>();
          await AppLogoutCoordinator.run(
            clearAuthenticatedSession: access.logout,
            activateGuestPreferences: preferences.useGuestPreferences,
            isMounted: () => context.mounted,
            navigateToLogin: () => Navigator.of(
              context,
              rootNavigator: true,
            ).pushNamedAndRemoveUntil(AppRouteNames.login, (_) => false),
          );
        },
      ),
    ];

    return Row(children: [...buttons, const SizedBox(width: 6)]);
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.tooltip,
    required this.onPressed,
    this.icon,
    this.text,
  });
  final String tooltip;
  final VoidCallback onPressed;
  final IconData? icon;
  final String? text;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        style: IconButton.styleFrom(
          foregroundColor: Colors.white70,
          hoverColor: _accent.withValues(alpha: 0.28),
          highlightColor: _accent.withValues(alpha: 0.20),
        ),
        icon: text != null
            ? AppText(
                text!,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              )
            : Icon(icon),
      ),
    );
  }
}

List<_NavItem> _visibleItems(BuildContext context) {
  final access = context.watch<AccessController>();
  return <_NavItem>[
    _NavItem(
      AppRouteNames.dashboard,
      'dashboard',
      'dashboard.view',
      Icons.dashboard_outlined,
      'navigationHome',
    ),
    _NavItem(
      AppRouteNames.notifications,
      'notifications',
      'dashboard.view',
      Icons.notifications_active_outlined,
      'navigationHome',
    ),
    _NavItem(
      AppRouteNames.inventory,
      'inventory',
      'inventory.view',
      Icons.warehouse_outlined,
      'navigationInventoryOperations',
    ),
    _NavItem(
      AppRouteNames.maintenance,
      'maintenance',
      'maintenance.view',
      Icons.build_outlined,
      'navigationInventoryOperations',
    ),
    _NavItem(
      AppRouteNames.businessPartners,
      'businessPartner',
      'customers.view',
      Icons.handshake_outlined,
      'navigationPartnersService',
    ),
    _NavItem(
      AppRouteNames.customerService,
      'customerService',
      'customer_service.view',
      Icons.support_agent_outlined,
      'navigationPartnersService',
    ),
    _NavItem(
      AppRouteNames.sales,
      'sales',
      'sales.view',
      Icons.point_of_sale_outlined,
      'navigationCommercial',
    ),
    _NavItem(
      AppRouteNames.purchases,
      'purchases',
      'purchases.view',
      Icons.shopping_cart_outlined,
      'navigationCommercial',
    ),
    _NavItem(
      AppRouteNames.accounting,
      'accounting',
      'accounting.view',
      Icons.account_balance_outlined,
      'navigationFinance',
    ),
    _NavItem(
      AppRouteNames.settings,
      'settings',
      'settings.view',
      Icons.settings_outlined,
      'navigationAdministration',
    ),
  ].where((item) => access.hasPermission(item.permission)).toList();
}

IconData _groupIcon(String group) {
  switch (group) {
    case 'navigationHome':
      return Icons.home_outlined;
    case 'navigationInventoryOperations':
      return Icons.widgets_outlined;
    case 'navigationPartnersService':
      return Icons.groups_outlined;
    case 'navigationCommercial':
      return Icons.receipt_long_outlined;
    case 'navigationFinance':
      return Icons.account_balance_wallet_outlined;
    case 'navigationAdministration':
      return Icons.admin_panel_settings_outlined;
    default:
      return Icons.folder_outlined;
  }
}

class _NavItem {
  const _NavItem(
    this.route,
    this.labelKey,
    this.permission,
    this.icon,
    this.group,
  );
  final String route;
  final String labelKey;
  final String permission;
  final IconData icon;
  final String group;
}
