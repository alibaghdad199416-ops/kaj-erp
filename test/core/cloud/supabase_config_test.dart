import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/cloud/supabase_config.dart';

void main() {
  group('SupabaseConfig.validate', () {
    test('accepts a project URL with a publishable key', () {
      expect(
        SupabaseConfig.validate(
          projectUrl: 'https://example.supabase.co',
          publishableKey: 'sb_publishable_example',
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
}
