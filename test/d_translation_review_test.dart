import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';

void main() {
  group('Stage D translation review', () {
    tearDown(() => AppTranslation.localeCode = 'ar');

    test('canonical language labels follow the selected locale', () {
      AppTranslation.localeCode = 'en';
      expect(AppTranslation.translate('العربية'), 'Arabic');
      expect(AppTranslation.translate('الإنجليزية'), 'English');

      AppTranslation.localeCode = 'ar';
      expect(AppTranslation.translate('Arabic'), 'العربية');
      expect(AppTranslation.translate('English'), 'الإنجليزية');
    });

    test('canonical accounting and business terms are bilingual', () {
      AppTranslation.localeCode = 'en';
      expect(AppTranslation.translate('الموردون'), 'Suppliers');
      expect(AppTranslation.translate('المصروفات'), 'Expenses');
      expect(AppTranslation.translate('حقوق الملكية'), 'Equity');

      AppTranslation.localeCode = 'ar';
      expect(AppTranslation.translate('Suppliers'), 'الموردون');
      expect(AppTranslation.translate('Expenses'), 'المصروفات');
      expect(AppTranslation.translate('Equity'), 'حقوق الملكية');
    });

    test('dynamic messages do not keep the opposite language', () {
      AppTranslation.localeCode = 'en';
      final english = AppTranslation.translate('تم حفظ المورد بنجاح');
      expect(english, isNot(contains('المورد')));

      AppTranslation.localeCode = 'ar';
      final arabic = AppTranslation.translate('Supplier saved successfully');
      expect(arabic, isNot(contains('Supplier')));
    });
  });
}
