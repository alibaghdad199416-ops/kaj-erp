import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:quality_line_erp/features/inventory/cars/data/car_images_repository.dart';
import 'package:quality_line_erp/features/inventory/cars/models/car_image_model.dart';

class CarImagesController extends ChangeNotifier {
  final CarImagesRepository _repository = CarImagesRepository();
  final Map<String, List<CarImageModel>> _cache = {};
  final Set<String> _loading = {};
  final Map<String, Uint8List?> _thumbnailBytes = {};

  List<CarImageModel> imagesFor(String carId) =>
      List.unmodifiable(_cache[carId] ?? const <CarImageModel>[]);

  bool isLoading(String carId) => _loading.contains(carId);

  Uint8List? thumbnailBytesFor(String carId) => _thumbnailBytes[carId];

  bool _notificationQueued = false;

  void _notifySafely() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      if (_notificationQueued) return;
      _notificationQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _notificationQueued = false;
        notifyListeners();
      });
      return;
    }
    notifyListeners();
  }

  void _refreshThumbnail(String carId) {
    final images = _cache[carId];
    if (images == null || images.isEmpty) {
      _thumbnailBytes[carId] = null;
      return;
    }
    try {
      final encoded = images.first.thumbnailBase64.trim();
      _thumbnailBytes[carId] = encoded.isEmpty ? null : base64Decode(encoded);
    } catch (_) {
      _thumbnailBytes[carId] = null;
    }
  }

  Future<void> loadThumbnails(
    Iterable<String> carIds, {
    bool force = false,
  }) async {
    final requested = carIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (!force) requested.removeWhere(_thumbnailBytes.containsKey);
    if (requested.isEmpty) return;
    final values = await _repository.getThumbnails(requested);
    for (final carId in requested) {
      final encoded = values[carId];
      if (encoded == null || encoded.isEmpty) {
        _thumbnailBytes[carId] = null;
        continue;
      }
      try {
        _thumbnailBytes[carId] = base64Decode(encoded);
      } catch (_) {
        _thumbnailBytes[carId] = null;
      }
    }
    _notifySafely();
  }

  Future<void> loadImages(String carId, {bool force = false}) async {
    if (!force && _cache.containsKey(carId)) return;
    if (_loading.contains(carId)) return;
    _loading.add(carId);
    _notifySafely();
    try {
      _cache[carId] = await _repository.getImages(carId);
      _refreshThumbnail(carId);
    } finally {
      _loading.remove(carId);
      _notifySafely();
    }
  }

  Future<void> replaceImages(String carId, List<CarImageModel> images) async {
    await _repository.replaceImages(carId, images);
    _cache[carId] = images;
    _refreshThumbnail(carId);
    _notifySafely();
  }

  Future<void> clearForCar(String carId) async {
    await _repository.deleteImagesForCar(carId);
    _cache.remove(carId);
    _thumbnailBytes.remove(carId);
    _notifySafely();
  }

  /// Invalidates all image snapshots after a Supabase Realtime change.
  /// The next visible card reloads only the car it needs.
  void invalidateAll() {
    if (_cache.isEmpty && _thumbnailBytes.isEmpty) return;
    _cache.clear();
    _thumbnailBytes.clear();
    _notifySafely();
  }
}
