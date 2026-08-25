import 'package:flutter/foundation.dart';

enum ErpModuleStatus { core, stable, preview, planned }

@immutable
class ErpModule {
  const ErpModule({
    required this.code,
    required this.nameAr,
    required this.nameEn,
    required this.route,
    required this.status,
    this.descriptionAr = '',
    this.dependencies = const <String>[],
    this.permissions = const <String>[],
    this.capabilities = const <String>[],
    this.isCore = false,
  });

  final String code;
  final String nameAr;
  final String nameEn;
  final String route;
  final ErpModuleStatus status;
  final String descriptionAr;
  final List<String> dependencies;
  final List<String> permissions;
  final List<String> capabilities;
  final bool isCore;

  bool get isAvailable => status != ErpModuleStatus.planned;

  Map<String, Object?> toMap() => <String, Object?>{
    'code': code,
    'nameAr': nameAr,
    'nameEn': nameEn,
    'route': route,
    'status': status.name,
    'descriptionAr': descriptionAr,
    'dependencies': List<String>.unmodifiable(dependencies),
    'permissions': List<String>.unmodifiable(permissions),
    'capabilities': List<String>.unmodifiable(capabilities),
    'isCore': isCore,
  };
}

@immutable
class ModuleValidationResult {
  const ModuleValidationResult({
    required this.isValid,
    this.missingDependencies = const <String>[],
    this.circularDependencies = const <String>[],
    this.duplicateCodes = const <String>[],
  });

  final bool isValid;
  final List<String> missingDependencies;
  final List<String> circularDependencies;
  final List<String> duplicateCodes;
}
