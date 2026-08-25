import 'dart:convert';

import 'package:flutter/material.dart';

import 'app_preferences_types.dart';

class UserInterfacePreferences {
  const UserInterfacePreferences({
    required this.localeCode,
    required this.themeMode,
    required this.navigationPosition,
    required this.sideNavigationCollapsed,
    required this.favoriteRoutes,
    required this.collapsedNavigationGroups,
    required this.sideNavigationScrollOffset,
  });

  final String localeCode;
  final ThemeMode themeMode;
  final AppNavigationPosition navigationPosition;
  final bool sideNavigationCollapsed;
  final Set<String> favoriteRoutes;
  final Set<String> collapsedNavigationGroups;
  final double sideNavigationScrollOffset;

  factory UserInterfacePreferences.defaults() => const UserInterfacePreferences(
    localeCode: 'en',
    themeMode: ThemeMode.dark,
    navigationPosition: AppNavigationPosition.side,
    sideNavigationCollapsed: false,
    favoriteRoutes: <String>{},
    collapsedNavigationGroups: <String>{},
    sideNavigationScrollOffset: 0,
  );

  UserInterfacePreferences withV4VisualDefaults() => UserInterfacePreferences(
    localeCode: localeCode,
    themeMode: ThemeMode.dark,
    navigationPosition: AppNavigationPosition.side,
    sideNavigationCollapsed: false,
    favoriteRoutes: Set<String>.from(favoriteRoutes),
    collapsedNavigationGroups: Set<String>.from(collapsedNavigationGroups),
    sideNavigationScrollOffset: sideNavigationScrollOffset,
  );

  factory UserInterfacePreferences.fromMap(Map<String, dynamic> map) {
    final rawFavorites = map['favorite_routes'] ?? map['favoriteRoutes'];
    final rawGroups =
        map['collapsed_navigation_groups'] ?? map['collapsedNavigationGroups'];
    final rawOffset =
        map['side_navigation_scroll_offset'] ??
        map['sideNavigationScrollOffset'];

    return UserInterfacePreferences(
      localeCode: map['locale_code'] == 'ar' || map['localeCode'] == 'ar'
          ? 'ar'
          : 'en',
      themeMode: map['theme_mode'] == 'dark' || map['themeMode'] == 'dark'
          ? ThemeMode.dark
          : ThemeMode.light,
      navigationPosition:
          map['navigation_position'] == 'side' ||
              map['navigationPosition'] == 'side'
          ? AppNavigationPosition.side
          : AppNavigationPosition.top,
      sideNavigationCollapsed:
          map['side_navigation_collapsed'] == true ||
          map['sideNavigationCollapsed'] == true,
      favoriteRoutes: _stringSet(rawFavorites),
      collapsedNavigationGroups: _stringSet(rawGroups),
      sideNavigationScrollOffset: _number(rawOffset),
    );
  }

  factory UserInterfacePreferences.fromJson(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map) return UserInterfacePreferences.defaults();
    return UserInterfacePreferences.fromMap(Map<String, dynamic>.from(decoded));
  }

  Map<String, dynamic> toLocalMap() => <String, dynamic>{
    'localeCode': localeCode,
    'themeMode': themeMode == ThemeMode.dark ? 'dark' : 'light',
    'navigationPosition': navigationPosition == AppNavigationPosition.side
        ? 'side'
        : 'top',
    'sideNavigationCollapsed': sideNavigationCollapsed,
    'favoriteRoutes': favoriteRoutes.toList()..sort(),
    'collapsedNavigationGroups': collapsedNavigationGroups.toList()..sort(),
    'sideNavigationScrollOffset': sideNavigationScrollOffset,
  };

  Map<String, dynamic> toRemoteMap(String userId) => <String, dynamic>{
    'user_id': userId,
    'locale_code': localeCode,
    'theme_mode': themeMode == ThemeMode.dark ? 'dark' : 'light',
    'navigation_position': navigationPosition == AppNavigationPosition.side
        ? 'side'
        : 'top',
    'side_navigation_collapsed': sideNavigationCollapsed,
    'favorite_routes': favoriteRoutes.toList()..sort(),
    'collapsed_navigation_groups': collapsedNavigationGroups.toList()..sort(),
    'side_navigation_scroll_offset': sideNavigationScrollOffset,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };

  String toJson() => jsonEncode(toLocalMap());

  static Set<String> _stringSet(Object? value) {
    if (value is Iterable) {
      return value
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toSet();
    }
    return <String>{};
  }

  static double _number(Object? value) {
    final result = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    if (result == null || result.isNaN || result.isInfinite || result < 0) {
      return 0;
    }
    return result;
  }
}
