# R24.1 Compile Closure

تصحيح لحزمة R24 بعد أن كشف `flutter analyze` على Windows أن إضافة `isExpanded: true` الآلية أفسدت 12 موضعًا نحويًا داخل DropdownButtonFormField.

- تم تصحيح المواضع الـ12 دون تغيير منطق Backend أو Production configuration.
- جميع 75 DropdownButtonFormField تحتوي `isExpanded: true` بصياغة constructor صحيحة.
- تمت إضافة Gate إلى `verify:r24` يرفض `child: isExpanded:`, `return isExpanded:` و`= isExpanded:` لمنع تكرار الخطأ.
- يجب تشغيل `flutter analyze --fatal-infos --fatal-warnings` و`flutter test` على جهاز Flutter قبل النشر.
