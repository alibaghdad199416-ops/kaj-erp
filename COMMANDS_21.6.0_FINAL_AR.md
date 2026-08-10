# أوامر الإصدار النهائي 21.6.0

```powershell
npm ci
flutter clean
flutter pub get

npm run verify:final
flutter analyze --fatal-infos --fatal-warnings
flutter test
npm run build:web
```

## تشغيل المتصفح
```powershell
flutter run -d edge --dart-define-from-file=dart_defines.json
```

## معاينة Firebase
```powershell
firebase hosting:channel:deploy signature-final
```

## Supabase ثم الإنتاج
```powershell
npx supabase db push --linked --dry-run
npx supabase db push --linked
npm run hosting:deploy
```
