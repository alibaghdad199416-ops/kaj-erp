# Quality Line ERP — Final Cross-Stage Integrity Closure

المرجع التشغيلي النهائي لهذه الحزمة هو:

`Final Cross-Stage Integrity Closure (R57/R58/R59)`

الإصدار canonical:

`22.9.8+229008`

وسلسلة التحقق الرئيسية هي `npm run verify:workspace`، ولا تعتمد على GitHub Quality Gate كبديل عن الفحص الداخلي.

## 1) التثبيت والفحص الكامل
```powershell
npm ci
flutter pub get
npm run verify:workspace
npm run format:check
npm run analyze
npm run test
npm run build:web
npm run verify:package
npm run verify:delivery
```

## 2) التشغيل والمعاينة
```powershell
npm run run:web
```
أو:
```powershell
flutter run -d edge --dart-define-from-file=dart_defines.json
```

راجع Zoom 100%، العربية RTL، الإنجليزية LTR، وحالات Empty/Loading/Error/Long text، ثم دورات Sales/Purchase/Maintenance/FX الفعلية.

## 3) Supabase قبل النشر
```powershell
npx supabase db push --linked --dry-run
npx supabase migration list --linked
```

## 4) النشر

لا يتم تنفيذ Production Deployment ضمن جولة الإصلاح الحالية. عند تنفيذ النشر مستقبلًا، يجب أن تمر العملية عبر منظومة التحقق الحالية وأن تكتشف جميع migrations الموجودة في المستودع بدل الاعتماد على قائمة R49 ثابتة.
