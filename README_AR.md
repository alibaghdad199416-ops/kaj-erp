# Quality Line ERP — Final Cross-Stage Integrity Closure

نظام ERP احترافي ثنائي اللغة لشركة سيارات وقطع غيار، ويغطي CRM والفرص، السيارات والمنتجات، المخازن، البيع، الشراء، الصيانة، المحاسبة، الصناديق، الدفعات والعملات المتعددة.

- **Backend:** Supabase PostgreSQL/Auth/RPC/Realtime.
- **Hosting:** Firebase Hosting فقط.
- **العملات:** USD وIQD مع Cashbox/FX guards.
- **اللغة:** العربية RTL والإنجليزية LTR.
- **الإصدار:** `22.9.8+229008` — Final Cross-Stage Integrity Closure (R57/R58/R59/R60).

ابدأ من `START_HERE_AR.md`. سلسلة التحقق الرئيسية تبدأ من `npm run verify:workspace` وتشمل فاحصي المرحلتين 11 و12 وفحص التكامل النهائي بين جميع المراحل.

لا تستبدل ملفات الاتصال الحالية أثناء الفحص، ولم يتم تنفيذ Production Deployment داخل جولة التطوير.

للفحص الكامل على جهاز يحتوي Flutter/Dart:

```powershell
npm ci
flutter pub get
npm run verify:workspace
npm run format:check
npm run analyze
npm run test
```

وقبل أي نشر Production:

```powershell
npx supabase db push --linked --dry-run
npx supabase migration list --linked
```
