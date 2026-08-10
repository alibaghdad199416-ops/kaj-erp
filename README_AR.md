# Quality Line ERP — R49 Focused Final Completion

نظام ERP احترافي ثنائي اللغة لشركة سيارات وقطع غيار، ويغطي CRM والفرص، السيارات والمنتجات، المخازن، البيع، الشراء، الصيانة، المحاسبة، الصناديق، الدفعات والعملات المتعددة.

- **Backend:** Supabase PostgreSQL/Auth/RPC/Realtime.
- **Hosting:** Firebase Hosting فقط.
- **العملات:** USD وIQD مع Cashbox/FX guards.
- **اللغة:** العربية RTL والإنجليزية LTR.
- **الإصدار:** `22.9.8+229008` — R49 Focused Final Completion.

ابدأ من `START_HERE_AR.md`. تقرير هذه الحزمة النهائي هو `R49_FOCUSED_FINAL_COMPLETION_AR.md`.

لا تستبدل ملفات الاتصال الحالية أثناء الفحص، ولم يتم تنفيذ Production Deployment داخل جولة التطوير.

للفحص الكامل على جهاز يحتوي Flutter/Dart:

```powershell
npm ci
flutter pub get
powershell -NoProfile -ExecutionPolicy Bypass -File tool/validate_r49_workspace.ps1
```

وقبل أي نشر Production:

```powershell
npx supabase db push --linked --dry-run
npx supabase migration list --linked
```
