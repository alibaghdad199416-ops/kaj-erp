# Quality Line ERP — R49 Focused Final Completion

المرجع النهائي لهذه الحزمة:

`R49_FOCUSED_FINAL_COMPLETION_AR.md`

وVerification Matrix:

`docs/audit/R49_FOCUSED_VERIFICATION_MATRIX.md`

لا تغيّر `dart_defines.json` أو `.firebaserc` أو `firebase.json` أثناء الفحص.

## 1) التثبيت والفحص الكامل
```powershell
npm ci
flutter pub get
powershell -NoProfile -ExecutionPolicy Bypass -File tool/validate_r49_workspace.ps1
```

أو يدويًا:
```powershell
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

## 4) النشر بعد نجاح اختبارات البيئة الخارجية فقط
```powershell
npm run deploy:production
```

ترتيب النشر المجهز: Validation/Build → Supabase → Firebase Hosting. لم يُنفذ Production Deployment أثناء التطوير.
