import 'package:quality_line_erp/core/cloud/cloud_feature_command.dart';
import 'package:quality_line_erp/core/cloud/supabase_config.dart';

class ProductionReadinessCheck {
  const ProductionReadinessCheck({
    required this.code,
    required this.title,
    required this.passed,
    required this.details,
    this.mandatory = true,
  });
  final String code;
  final String title;
  final bool passed;
  final String details;
  final bool mandatory;
}

class ProductionReadinessSnapshot {
  const ProductionReadinessSnapshot({
    required this.generatedAt,
    required this.checks,
  });
  final DateTime generatedAt;
  final List<ProductionReadinessCheck> checks;
  int get mandatoryFailures =>
      checks.where((c) => c.mandatory && !c.passed).length;
  bool get readyForProduction => mandatoryFailures == 0;
}

class ProductionReadinessService {
  const ProductionReadinessService();

  Future<ProductionReadinessSnapshot> evaluate() async {
    final checks = <ProductionReadinessCheck>[
      ProductionReadinessCheck(
        code: 'SUPABASE_CONFIG',
        title: 'إعداد Supabase',
        passed: SupabaseConfig.validate() == null,
        details: SupabaseConfig.validate() ?? 'الإعداد صالح.',
      ),
    ];
    try {
      final contract = await CloudFeatureCommand.instance
          .runtimeContractProbe();
      final required = <String>[
        'r15MasterList',
        'r15MasterGet',
        'r15MasterUpsert',
        'r15MasterDelete',
        'r22Phase26',
        'r22SalesApprove',
        'r22PurchaseApprove',
        'r22DirectPurchase',
        'r22HistoricalPurchaseRebuild',
        'r22CashTransfer',
        'r22CashReconciliation',
        'r22StateReconcile',
        'masterContractsOk',
        'persistentDeletionRegistry',
        'identitySafeCashReconciliation',
      ];
      final missing = required.where((key) => contract[key] != true).toList();
      checks.add(
        ProductionReadinessCheck(
          code: 'RUNTIME_RPC_CONTRACT',
          title: 'عقد RPC للإنتاج',
          passed: contract['ok'] == true && missing.isEmpty,
          details: missing.isEmpty
              ? 'جميع عقود R22 المطلوبة متاحة: اعتماد الفواتير المباشر، تحويل الصناديق المعرّف الهوية، وسجل الحذف الدائم فعال.'
              : 'عقود/بنى R22 غير متاحة: ${missing.join(', ')}; masterIssues=${contract['masterContractIssues']}',
        ),
      );
      final currentState = contract['currentStateHealth'];
      final stateMap = currentState is Map
          ? Map<String, dynamic>.from(currentState)
          : <String, dynamic>{};
      checks.add(
        ProductionReadinessCheck(
          code: 'CANONICAL_DATA_STATE',
          title: 'الحالة المرجعية للبيانات',
          passed: stateMap['ok'] == true,
          details: stateMap['ok'] == true
              ? 'الحالة المرجعية R22 سليمة: الحذف الدائم محفوظ، ولا بيانات Legacy فعالة، وتحويلات الصناديق مرتبطة بالأستاذ بهوية مؤكدة.'
              : 'تحتاج البيانات إلى reconciliation: $stateMap',
        ),
      );
      await CloudFeatureCommand.instance.call('system_monitor', 'health_check');
      checks.add(
        const ProductionReadinessCheck(
          code: 'CLOUD_HEALTH',
          title: 'اتصال PostgreSQL السحابي',
          passed: true,
          details: 'تم تنفيذ فحص الصحة السحابي بنجاح.',
        ),
      );
    } catch (error) {
      checks.add(
        ProductionReadinessCheck(
          code: 'CLOUD_HEALTH',
          title: 'اتصال PostgreSQL السحابي',
          passed: false,
          details: error.toString(),
        ),
      );
    }
    return ProductionReadinessSnapshot(
      generatedAt: DateTime.now(),
      checks: List.unmodifiable(checks),
    );
  }
}
