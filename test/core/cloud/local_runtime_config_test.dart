import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/cloud/cloud_bootstrap.dart';
import 'package:quality_line_erp/core/cloud/supabase_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('authoritative production runtime defines initialize Supabase', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    expect(SupabaseConfig.url, SupabaseConfig.expectedProductionUrl);
    expect(
      SupabaseConfig.projectRef,
      SupabaseConfig.expectedProductionProjectRef,
    );
    expect(SupabaseConfig.publishableKey, startsWith('sb_publishable_'));
    expect(SupabaseConfig.publishableKey, isNot(contains('service_role')));
    expect(SupabaseConfig.publishableKey, isNot(startsWith('sb_secret_')));
    expect(SupabaseConfig.allowLocalDev, isFalse);
    expect(SupabaseConfig.validate(), isNull);
    expect(SupabaseConfig.isConfigured, isTrue);
    expect(SupabaseConfig.isLocalTarget(), isFalse);
    expect(SupabaseConfig.isHostedProductionTarget(), isTrue);

    final result = await CloudBootstrap.initialize(retry: true);
    expect(result.supabaseReady, isTrue);
    expect(Supabase.instance.client, isA<SupabaseClient>());
  });
}
