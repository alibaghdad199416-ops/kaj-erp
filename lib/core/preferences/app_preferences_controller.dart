import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/logging/app_logger.dart';

import 'app_preferences_types.dart';
import 'user_interface_preferences.dart';
import 'user_interface_preferences_repository.dart';

export 'app_preferences_types.dart';

class AppPreferencesController extends ChangeNotifier {
  AppPreferencesController({SupabaseClient? client})
    : _client = client ?? _resolveClient() {
    final activeClient = _client;
    if (activeClient != null) {
      _repository = UserInterfacePreferencesRepository(activeClient);
      _authSubscription = activeClient.auth.onAuthStateChange.listen((event) {
        unawaited(_activateUser(event.session?.user.id));
      });
    }
  }

  static const _localPrefix = 'user_ui_preferences_v2';
  static const _guestScope = 'guest';
  static const _v4VisualMarkerPrefix = 'kaj_v4_visual_layout_applied';
  static const _legacyKeys = <String>[
    'app_locale',
    'app_theme_mode',
    'app_navigation_position',
    'side_navigation_collapsed',
    'side_navigation_favorites',
    'side_navigation_collapsed_groups',
  ];

  final SupabaseClient? _client;
  UserInterfacePreferencesRepository? _repository;
  StreamSubscription<AuthState>? _authSubscription;
  SharedPreferences? _preferences;
  Future<void>? _loadFuture;
  Future<void>? _activationInFlight;
  String? _activationTarget;
  Future<void> _writeQueue = Future<void>.value();
  int _activationGeneration = 0;
  String? _activeUserId;

  Locale _locale = const Locale('en');
  ThemeMode _themeMode = ThemeMode.dark;
  AppNavigationPosition _navigationPosition = AppNavigationPosition.side;
  bool _sideNavigationCollapsed = false;
  Set<String> _favoriteRoutes = <String>{};
  Set<String> _collapsedNavigationGroups = <String>{};
  double _sideNavigationScrollOffset = 0;
  bool _isLoaded = false;

  Locale get locale => _locale;
  ThemeMode get themeMode => _themeMode;
  AppNavigationPosition get navigationPosition => _navigationPosition;
  bool get isLoaded => _isLoaded;
  bool get isArabic => _locale.languageCode == 'ar';
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  bool get usesSideNavigation =>
      _navigationPosition == AppNavigationPosition.side;
  bool get sideNavigationCollapsed => _sideNavigationCollapsed;
  Set<String> get favoriteRoutes => Set<String>.unmodifiable(_favoriteRoutes);
  Set<String> get collapsedNavigationGroups =>
      Set<String>.unmodifiable(_collapsedNavigationGroups);
  double get sideNavigationScrollOffset => _sideNavigationScrollOffset;
  String? get activeUserId => _activeUserId;

  Future<void> load() =>
      _loadFuture ??= _activateUser(_client?.auth.currentUser?.id, force: true);

  Future<void> synchronizeForCurrentUser() =>
      _activateUser(_client?.auth.currentUser?.id);

  Future<void> useGuestPreferences() => _activateUser(null, force: true);

  Future<void> _activateUser(String? userId, {bool force = false}) {
    if (!force && _isLoaded && _activeUserId == userId) {
      return Future<void>.value();
    }
    final active = _activationInFlight;
    if (active != null && _activationTarget == userId) return active;

    final request = _activateUserNow(userId, force: force);
    _activationTarget = userId;
    _activationInFlight = request;
    return request.whenComplete(() {
      if (identical(_activationInFlight, request)) {
        _activationInFlight = null;
        _activationTarget = null;
      }
    });
  }

  Future<void> _activateUserNow(String? userId, {bool force = false}) async {
    if (!force && _isLoaded && _activeUserId == userId) return;
    final generation = ++_activationGeneration;
    _activeUserId = userId;
    final store = _preferences ??= await SharedPreferences.getInstance();
    await store.reload();

    final local = _readLocal(store, userId);
    final visualMarkerKey = '$_v4VisualMarkerPrefix.${userId ?? _guestScope}';
    final needsV4VisualMigration = store.getBool(visualMarkerKey) != true;
    final localPreferences = local ?? UserInterfacePreferences.defaults();
    if (generation != _activationGeneration) return;
    _apply(
      needsV4VisualMigration
          ? localPreferences.withV4VisualDefaults()
          : localPreferences,
    );
    _isLoaded = true;
    notifyListeners();

    // Old global keys caused one user's choices to leak into another account.
    // They are deliberately removed and never migrated to a user scope.
    for (final key in _legacyKeys) {
      await store.remove(key);
    }

    if (userId == null) {
      if (needsV4VisualMigration) {
        final migrated = _snapshot();
        await store.setString(_localKey(userId), migrated.toJson());
        await store.setBool(visualMarkerKey, true);
      }
      return;
    }
    try {
      final remote = await _repository?.fetch(userId);
      if (generation != _activationGeneration || _activeUserId != userId) {
        return;
      }
      if (remote != null) {
        final resolved = needsV4VisualMigration
            ? remote.withV4VisualDefaults()
            : remote;
        _apply(resolved);
        await store.setString(_localKey(userId), resolved.toJson());
        if (needsV4VisualMigration) {
          await _repository?.save(userId, resolved);
          await store.setBool(visualMarkerKey, true);
        }
        notifyListeners();
      } else {
        final snapshot = _snapshot();
        await _repository?.save(userId, snapshot);
        if (needsV4VisualMigration) {
          await store.setString(_localKey(userId), snapshot.toJson());
          await store.setBool(visualMarkerKey, true);
        }
      }
    } catch (error, stackTrace) {
      AppLogger.debug('User UI preferences cloud restore failed: $error');
      AppLogger.stack(stackTrace);
    }
  }

