# تشغيل Supabase وFirebase Hosting

## إعداد Supabase داخل التطبيق

انسخ ملف المثال:

```powershell
Copy-Item dart_defines.example.json dart_defines.json
```

ضع `SUPABASE_URL` و`SUPABASE_ANON_KEY` فقط. لا تستخدم `service_role` في تطبيق الويب.

## تشغيل التطبيق محليًا

```powershell
flutter pub get
npm ci
npm run run:web
```

## التحقق قبل رفع قاعدة البيانات

```powershell
npm run verify
npm run analyze
npm run test
```

## تطبيق Migrations على مشروع Supabase المرتبط

```powershell
npm run db:push
```

راجع الناتج قبل المتابعة، ولا تعدّل Migration قديمة سبق تطبيقها؛ أضف Migration جديدة.

## بناء الويب

```powershell
npm run build:web
```

الناتج داخل `build/web`. البناء يستهدف JavaScript للمتصفحات، وليس WebAssembly.

## نشر Firebase Hosting

```powershell
npm run hosting:deploy
```

يجب أن يبقى `firebase.json` خاصًا بـHosting فقط؛ المصادقة والبيانات في Supabase.
