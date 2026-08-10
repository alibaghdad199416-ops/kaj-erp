import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';

import 'package:quality_line_erp/features/business_partners/suppliers/models/supplier_model.dart';
import 'package:quality_line_erp/features/business_partners/suppliers/repositories/supplier_repository.dart';
import 'package:quality_line_erp/core/events/app_data_change_bus.dart';

class SuppliersController extends ChangeNotifier {
  SuppliersController({SupplierRepository? repository})
    : _repository = repository ?? SupplierRepository();

  final SupplierRepository _repository;

  final List<SupplierModel> _suppliers = [];

  bool _isLoading = false;
  String? _errorMessage;
  String _searchQuery = '';
  bool _hasLoaded = false;

  List<SupplierModel> get suppliers => List.unmodifiable(_suppliers);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get searchQuery => _searchQuery;
  bool get hasLoaded => _hasLoaded;

  int get totalSuppliers => _suppliers.length;

  int get activeSuppliers {
    return _suppliers.where((supplier) => supplier.isActive).length;
  }

  int get inactiveSuppliers {
    return _suppliers.where((supplier) => !supplier.isActive).length;
  }

  double get totalOpeningBalanceUsd {
    return _suppliers
        .where((supplier) => supplier.currency == 'USD')
        .fold<double>(0, (total, supplier) => total + supplier.openingBalance);
  }

  double get totalOpeningBalanceIqd {
    return _suppliers
        .where((supplier) => supplier.currency == 'IQD')
        .fold<double>(0, (total, supplier) => total + supplier.openingBalance);
  }

  Future<void> loadSuppliers() async {
    _setLoading(true);
    _clearError();

    try {
      final suppliers = await _repository.getSuppliers();

      _suppliers
        ..clear()
        ..addAll(suppliers);
      _hasLoaded = true;
    } catch (error, stackTrace) {
      AppLogger.debug('SuppliersController.loadSuppliers error: $error');
      AppLogger.stack(stackTrace);

      _setError('تعذر تحميل بيانات الموردين. حاول مرة أخرى.');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> searchSuppliers(String query) async {
    _searchQuery = query.trim();
    _setLoading(true);
    _clearError();

    try {
      final suppliers = await _repository.searchSuppliers(_searchQuery);

      _suppliers
        ..clear()
        ..addAll(suppliers);
    } catch (error, stackTrace) {
      AppLogger.debug('SuppliersController.searchSuppliers error: $error');
      AppLogger.stack(stackTrace);

      _setError('تعذر البحث في الموردين.');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> clearSearch() async {
    _searchQuery = '';
    await loadSuppliers();
  }

  Future<void> addSupplier(SupplierModel supplier) async {
    _setLoading(true);
    _clearError();

    try {
      final duplicatePhone = await _repository.phoneExists(
        phone: supplier.phone,
      );

      if (duplicatePhone) {
        throw StateError('رقم الهاتف مستخدم بالفعل لمورد آخر.');
      }

      await _repository.addSupplier(supplier);
      AppDataChangeBus.instance.publish('suppliers', operation: 'insert');
      await _reloadAuthoritativeSuppliers();
    } catch (error, stackTrace) {
      AppLogger.debug('SuppliersController.addSupplier error: $error');
      AppLogger.stack(stackTrace);

      _setError(_friendlyMessage(error));
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> updateSupplier(SupplierModel supplier) async {
    _setLoading(true);
    _clearError();

    try {
      final duplicatePhone = await _repository.phoneExists(
        phone: supplier.phone,
        excludeSupplierId: supplier.id,
      );

      if (duplicatePhone) {
        throw StateError('رقم الهاتف مستخدم بالفعل لمورد آخر.');
      }

      await _repository.updateSupplier(supplier);
      AppDataChangeBus.instance.publish('suppliers', operation: 'update');
      await _reloadAuthoritativeSuppliers();
    } catch (error, stackTrace) {
      AppLogger.debug('SuppliersController.updateSupplier error: $error');
      AppLogger.stack(stackTrace);

      _setError(_friendlyMessage(error));
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> deleteSupplier(String id) async {
    _setLoading(true);
    _clearError();

    try {
      await _repository.deleteSupplier(id);
      AppDataChangeBus.instance.publish('suppliers', operation: 'delete');

      _suppliers.removeWhere((supplier) => supplier.id == id);

      notifyListeners();
    } catch (error, stackTrace) {
      AppLogger.debug('SuppliersController.deleteSupplier error: $error');
      AppLogger.stack(stackTrace);

      _setError(_friendlyMessage(error));
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> toggleSupplierStatus(SupplierModel supplier) async {
    _setLoading(true);
    _clearError();

    try {
      final newStatus = !supplier.isActive;

      await _repository.setSupplierActive(id: supplier.id, isActive: newStatus);
      AppDataChangeBus.instance.publish('suppliers', operation: 'status');
      await _reloadAuthoritativeSuppliers();
    } catch (error, stackTrace) {
      AppLogger.debug('SuppliersController.toggleSupplierStatus error: $error');
      AppLogger.stack(stackTrace);

      _setError(_friendlyMessage(error));
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  SupplierModel? getSupplierById(String id) {
    try {
      return _suppliers.firstWhere((supplier) => supplier.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> _reloadAuthoritativeSuppliers() async {
    final suppliers = await _repository.getSuppliers();
    _suppliers
      ..clear()
      ..addAll(suppliers);
    _hasLoaded = true;
    notifyListeners();
  }

  void clearError() {
    _clearError();
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String message) {
    _errorMessage = message;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
  }

  String _friendlyMessage(Object error) {
    AppLogger.debug('Supplier operation failed: $error');
    return userFacingError(
      error,
      isArabic: AppTranslation.isArabic,
      arabicFallback:
          'تعذر حفظ بيانات المورد. تحقق من الاتصال والصلاحيات ثم أعد المحاولة.',
      englishFallback:
          'Unable to save supplier data. Check the connection and permissions, then try again.',
    );
  }
}
