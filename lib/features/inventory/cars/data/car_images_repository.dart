import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:quality_line_erp/core/cloud/cloud_master_data_service.dart';
import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';
import 'package:quality_line_erp/features/inventory/cars/models/car_image_model.dart';

/// Supabase-only repository for vehicle images.
///
/// Image replacement is verified from the authoritative read RPC before the
/// operation is considered successful. Identical image sets are a true no-op,
/// which keeps ordinary car edits independent from the dedicated image
/// permission and avoids unnecessary Base64 rewrites.
class CarImagesRepository {
  final CloudMasterDataService _cloud = CloudMasterDataService.instance;

  SupabaseClient get _client => Supabase.instance.client;

  String get _companyId {
    final value = CloudTenantContext.instance.companyUuid;
    if (value == null || value.isEmpty) {
      throw StateError('لم يتم تحديد شركة سحابية للمستخدم الحالي.');
    }
    return value;
  }

  Future<Map<String, String>> getThumbnails(Iterable<String> carIds) async {
    final ids = carIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return const <String, String>{};
    final raw = await _client.rpc(
      'erp_r44_list_car_thumbnails',
      params: {'p_company_id': _companyId, 'p_car_ids': ids},
    );
    final result = <String, String>{};
    for (final row in (raw as List)) {
      final map = Map<String, dynamic>.from(row as Map);
      final carId = (map['carId'] ?? map['car_id'] ?? '').toString().trim();
      final image = (map['thumbnailBase64'] ?? map['thumbnail_base64'] ?? '')
          .toString();
      if (carId.isNotEmpty && image.isNotEmpty) result[carId] = image;
    }
    return result;
  }

  Future<List<CarImageModel>> getImages(String carId) async {
    final raw = await _client.rpc(
      'erp_r26_list_car_images_for_car',
      params: {'p_company_id': _companyId, 'p_car_id': carId},
    );
    final rows = (raw as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
    final result = rows.map(CarImageModel.fromMap).toList(growable: false);
    result.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      return byOrder != 0 ? byOrder : a.createdAt.compareTo(b.createdAt);
    });
    return result;
  }

  bool _sameImageSet(
    List<CarImageModel> existing,
    List<CarImageModel> incoming,
  ) {
    if (existing.length != incoming.length) return false;
    final byId = <String, CarImageModel>{for (final image in existing) image.id: image};
    for (final image in incoming) {
      final current = byId[image.id];
      if (current == null ||
          current.carId != image.carId ||
          current.sortOrder != image.sortOrder ||
          current.imageBase64.trim() != image.imageBase64.trim() ||
          current.thumbnailBase64.trim() != image.thumbnailBase64.trim()) {
        return false;
      }
    }
    return true;
  }

  Future<void> replaceImages(String carId, List<CarImageModel> images) async {
    final existing = await getImages(carId);
    if (_sameImageSet(existing, images)) return;

    final incomingIds = images.map((e) => e.id).toSet();
    for (final old in existing) {
      if (!incomingIds.contains(old.id)) {
        await _cloud.delete('erp_car_images', old.id);
      }
    }
    for (final image in images) {
      if (image.carId != carId) {
        throw ArgumentError('مرجع صورة السيارة لا يطابق السيارة الحالية.');
      }
      await _cloud.upsert('erp_car_images', image.id, image.toMap());
    }

    final persisted = await getImages(carId);
    final persistedById = <String, CarImageModel>{
      for (final image in persisted) image.id: image,
    };
    if (persistedById.length != images.length) {
      throw StateError(
        'لم يتم تثبيت جميع صور السيارة في Supabase. أعد المحاولة بعد تحديث قاعدة البيانات.',
      );
    }
    for (final expected in images) {
      final actual = persistedById[expected.id];
      if (actual == null ||
          actual.imageBase64.trim() != expected.imageBase64.trim() ||
          actual.thumbnailBase64.trim() != expected.thumbnailBase64.trim() ||
          actual.sortOrder != expected.sortOrder) {
        throw StateError(
          'فشل التحقق من صورة السيارة بعد الحفظ. لم يتم اعتبار العملية ناجحة.',
        );
      }
    }
  }

  Future<void> deleteImagesForCar(String carId) async {
    final rows = await getImages(carId);
    for (final image in rows) {
      await _cloud.delete('erp_car_images', image.id);
    }
  }
}
