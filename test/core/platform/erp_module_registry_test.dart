import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/platform/erp_module_registry.dart';

void main() {
  const accepted = <String>{
    'dashboard',
    'global_search',
    'notifications',
    'inventory',
    'maintenance',
    'business_partners',
    'customer_service',
    'sales',
    'purchases',
    'accounting',
    'settings',
  };

  group('ErpModuleRegistry', () {
    test('contains exactly the eleven accepted modules', () {
      expect(
        ErpModuleRegistry.modules.map((module) => module.code).toSet(),
        accepted,
      );
      expect(ErpModuleRegistry.modules, hasLength(11));
    });

    test('registry is internally valid', () {
      final result = ErpModuleRegistry.validate();
      expect(result.isValid, isTrue);
      expect(result.duplicateCodes, isEmpty);
      expect(result.missingDependencies, isEmpty);
      expect(result.circularDependencies, isEmpty);
    });

    test('sales dependency resolution stays inside accepted modules', () {
      final codes = ErpModuleRegistry.resolveDependencies(<String>[
        'sales',
      ]).map((module) => module.code).toSet();
      expect(
        codes,
        containsAll(<String>[
          'inventory',
          'business_partners',
          'accounting',
          'sales',
        ]),
      );
      expect(codes.difference(accepted), isEmpty);
    });
  });
}
