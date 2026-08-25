class TtlCache<K, V> {
  TtlCache({required this.ttl});

  final Duration ttl;
  final Map<K, _CacheEntry<V>> _entries = <K, _CacheEntry<V>>{};

  V? get(K key) {
    final entry = _entries[key];
    if (entry == null) return null;
    if (DateTime.now().isAfter(entry.expiresAt)) {
      _entries.remove(key);
      return null;
    }
    return entry.value;
  }

  void put(K key, V value) {
    _entries[key] = _CacheEntry<V>(value, DateTime.now().add(ttl));
  }

  void invalidate([K? key]) {
    if (key == null) {
      _entries.clear();
    } else {
      _entries.remove(key);
    }
  }
}

class _CacheEntry<V> {
  const _CacheEntry(this.value, this.expiresAt);
  final V value;
  final DateTime expiresAt;
}
