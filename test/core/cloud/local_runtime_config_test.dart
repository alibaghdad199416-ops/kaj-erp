import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/cloud/cloud_bootstrap.dart';
import 'package:quality_line_erp/core/cloud/supabase_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'authoritative runtime defines initialize the selected Supabase backend',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      expect(SupabaseConfig.publishableKey, isNotEmpty);
      expect(SupabaseConfig.publishableKey, isNot(contains('service_role')));
      expect(SupabaseConfig.publishableKey, isNot(startsWith('sb_secret_')));
      expect(SupabaseConfig.validate(), isNull);
      expect(SupabaseConfig.isConfigured, isTrue);

      if (SupabaseConfig.url == SupabaseConfig.expectedProductionUrl) {
        expect(
          SupabaseConfig.projectRef,
          SupabaseConfig.expectedProductionProjectRef,
        );
        expect(SupabaseConfig.publishableKey, startsWith('sb_publishable_'));
        expect(SupabaseConfig.isLocalTarget(), isFalse);
        expect(SupabaseConfig.isHostedProductionTarget(), isTrue);
      } else {
        expect(SupabaseConfig.url, 'http://127.0.0.1:54321');
        expect(SupabaseConfig.projectRef, 'quality_line_erp_local_dev');
        expect(SupabaseConfig.isLocalTarget(), isTrue);
        expect(SupabaseConfig.isHostedProductionTarget(), isFalse);
      }

      final result = await CloudBootstrap.initialize(retry: true);
      expect(result.supabaseReady, isTrue);
      expect(Supabase.instance.client, isA<SupabaseClient>());
    },
  );
}
