# بوابات الجودة الحالية

تم حذف سلاسل أوامر الإصدارات القديمة، وأصبحت الأوامر المعتمدة:

```powershell
npm run format        # تنسيق lib وtest وintegration_test
npm run verify        # فحص البنية وقاعدة البيانات والمعمارية والمصدر أثناء التطوير
npm run verify:package # فحص نظافة حزمة التسليم قبل تثبيت المتطلبات فقط
npm run analyze       # Flutter analyzer بأخطاء وتحذيرات صارمة
npm run test          # اختبارات Flutter السلوكية والوحدوية
npm run check         # verify + format check + analyze + test
npm run build:web     # تجهيز وبناء وفحص JavaScript Web للإنتاج
npm run check:release # جميع البوابات ثم بناء Web وفحصه
```

## ما تغطيه `npm run verify`

- وصول ملفات Dart المستخدمة وعدم وجود ملفات إنتاج ميتة غير موثقة.
- عدم وجود دورات Imports.
- صحة جميع استيرادات `package:quality_line_erp`.
- عدم اتصال الصفحات والـWidgets بـSupabase مباشرة.
- تسجيل Controllers طويلة العمر مركزيًا أو توثيقها كحالة محلية.
- وجود مستهلك تحديث لكل مصدر Mutation وRealtime.
- عقود RPC وPostgreSQL وحدود UUID/Text.
- سلامة الترجمة واللغة الإنجليزية الافتراضية ودعم العربية.
- صحة ترتيب بناء Web وفحصه في GitHub Actions.

## فحص حزمة التسليم

شغّل `npm run verify:package` أو `npm run check:delivery` على نسخة نظيفة قبل تنفيذ `flutter pub get` و`npm ci` وقبل إنشاء `dart_defines.json`. هذا الفحص يتعمد رفض `.dart_tool` و`node_modules` و`dart_defines.json` وملفات البناء حتى لا تدخل في ZIP أو Git.

## اختبارات Flutter

يوجد 31 ملف اختبار تنفيذي مركزًا، إضافة إلى ملف مساعد للاختبارات، وتختبر السلوك الفعلي، ومنها إدارة صفحات الوحدات، حماية التغييرات غير المحفوظة، الترجمة، دفتر الأستاذ، الصلاحيات، ربط العمليات التجارية، وتحويل نماذج البيانات.

لا تُستخدم اختبارات Flutter لقراءة ملفات المصدر والبحث عن أسماء متغيرات؛ العقود البنيوية الثابتة تُفحص بواسطة أدوات Python حتى تبقى إعادة الهيكلة الآمنة ممكنة.
