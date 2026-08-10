import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:quality_line_erp/core/cloud/cloud_master_data_service.dart';
import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';
import 'package:quality_line_erp/features/inventory/cars/models/car_image_model.dart';

/// Supabase-only repository for vehicle images.
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

  Future<void> replaceImages(String carId, List<CarImageModel> images) async {
    final existing = await getImages(carId);
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
  }

  Future<void> deleteImagesForCar(String carId) async {
    final rows = await getImages(carId);
    for (final image in rows) {
      await _cloud.delete('erp_car_images', image.id);
    }
  }
}
