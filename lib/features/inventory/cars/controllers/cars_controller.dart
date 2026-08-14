import 'dart:async';

import 'package:flutter/material.dart';

import 'package:quality_line_erp/features/inventory/cars/data/car_repository.dart';
import 'package:quality_line_erp/features/inventory/cars/models/car_model.dart';
import 'package:quality_line_erp/core/events/app_data_change_bus.dart';

class CarsController extends ChangeNotifier {
  CarsController({CarRepository? repository})
    : _repository = repository ?? CarRepository();

  final CarRepository _repository;

  List<CarModel> _cars = [];
  bool _isLoading = false;
  bool _reloadRequested = false;
  Future<void>? _loadInFlight;
  DateTime? _loadedAt;
  bool _disposed = false;
  bool _hasLoaded = false;

  List<CarModel> get cars => List.unmodifiable(_cars);
  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;

  static const Duration _loadTtl = Duration(seconds: 20);

  Future<void> loadCars({bool force = false}) {
    final loadedAt = _loadedAt;
    if (!force &&
        loadedAt != null &&
        DateTime.now().difference(loadedAt) < _loadTtl) {
      return Future<void>.value();
    }
    final active = _loadInFlight;
    if (active != null) {
      if (force) _reloadRequested = true;
      return active;
    }

    final request = _loadCarsNow();
    _loadInFlight = request;
    return request.whenComplete(() {
      if (identical(_loadInFlight, request)) _loadInFlight = null;
    });
  }

  Future<void> _loadCarsNow() async {
    _isLoading = true;
    try {
      do {
        _reloadRequested = false;
        _cars = await _repository.getCars();
        _hasLoaded = true;
        _loadedAt = DateTime.now();

        if (!_disposed) {
          notifyListeners();
        }
      } while (_reloadRequested && !_disposed);
    } finally {
      _isLoading = false;
    }
  }

  Future<void> addCar(CarModel car) async {
    try {
      await _repository.insertCar(car);
      AppDataChangeBus.instance.publish(
        'cars',
        operation: 'insert',
        entityId: car.id,
      );
    } catch (error, stackTrace) {
      var committed = false;
      try {
        committed = await _repository.carExists(car.id);
      } catch (_) {
        committed = false;
      }
      if (!committed) Error.throwWithStackTrace(error, stackTrace);
      AppDataChangeBus.instance.publish(
        'cars',
        operation: 'insert-reconciled',
        entityId: car.id,
      );
    } finally {
      await loadCars(force: true);
    }
  }

  Future<void> updateCar(CarModel car) async {
    try {
      await _repository.updateCar(car);
      AppDataChangeBus.instance.publish(
        'cars',
        operation: 'update',
        entityId: car.id,
      );
    } finally {
      await loadCars(force: true);
    }
  }

  Future<void> removeCar(String id) async {
    await _repository.deleteCar(id);
    AppDataChangeBus.instance.publish('cars', operation: 'delete');
    await loadCars(force: true);
  }

  CarModel? getCarById(String id) {
    try {
      return _cars.firstWhere((car) => car.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> changeCarStatus(String id, String status) async {
    await _repository.updateCarStatus(id, status);
    AppDataChangeBus.instance.publish('cars', operation: 'status');
    await loadCars(force: true);
  }

  int get totalCars => _cars.length;

  int get availableCars => _cars.where((car) => car.status == 'متوفرة').length;

  int get soldCars => _cars.where((car) => car.status == 'مباعة').length;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
