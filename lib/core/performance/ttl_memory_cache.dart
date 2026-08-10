import 'dart:async';

class CacheEntry<T> {
  CacheEntry(this.value, this.expiresAt);
  final T value;
  final DateTime expiresAt;
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class TtlMemoryCache {
  TtlMemoryCache({this.maximumEntries = 250}) : assert(maximumEntries > 0);

  final int maximumEntries;
  final Map<String, CacheEntry<Object?>> _entries = {};
  final Map<String, Future<Object?>> _inflight = {};

  int get length => _entries.length;

  T? get<T>(String key) {
    final entry = _entries[key];
    if (entry == null) return null;
    if (entry.isExpired) {
      _entries.remove(key);
      return null;
    }
    return entry.value as T?;
  }

  void put<T>(
    String key,
    T value, {
    Duration ttl = const Duration(minutes: 5),
  }) {
    _entries.remove(key);
    _entries[key] = CacheEntry<Object?>(value, DateTime.now().add(ttl));
    _trim();
  }

  Future<T> remember<T>(
    String key,
    Future<T> Function() loader, {
    Duration ttl = const Duration(minutes: 5),
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = get<T>(key);
      if (cached != null) return cached;
    }
    final pending = _inflight[key];
    if (pending != null) return await pending as T;
    final future = loader();
    _inflight[key] = future;
    try {
      final value = await future;
      put<T>(key, value, ttl: ttl);
      return value;
    } finally {
      await _inflight.remove(key);
    }
  }

  void invalidate(String key) => _entries.remove(key);

  void invalidatePrefix(String prefix) {
    _entries.removeWhere((key, _) => key.startsWith(prefix));
  }

  void clear() {
    _entries.clear();
    _inflight.clear();
  }

  void _trim() {
    _entries.removeWhere((_, value) => value.isExpired);
    while (_entries.length > maximumEntries) {
      _entries.remove(_entries.keys.first);
    }
  }
}
