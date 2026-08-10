import 'dart:async';

import 'package:flutter/material.dart';

import 'package:quality_line_erp/features/inventory/cars/data/car_repository.dart';
import 'package:quality_line_erp/features/inventory/cars/models/car_model.dart';
import 'package:quality_line_erp/core/events/app_data_change_bus.dart';

class CarsController extends ChangeNotifier {
  CarsController();

  final CarRepository _repository = CarRepository();

  List<CarModel> _cars = [];
  bool _isLoading = false;
  bool _reloadRequested = false;
  bool _disposed = false;
  bool _hasLoaded = false;

  List<CarModel> get cars => List.unmodifiable(_cars);
  bool get hasLoaded => _hasLoaded;

  Future<void> loadCars() async {
    if (_isLoading) {
      _reloadRequested = true;
      return;
    }

    _isLoading = true;
    try {
      do {
        _reloadRequested = false;
        _cars = await _repository.getCars();
        _hasLoaded = true;

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
    } finally {
      await loadCars();
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
      await loadCars();
    }
  }

  Future<void> removeCar(String id) async {
    await _repository.deleteCar(id);
    AppDataChangeBus.instance.publish('cars', operation: 'delete');
    await loadCars();
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
    await loadCars();
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
