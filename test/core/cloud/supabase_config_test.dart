import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/cloud/supabase_config.dart';

void main() {
  group('SupabaseConfig hosted production and local development runtime', () {
    test('accepts only the intended hosted production project', () {
      expect(
        SupabaseConfig.validateConfiguration(
          projectUrl: SupabaseConfig.expectedProductionUrl,
          publishableKey: 'sb_publishable_example',
          allowLocalDev: false,
        ),
        isNull,
      );
      expect(
        SupabaseConfig.isHostedProductionTarget(
          projectUrl: SupabaseConfig.expectedProductionUrl,
          publishableKey: 'sb_publishable_example',
        ),
        isTrue,
      );
      expect(
        SupabaseConfig.projectRefFor(
          projectUrl: SupabaseConfig.expectedProductionUrl,
        ),
        SupabaseConfig.expectedProductionProjectRef,
      );
    });

    test('rejects arbitrary hosted Supabase projects', () {
      expect(
        SupabaseConfig.validateConfiguration(
          projectUrl: 'https://example.supabase.co',
          publishableKey: 'sb_publishable_example',
          allowLocalDev: false,
        ),
        contains('KAJ ERP'),
      );
    });

    test('accepts explicit loopback targets only when local dev is enabled', () {
      for (final url in <String>[
        'http://127.0.0.1:54321',
        'http://localhost:54321',
        'http://[::1]:54321',
      ]) {
        expect(
          SupabaseConfig.validateConfiguration(
            projectUrl: url,
            publishableKey: 'sb_publishable_local_example',
            allowLocalDev: true,
          ),
          isNull,
        );
      }
      expect(
        SupabaseConfig.validateConfiguration(
          projectUrl: 'http://127.0.0.1:54321',
          publishableKey: 'sb_publishable_local_example',
          allowLocalDev: false,
        ),
        contains('Local Supabase'),
      );
    });

    test('rejects LAN and arbitrary HTTP targets', () {
      for (final url in <String>[
        'http://192.168.1.20:54321',
        'http://example.com:54321',
      ]) {
        expect(
          SupabaseConfig.validateConfiguration(
            projectUrl: url,
            publishableKey: 'sb_publishable_local_example',
            allowLocalDev: true,
          ),
          isNotNull,
        );
      }
    });

    test('rejects REST endpoint URLs', () {
      for (final url in <String>[
        '${SupabaseConfig.expectedProductionUrl}/rest/v1/',
        'http://localhost:54321/rest/v1',
      ]) {
        expect(
          SupabaseConfig.validateConfiguration(
            projectUrl: url,
            publishableKey: 'sb_publishable_example',
            allowLocalDev: true,
          ),
          contains('/rest/v1'),
        );
      }
    });

    test('requires a public browser key and rejects secrets', () {
      expect(
        SupabaseConfig.validateConfiguration(
          projectUrl: SupabaseConfig.expectedProductionUrl,
          publishableKey: '',
          allowLocalDev: false,
        ),
        contains('غير مضبوط'),
      );
      for (final key in <String>['service_role_example', 'sb_secret_example']) {
        expect(
          SupabaseConfig.validateConfiguration(
            projectUrl: SupabaseConfig.expectedProductionUrl,
            publishableKey: key,
            allowLocalDev: false,
          ),
          contains('مفتاحاً سرياً'),
        );
      }
    });

    test('local project id remains an explicit browser namespace opt-in', () {
      expect(
        SupabaseConfig.resolveLocalDevelopmentOptIn(
          explicitAllowLocalDev: false,
          localProjectId: 'quality_line_erp_local_dev',
        ),
        isTrue,
      );
      expect(
        SupabaseConfig.projectRefFor(
          projectUrl: 'http://127.0.0.1:54321',
          localProjectId: 'quality_line_erp_local_dev',
        ),
        'quality_line_erp_local_dev',
      );
    });

    test('presentation labels production and local targets explicitly', () {
      expect(
        SupabaseConfig.environmentLabel(
          isArabic: false,
          projectUrl: SupabaseConfig.expectedProductionUrl,
          publishableKey: 'sb_publishable_example',
          allowLocalDevelopment: false,
        ),
        'Production Supabase',
      );
      expect(
        SupabaseConfig.environmentLabel(
          isArabic: true,
          projectUrl: 'http://localhost:54321',
          publishableKey: 'sb_publishable_local_example',
          allowLocalDevelopment: true,
        ),
        'بيئة تطوير Supabase المحلية',
      );
    });
  });
}
