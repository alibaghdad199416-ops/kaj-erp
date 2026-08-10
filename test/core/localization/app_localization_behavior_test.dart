import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';

void main() {
  test('core ERP terminology is translated in both directions', () {
    AppTranslation.localeCode = 'en';
    expect(AppTranslation.translate('قيد البيع'), 'Sale pending');
    expect(
      AppTranslation.translate('تسديد كامل مع تسوية فرق الصرف'),
      'Full settlement with FX adjustment',
    );

    AppTranslation.localeCode = 'ar';
    expect(AppTranslation.translate('Sale pending'), 'قيد البيع');
    expect(
      AppTranslation.translate('Full settlement with FX adjustment'),
      'تسديد كامل مع تسوية فرق الصرف',
    );
  });

  test('dynamic operational messages never mix Arabic into English UI', () {
    AppTranslation.localeCode = 'en';
    final samples = <String>[
      'يرجى إدخال الاسم الكامل',
      'اسم المخزن مطلوب',
      'فشل حفظ السيارة: network_error',
      'تعذر حفظ المنتج: network_error',
      'هل تريد حذف القيد JV-100؟',
      'الحساب 1',
      'إجمالي المدين: 1,250.00',
      'الحالة: approved • المنفذ: admin • التاريخ: 2026-07-27',
      'المخزن: Baghdad • الكمية: 2 • النوع: product',
      'الكلفة النهائية: 10,000 USD',
    ];
    final arabic = RegExp(r'[\u0600-\u06FF]');
    for (final sample in samples) {
      final translated = AppTranslation.translate(sample);
      expect(
        translated,
        isNot(matches(arabic)),
        reason: 'Mixed English message for: $sample => $translated',
      );
      expect(
        translated,
        isNot(contains('accountBranch')),
        reason: 'Cascaded catalog replacement for: $sample => $translated',
      );
    }
  });
}
