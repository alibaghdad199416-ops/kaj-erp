import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

/// Small in-memory LRU cache for base64 thumbnails used by list cards.
/// It avoids repeatedly decoding the same image during widget rebuilds.
class Base64ImageCache {
  Base64ImageCache._();

  static final Base64ImageCache instance = Base64ImageCache._();

  static const int _maximumEntries = 96;
  final LinkedHashMap<String, Uint8List> _cache =
      LinkedHashMap<String, Uint8List>();

  Uint8List? decode(String? value) {
    if (value == null || value.isEmpty) return null;

    final cached = _cache.remove(value);
    if (cached != null) {
      _cache[value] = cached;
      return cached;
    }

    try {
      final bytes = base64Decode(value);
      _cache[value] = bytes;
      while (_cache.length > _maximumEntries) {
        _cache.remove(_cache.keys.first);
      }
      return bytes;
    } on FormatException {
      return null;
    }
  }

  void clear() => _cache.clear();
}
