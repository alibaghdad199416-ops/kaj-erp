import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/cloud/supabase_config.dart';

void main() {
  group('SupabaseConfig local-only runtime', () {
    test('accepts explicit loopback targets with a public local key', () {
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
    });

    test('rejects every hosted Supabase target even with a publishable key', () {
      for (final url in <String>[
        'https://example.supabase.co',
        'https://havlqebmnjdcwmpaaqew.supabase.co',
      ]) {
        expect(
          SupabaseConfig.validateConfiguration(
            projectUrl: url,
            publishableKey: 'sb_publishable_example',
            allowLocalDev: true,
          ),
          contains('Local Supabase'),
        );
      }
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
          contains('Local Supabase'),
        );
      }
    });

    test('rejects loopback when local development is disabled', () {
      expect(
        SupabaseConfig.validateConfiguration(
          projectUrl: 'http://127.0.0.1:54321',
          publishableKey: 'sb_publishable_local_example',
          allowLocalDev: false,
        ),
        contains('Local Supabase'),
      );
    });

    test('rejects REST paths on local targets', () {
      expect(
        SupabaseConfig.validateConfiguration(
          projectUrl: 'http://localhost:54321/rest/v1',
          publishableKey: 'sb_publishable_local_example',
          allowLocalDev: true,
        ),
        contains('/rest/v1'),
      );
    });

    test('requires a local browser key and rejects secrets', () {
      expect(
        SupabaseConfig.validateConfiguration(
          projectUrl: 'http://localhost:54321',
          publishableKey: '',
          allowLocalDev: true,
        ),
        contains('supabase status'),
      );
      for (final key in <String>['service_role_example', 'sb_secret_example']) {
        expect(
          SupabaseConfig.validateConfiguration(
            projectUrl: 'http://localhost:54321',
            publishableKey: key,
            allowLocalDev: true,
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

    test('presentation never labels a rejected target as production', () {
      expect(
        SupabaseConfig.environmentLabel(
          isArabic: false,
          projectUrl: 'https://example.supabase.co',
          publishableKey: 'sb_publishable_example',
          allowLocalDevelopment: true,
        ),
        'Local Supabase Required',
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
