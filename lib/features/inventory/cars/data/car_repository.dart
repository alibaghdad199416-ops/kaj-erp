import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:quality_line_erp/core/cloud/cloud_master_data_service.dart';
import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';
import 'package:quality_line_erp/core/data/query_page.dart';
import 'package:quality_line_erp/features/inventory/cars/domain/car_lifecycle_guard.dart';
import 'package:quality_line_erp/features/inventory/cars/models/car_model.dart';

/// Supabase-only repository for vehicle master data.
///
/// PostgreSQL (`erp_cars`) is the sole source of truth and failures are surfaced
/// to the caller instead of being hidden behind a secondary data store.
class CarRepository {
  final CloudMasterDataService _cloud = CloudMasterDataService.instance;

  Future<void> insertCar(CarModel car) async {
    AppLogger.debug('CarRepository.insertCar() [Supabase only]');
    car.validate();
    await _cloud.upsert('erp_cars', car.id, car.toCloudMap());
  }

  Future<bool> carExists(String id) async =>
      await _cloud.getById('erp_cars', id) != null;

  Future<void> updateCar(CarModel car) async {
    AppLogger.debug('CarRepository.updateCar() [Supabase only]');
    car.validate();
    final existing = await _cloud.getById('erp_cars', car.id);
    if (existing == null) throw StateError('السيارة غير موجودة.');
    await _cloud.upsert('erp_cars', car.id, car.toCloudMap());
  }

  Future<void> updateCarStatus(String id, String status) async {
    AppLogger.debug('CarRepository.updateCarStatus() [Supabase only]');
    CarLifecycleGuard.validateStatus(status);

    final row = await _cloud.getById('erp_cars', id);
    if (row == null) throw StateError('السيارة غير موجودة.');

    final current = CarModel.fromCloudMap(row);
    CarLifecycleGuard.ensureTransition(current.status, status);
    final updated = current.copyWith(status: status);
    await _cloud.upsert('erp_cars', id, updated.toCloudMap());
  }

  Future<void> deleteCar(String id) async {
    AppLogger.debug('CarRepository.deleteCar() [Supabase only]');
    final existing = await _cloud.getById('erp_cars', id);
    if (existing == null) throw StateError('السيارة غير موجودة.');

    if (await _cloud.hasActiveLegacyReference(
      entityType: 'sales',
      field: 'carId',
      value: id,
    )) {
      throw StateError(
        'لا يمكن حذف سيارة مرتبطة بعملية بيع. ألغِ المستند المرتبط أولاً.',
      );
    }
    if (await _cloud.hasActiveLegacyReference(
      entityType: 'purchase_items',
      field: 'carId',
      value: id,
    )) {
      throw StateError(
        'لا يمكن حذف سيارة مرتبطة بعملية شراء. ألغِ المستند المرتبط أولاً.',
      );
    }
    if (await _cloud.hasActiveLegacyReference(
      entityType: 'sales_order_items',
      field: 'itemId',
      value: id,
      equals: const {'itemType': 'car'},
    )) {
      throw StateError(
        'لا يمكن حذف سيارة مرتبطة بأمر بيع. ألغِ أمر البيع أولاً.',
      );
    }
    if (await _cloud.hasActiveLegacyReference(
      entityType: 'purchase_order_items_v2',
      field: 'itemId',
      value: id,
      equals: const {'itemType': 'car'},
    )) {
      throw StateError(
        'لا يمكن حذف سيارة مرتبطة بأمر شراء. ألغِ أمر الشراء أولاً.',
      );
    }

    // Tombstone cloud child records first so no device can later restore an
    // orphaned image after receiving the vehicle tombstone.
    final imageIds = await _cloud.activeLegacyReferenceIds(
      entityType: 'car_images',
      field: 'carId',
      value: id,
    );
    for (final imageId in imageIds) {
      await _softDeleteLegacyRecord('car_images', imageId);
    }
    await _cloud.delete('erp_cars', id);
  }

  Future<void> _softDeleteLegacyRecord(String entityType, String id) async {
    // Compatibility children still live in erp_records during the staged
    // migration. The retired synchronization service is not used here because it
    // carries the retired local synchronization lifecycle.
    await _cloud.deleteLegacyRecord(entityType: entityType, recordId: id);
  }

  Future<List<CarModel>> getCars({QueryPage page = const QueryPage()}) async {
    AppLogger.debug('CarRepository.getCars() [canonical warehouse RPC]');
    final companyId = CloudTenantContext.instance.companyUuid;
    if (companyId == null || companyId.isEmpty) {
      throw StateError('لم يتم تحديد الشركة الحالية.');
    }
    final result = await Supabase.instance.client
        .rpc(
          'erp_r49_list_cloud_cars_with_warehouse',
          params: {'p_company_id': companyId},
        )
        .timeout(const Duration(seconds: 30));
    final cars = (result as List)
        .map(
          (row) => CarModel.fromCloudMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);
    return cars.skip(page.offset).take(page.limit).toList(growable: false);
  }
}
