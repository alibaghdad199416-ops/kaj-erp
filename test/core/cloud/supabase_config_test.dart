import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/cloud/supabase_config.dart';

void main() {
  group('SupabaseConfig.validate', () {
    test('accepts a project URL with a publishable key', () {
      expect(
        SupabaseConfig.validate(
          projectUrl: 'https://example.supabase.co',
          publishableKey: 'sb_publishable_example',
          allowLocalDevelopment: false,
        ),
        isNull,
      );
    });

    test('rejects REST endpoint URLs', () {
      expect(
        SupabaseConfig.validate(
          projectUrl: 'https://example.supabase.co/rest/v1/',
          publishableKey: 'sb_publishable_example',
        ),
        contains('/rest/v1'),
      );
    });

    test('rejects secret keys in a web build', () {
      expect(
        SupabaseConfig.validate(
          projectUrl: 'https://example.supabase.co',
          publishableKey: 'sb_secret_example',
        ),
        contains('مفتاحاً سرياً'),
      );
    });
  });

  test('accepts explicit loopback IPv4 and localhost development targets', () {
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

  test('rejects loopback HTTP unless local development is explicit', () {
    expect(
      SupabaseConfig.validateConfiguration(
        projectUrl: 'http://127.0.0.1:54321',
        publishableKey: 'sb_publishable_local_example',
        allowLocalDev: false,
      ),
      isNotNull,
    );
  });

  test('local project id is an explicit loopback development opt-in', () {
    expect(
      SupabaseConfig.resolveLocalDevelopmentOptIn(
        explicitAllowLocalDev: false,
        localProjectId: 'quality_line_erp_local_dev',
      ),
      isTrue,
    );
    expect(
      SupabaseConfig.resolveLocalDevelopmentOptIn(
        explicitAllowLocalDev: false,
        localProjectId: '  ',
      ),
      isFalse,
    );
  });

  test('local mode never permits LAN or arbitrary HTTP targets', () {
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

  test('production mode rejects non-Supabase HTTPS hosts', () {
    expect(
      SupabaseConfig.validateConfiguration(
        projectUrl: 'https://example.com',
        publishableKey: 'sb_publishable_example',
        allowLocalDev: false,
      ),
      isNotNull,
    );
  });

  test('rejects REST paths in local and hosted modes', () {
    for (final entry in <(String, bool)>[
      ('https://example.supabase.co/rest/v1', false),
      ('http://localhost:54321/rest/v1', true),
    ]) {
      expect(
        SupabaseConfig.validateConfiguration(
          projectUrl: entry.$1,
          publishableKey: 'sb_publishable_example',
          allowLocalDev: entry.$2,
        ),
        contains('/rest/v1'),
      );
    }
  });

  test('rejects service-role and secret keys in every mode', () {
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

  test('validated local target has explicit non-production presentation', () {
    expect(
      SupabaseConfig.environmentLabel(
        isArabic: false,
        projectUrl: 'http://127.0.0.1:54321',
        publishableKey: 'sb_publishable_local_example',
        allowLocalDevelopment: true,
      ),
      'Local Supabase Development Environment',
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
}
