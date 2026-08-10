# أوامر R22 — Quality Line ERP

## 1) فك ZIP في مجلد جديد
لا تنسخ R22 فوق R21 المبنية.

## 2) تحقق Windows الكامل
```powershell
npm run validate:r22:windows
```
المسار يقوم بـ:
- verify:delivery قبل generated artifacts
- npm ci
- flutter pub get
- dart format
- format:check
- verify:workspace بما فيه R22
- flutter analyze --fatal-infos --fatal-warnings
- flutter test
- fresh build:web

النتيجة المطلوبة:
```text
PASS R22 Windows release validation
```

## 3) النشر الكامل
يمكن بعد ذلك تشغيل:
```powershell
npm run deploy:r22:production
```
أو:
```powershell
npm run deploy:production
```

السكربت يعيد installed-workspace validation/fresh build ثم:
1. Supabase dry-run.
2. يرفض أي migration غير R22.
3. يدفع R22 إلى Supabase أولاً.
4. يعمل dry-run ثانياً ويشترط عدم بقاء migrations pending.
5. يعرض remote migration list.
6. يختار Firebase `kaj-erp`.
7. يرفع fresh `build/web` إلى Firebase Hosting.

المتوقع في أول dry-run بعد R21:
```text
20260808043000_r22_production_accounting_consolidation.sql
```

النتيجة النهائية المطلوبة:
```text
PASS R22 production deployment
Supabase project: fjiaxdorunedmltgqtty
Firebase Hosting: https://kaj-erp.web.app
```

## 4) بعد النشر
- أغلق tabs القديمة أو نفذ Ctrl+Shift+R.
- سجل الدخول بحساب System Admin مرة واحدة.
- R22 canonical reconciliation يعمل قبل تحميل modules.
- افتح Production Readiness وتأكد أن `RUNTIME_RPC_CONTRACT` و`CANONICAL_DATA_STATE` ناجحان.

## 5) Acceptance tests المطلوبة
### Purchase
- draft order → approve → receipt → approve receipt → invoice → approve invoice.
- يجب أن يكون القيد Supplier↔Inventory مباشرة.
- لا يوجد capitalization/clearing journal.

### Sales
- جرّب item cost currency مختلفة عن invoice currency.
- Revenue/Customer بعملة الفاتورة.
- Inventory/COGS بعملة التكلفة/FIFO.

### Cashbox
- same-currency transfer.
- linked FX transfer.
- reconciliation difference = 0، أو issue واضح إن كانت حالة تاريخية ملتبسة.
- لا Ledger Difference journal.

### Historical state
- المخزن المحذوف لا يعود.
- حسابات الرسملة القديمة لا تعود Active.
- القيود التاريخية القابلة لإعادة البناء تصبح `direct_supplier_inventory`.
- الحالات غير القابلة للحسم لا تعدل تلقائياً وتظهر في health/reconciliation.

## ممنوع
- لا تستخدم `supabase db reset` على Production.
- لا تعدل migration history يدوياً.
- لا تغير `dart_defines.json`.
- لا تستخدم `-ReconfigureRuntime`.
