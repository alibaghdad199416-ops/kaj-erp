import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';

void main() {
  tearDown(() => AppTranslation.localeCode = 'ar');

  test('canonical business terms translate consistently to English', () {
    AppTranslation.localeCode = 'en';

    expect(AppTranslation.translate('العميل'), 'customer');
    expect(AppTranslation.translate('المورد'), 'Supplier');
    expect(AppTranslation.translate('المصروفات'), 'Expenses');
    expect(AppTranslation.translate('الأصول'), 'Assets');
    expect(AppTranslation.translate('الخصوم'), 'Liabilities');
    expect(AppTranslation.translate('حقوق الملكية'), 'Equity');
    expect(AppTranslation.translate('الإيرادات'), 'Revenue');
  });

  test('legacy English labels translate back to canonical Arabic', () {
    AppTranslation.localeCode = 'ar';

    expect(AppTranslation.translate('Customer'), 'عميل');
    expect(AppTranslation.translate('Supplier'), 'مورد');
    expect(AppTranslation.translate('Expenses'), 'المصروفات');
    expect(AppTranslation.translate('Assets'), 'الأصول');
    expect(AppTranslation.translate('Liabilities'), 'الخصوم');
    expect(AppTranslation.translate('Equity'), 'حقوق الملكية');
    expect(AppTranslation.translate('Revenue'), 'الإيرادات');
  });

  test(
    'dynamic messages do not leave canonical terms in the wrong language',
    () {
      AppTranslation.localeCode = 'en';
      final english = AppTranslation.translate(
        'تم حفظ العميل في حساب الأصول بنجاح.',
      );
      expect(english, isNot(contains('العميل')));
      expect(english, isNot(contains('الأصول')));

      AppTranslation.localeCode = 'ar';
      final arabic = AppTranslation.translate(
        'Customer was linked to Assets successfully.',
      );
      expect(arabic, isNot(contains('Customer')));
      expect(arabic, isNot(contains('Assets')));
    },
  );
}
