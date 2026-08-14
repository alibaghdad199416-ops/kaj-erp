import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/cloud/cloud_bootstrap.dart';
import 'package:quality_line_erp/core/cloud/supabase_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'authoritative local runtime define file initializes Supabase',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      if (SupabaseConfig.localProjectId.isEmpty) {
        expect(SupabaseConfig.isLocalTarget(), isFalse);
        return;
      }
      expect(SupabaseConfig.url, 'http://127.0.0.1:54321');
      expect(SupabaseConfig.localProjectId, 'quality_line_erp_local_dev');
      expect(SupabaseConfig.publishableKey, isNotEmpty);
      expect(SupabaseConfig.publishableKey, isNot(contains('service_role')));
      expect(SupabaseConfig.publishableKey, isNot(startsWith('sb_secret_')));
      expect(SupabaseConfig.allowLocalDev, isTrue);
      expect(SupabaseConfig.validate(), isNull);
      expect(SupabaseConfig.isConfigured, isTrue);
      expect(SupabaseConfig.isLocalTarget(), isTrue);

      final result = await CloudBootstrap.initialize(retry: true);
      expect(result.supabaseReady, isTrue);
      expect(Supabase.instance.client, isA<SupabaseClient>());
    },
  );
}