  UserInterfacePreferences? _readLocal(
    SharedPreferences store,
    String? userId,
  ) {
    final raw = store.getString(_localKey(userId));
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return UserInterfacePreferences.fromJson(raw);
    } catch (error, stackTrace) {
      AppLogger.debug('User UI preferences local restore failed: $error');
      AppLogger.stack(stackTrace);
      return null;
    }
  }

  void _apply(UserInterfacePreferences value) {
    _locale = Locale(value.localeCode == 'en' ? 'en' : 'ar');
    AppTranslation.localeCode = _locale.languageCode;
    _themeMode = value.themeMode;
    _navigationPosition = value.navigationPosition;
    _sideNavigationCollapsed = value.sideNavigationCollapsed;
    _favoriteRoutes = Set<String>.from(value.favoriteRoutes);
    _collapsedNavigationGroups = Set<String>.from(
      value.collapsedNavigationGroups,
    );
    _sideNavigationScrollOffset = value.sideNavigationScrollOffset;
  }

  UserInterfacePreferences _snapshot() => UserInterfacePreferences(
    localeCode: _locale.languageCode,
    themeMode: _themeMode,
    navigationPosition: _navigationPosition,
    sideNavigationCollapsed: _sideNavigationCollapsed,
    favoriteRoutes: Set<String>.from(_favoriteRoutes),
    collapsedNavigationGroups: Set<String>.from(_collapsedNavigationGroups),
    sideNavigationScrollOffset: _sideNavigationScrollOffset,
  );

  String _localKey(String? userId) => '$_localPrefix.${userId ?? _guestScope}';

  Future<void> _persistCurrent() {
    final userId = _activeUserId;
    final snapshot = _snapshot();
    final operation = _writeQueue.then((_) async {
      final store = _preferences ??= await SharedPreferences.getInstance();
      final saved = await store.setString(_localKey(userId), snapshot.toJson());
      if (!saved) {
        throw StateError('Unable to save user interface preferences locally.');
      }
      if (userId != null) {
        try {
          await _repository?.save(userId, snapshot);
        } catch (error, stackTrace) {
          AppLogger.debug('User UI preferences cloud save failed: $error');
          AppLogger.stack(stackTrace);
        }
      }
    });
    _writeQueue = operation.catchError((_) {});
    return operation;
  }

  Future<void> toggleLocale() async {
    await setLocale(isArabic ? const Locale('en') : const Locale('ar'));
  }

  Future<void> setLocale(Locale locale) async {
    final next = Locale(locale.languageCode == 'en' ? 'en' : 'ar');
    if (_locale.languageCode == next.languageCode) return;
    _locale = next;
    AppTranslation.localeCode = _locale.languageCode;
    notifyListeners();
    await _persistCurrent();
  }

  Future<void> toggleTheme() async {
    await setThemeMode(isDarkMode ? ThemeMode.light : ThemeMode.dark);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final next = mode == ThemeMode.dark ? ThemeMode.dark : ThemeMode.light;
    if (_themeMode == next) return;
    _themeMode = next;
    notifyListeners();
    await _persistCurrent();
  }

  Future<void> toggleNavigationPosition() async {
    await setNavigationPosition(
      usesSideNavigation
          ? AppNavigationPosition.top
          : AppNavigationPosition.side,
    );
  }

  Future<void> setNavigationPosition(AppNavigationPosition position) async {
    if (_navigationPosition == position) return;
    _navigationPosition = position;
    notifyListeners();
    await _persistCurrent();
  }

  Future<void> setSideNavigationCollapsed(bool collapsed) async {
    if (_sideNavigationCollapsed == collapsed) return;
    _sideNavigationCollapsed = collapsed;
    notifyListeners();
    await _persistCurrent();
  }

  Future<void> toggleFavoriteRoute(String route) async {
    final normalized = route.trim();
    if (normalized.isEmpty) return;
    if (!_favoriteRoutes.add(normalized)) {
      _favoriteRoutes.remove(normalized);
    }
    notifyListeners();
    await _persistCurrent();
  }

  Future<void> toggleCollapsedNavigationGroup(String group) async {
    final normalized = group.trim();
    if (normalized.isEmpty) return;
    if (!_collapsedNavigationGroups.add(normalized)) {
      _collapsedNavigationGroups.remove(normalized);
    }
    notifyListeners();
    await _persistCurrent();
  }

  Future<void> setSideNavigationScrollOffset(double offset) async {
    final double next = offset.isFinite && offset > 0 ? offset : 0.0;
    if ((_sideNavigationScrollOffset - next).abs() < 0.5) return;
    _sideNavigationScrollOffset = next;
    await _persistCurrent();
  }

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    super.dispose();
  }

  static SupabaseClient? _resolveClient() {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }
}
