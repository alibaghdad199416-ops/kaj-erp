# Quality Line ERP 21.1.0 — KAJ Signature Phase 2

## نطاق المرحلة

- إعادة توحيد شاشة التحميل وتقديم حالة تشغيل محايدة عن مزود الخدمة.
- تثبيت تجربة تسجيل الدخول داخل الهيكل الفاخر المشترك مع اللغة والثيم.
- إضافة مكوّن `KajSignaturePageHero` المركزي للواجهات التنفيذية.
- ترقية لوحة المعلومات إلى رأس تنفيذي موحد يعرض أهم مؤشرات اليوم.
- ترقية مركز الإشعارات إلى مركز وعي تشغيلي مع مؤشرات غير المقروء والحرج والتحذيرات.
- إعادة بناء مقدمة البحث الشامل وسطح البحث وإزالة قيمة الفلتر العربية الثابتة.
- تحسين الشريط العلوي ليستهلك ألوان الثيم بدل الخلفية الداكنة الثابتة.
- بدء إزالة الخلط اللغوي من الحالات الفارغة والأخطاء والفلاتر داخل الإشعارات والبحث.

## الإصدار

`21.1.0+211000`

## الفحص

```powershell
npm run verify:v2110
npm run verify:source
npm run verify:localization
flutter analyze --fatal-infos --fatal-warnings
flutter test
npm run build:web
```

## التشغيل

```powershell
flutter run -d edge --dart-define-from-file=dart_defines.json
```

## الرفع

```powershell
npm run build:web
npm run hosting:deploy
```
