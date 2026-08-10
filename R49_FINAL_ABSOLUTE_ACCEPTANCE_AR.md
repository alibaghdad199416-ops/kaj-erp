# R49 — FINAL ABSOLUTE ACCEPTANCE & ZERO-KNOWN-ERROR CLOSURE

التاريخ: 2026-08-10

هذه الجولة مبنية على `Quality-Line-ERP-R49-PRODUCT-IDENTITY-FULL-CLOSURE.zip` وتحافظ على جميع إصلاحات R44–R49 السابقة. لم يتم تنفيذ أي Production Deployment إلى Supabase أو Firebase.

## النتيجة التنفيذية

ضمن الأدوات المتاحة في بيئة العمل الحالية، لا توجد Failure معروفة متبقية في فحوص المصدر/العقود/قاعدة البيانات/التسليم يمكن إصلاحها محليًا وتم تركها دون إصلاح. تم تنفيذ دورة Audit → Root Cause → Fix → Regression على الحالة النهائية نفسها.

## الإصلاحات الإضافية في جولة القبول النهائي

### 1. دفعات الفواتير — منع اختلاق USD لصندوق ناقص العملة

المشكلة: `invoice_payment_batch_dialog.dart` كان يستخدم `?? 'USD'` عند قراءة عملة Cashbox. Cashbox ناقص/تالف الـcurrency كان يمكن أن يتحول إلى Payment Draft بعملة USD غير موجودة في مصدر الحقيقة.

الإصلاح:
- قبول Cashboxes ذات ID وعملة صريحة `USD/IQD` فقط داخل Dialog.
- منع إضافة/حفظ الدفعات إذا لم يوجد Cashbox صالح.
- Empty State واضح بدل عملية مالية بعملة مختلقة.
- عرض المتبقي باستخدام `MoneyFormatter` المركزي.
- إضافة R49 regression gate يمنع عودة fallback المذكور.

### 2. Permission Scope Integrity — توحيد UI وBackend

المشكلة الأولى: UI يسمح لـ`permissions.scopes.manage` بإدارة صلاحيات مستخدم آخر، بينما RPC القراءة كان يسمح فقط للـAdmin أو للمستخدم نفسه.

المشكلة الثانية: RPC الكتابة/المسح كان يسمح كذلك بـ`users.update`، ما يجعل صلاحية تعديل بيانات المستخدم قادرة Backend-side على منح/سحب Permissions حتى عندما لا يعرض UI هذا الإجراء.

الإصلاح: Migration Forward-Only:

`20260810070000_r49_permission_scope_integrity.sql`

وتقوم بـ:
- Admin أو `permissions.scopes.manage` فقط لإدارة صلاحيات مستخدم آخر.
- المستخدم العادي يستطيع قراءة Effective Permissions الخاصة به فقط.
- Scope Manager يستطيع قراءة وإدارة المستخدمين داخل نفس Tenant.
- التحقق من وجود Target User فعليًا داخل الشركة قبل Set/Clear/Read.
- إزالة `users.update` كمسار بديل لإدارة Permission Scopes.
- الحفاظ على `SECURITY DEFINER` مع `search_path=public` وrevoke من `public/anon`.
- تحديث وصف `users.update` في Flutter ليعكس تعديل بيانات المستخدم/الحالة/الدور فقط.

### 3. Localization — منع تسرب العربية في English Mode

المشكلة: الفاحص القديم يمنع `Text('...')` الخام، لكنه لا يثبت أن كل عبارة عربية ثابتة تمر عبر `AppText/AppTranslation` لديها ترجمة Exact. تم اكتشاف 51 عبارة ثابتة بدون Exact English entry.

الإصلاح:
- إضافة Exact translations للعبارات المكتشفة في `ModuleTranslationCatalog`.
- توسيع `verify_localization.py` ليكتشف أي Fixed Arabic literal user-facing داخل `AppText/AppTranslation.translate` لا يمتلك English catalog entry.
- إصلاح verifier ليبقى formatter-invariant وفق R11.

### 4. Delivery Hygiene

المشكلة: `supabase-push-debug.txt` بقي داخل ZIP السابق رغم أنه Debug artifact غير مطلوب في Production source package.

الإصلاح:
- حذف الملف من الحزمة.
- توسيع `verify_package_sanity.py` لمنع `supabase-push-debug.txt` و`supabase-debug.log` مستقبلاً.

## قواعد ERP التي أعيد التحقق منها ولم يتم تغييرها

- Purchase Approval ≠ Receipt.
- Receipt المعتمد هو حد زيادة كمية المخزون.
- Sales Approval ≠ Delivery.
- Delivery المعتمد هو حد نقص كمية المخزون.
- Maintenance Material Issue/Consumption هو الحد التشغيلي لحركة مواد الصيانة.
- Invoice Approval يملك الترحيل التجاري النهائي وفق R46؛ Order/Logistics لا تنشئ القيد النهائي.
- Payment مستقل عن Invoice.
- Cashbox/FX linked-payment guards محفوظة.
- Master-data account bindings + account type/currency guards محفوظة.
- Inventory/Car valuation summaries تبقى مفصولة حسب عملة التكلفة.
- R44 thumbnail batching/cache محفوظ ولا يوجد رجوع إلى per-card Base64/N+1 image RPC.
- UUID يبقى داخليًا مع Business References القصيرة التي أضيفت في R49.

## FULLY VERIFIED — تم تشغيله فعليًا على الحالة النهائية

- `npm run verify` — PASS.
- `npm run verify:final` — PASS.
- `npm run verify:database` — PASS.
- `npm run verify:delivery` — PASS.
- `verify:package` — PASS.
- `verify:deployment-target` — PASS.
- R8 → R44 — PASS (R45 لا يملك verifier مستقلًا في `package.json`).
- R46 — PASS 10/10.
- R47 — PASS 6/6.
- R48 — PASS 12/12.
- R49 — PASS 47/47.
- Static Dart source: 341 files checked.
- Dart graph: 338 reachable + 3 test-only support files; no import cycles.
- Literal RPC contract: 164 calls، كلها معرفة.
- Executable Flutter test files discovered: 33 + 1 support file.
- Migrations: 245.
- PostgreSQL CREATE/REPLACE compatibility: 1303 definitions / 726 active signatures.
- PostgreSQL UUID/Text boundaries: 725 active signatures / 154 table schemas.
- Localization: PASS، fixed Arabic literals now require exact English entries.
- UI/localization audit: 0 raw unlocalized UI candidates.
- Package hygiene: no debug/temp/generated artifact known in delivery root.
- No unresolved merge markers.
- No obsolete Supabase project ref in runtime/config/deploy surface.
- Browser config contains publishable key only; no service-role/secret key packaged.

## STATICALLY VERIFIED

هذه الجوانب تم تتبع عقودها وكودها وRegression gates، لكن إثبات السلوك الحقيقي يتطلب Flutter/Web أو قاعدة متصلة:

- Full Opportunity → Sales → Delivery → Invoice → Payment runtime flow.
- Purchase → Receipt → Invoice → Payment runtime flow.
- Maintenance → Issue → Invoice → Payment runtime flow.
- Actual Journal balance/content against live transactional data.
- Actual FIFO/valuation reconciliation against live inventory records.
- RLS behavior under multiple real authenticated users/roles.
- RTL/LTR layout rendering and all Modal visual states.

## REQUIRES MY EXTERNAL ENVIRONMENT

بيئة التنفيذ الحالية لا تحتوي `flutter` أو `dart`. تم أيضًا اختبار الوصول لتنزيل Flutter SDK، وفشل DNS برسالة:

`Could not resolve host: storage.googleapis.com`

لذلك لم يتم الادعاء بتشغيل البنود التالية:

```text
dart format
flutter analyze
flutter test
flutter build web
Chrome walkthrough at Zoom 100%
Arabic RTL / English LTR visual walkthrough
Empty / loading / error / long-text runtime states
Live Supabase transactional/RLS integration scenarios
```

## BLOCKED

لا يوجد Source/SQL/Verifier fix معروف حاليًا مصنف BLOCKED. القيود المتبقية هي Runtime/External-environment verification المذكورة أعلاه.

## Migration R49 النهائية

Production orchestrator يسمح فقط بمigrations R49 التالية، ويرفض pending migrations غير المعروفة:

1. `20260810021000_r49_crm_business_reference_closure.sql`
2. `20260810030000_r49_end_to_end_opportunity_lifecycle_readback.sql`
3. `20260810031000_r49_master_business_references.sql`
4. `20260810040000_r49_invoice_idempotency_quality_closure.sql`
5. `20260810050000_r49_installment_currency_fixed_asset_boundary.sql`
6. `20260810060000_r49_product_identity_accounting_integrity.sql`
7. `20260810070000_r49_permission_scope_integrity.sql`

لم يتم تعديل historical applied migration.

## أوامر الفحص المطلوبة في بيئتك

من جذر المشروع:

```bash
npm ci
flutter pub get
npm run format
npm run verify:workspace
npm run format:check
npm run analyze
npm run test
npm run build:web
npm run verify:package
npm run verify:delivery
```

أو على Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/validate_r49_workspace.ps1
```

### فحص Supabase قبل النشر

```bash
npx supabase db push --linked --dry-run
npx supabase migration list --linked
```

المتوقع: لا يظهر pending migration خارج قائمة R49 السباعية أعلاه.

### اختبار خارجي قصير يجب تنفيذه بعد تطبيق migrations في بيئة اختبار/Production-controlled

1. مستخدم Admin: فتح Users → Custom Permissions لمستخدم آخر، الحفظ وإعادة الفتح؛ يجب أن تستمر الاختيارات.
2. مستخدم يملك `permissions.scopes.manage` وليس Admin: يجب أن يستطيع قراءة وتعديل Custom Permissions داخل نفس الشركة.
3. مستخدم يملك `users.update` فقط: يجب أن يستطيع تعديل بيانات المستخدم المسموحة، لكن Backend يرفض RPC Set/Clear permission scopes.
4. إنشاء Sales/Purchase/Maintenance invoice/payment على USD وIQD وتجربة Cashbox ناقص/غير مرتبط؛ العملية غير الصحيحة يجب أن تُرفض بلا fallback.
5. تنفيذ دورة Receipt/Delivery/Material Issue والتأكد أن الكمية تتحرك مرة واحدة فقط وأن Invoice لا تضاعف الحركة.
6. مقارنة Inventory Value per currency مع cost layers والحسابات ذات العلاقة.
7. تشغيل Chrome Zoom 100% بالعربية والإنجليزية على أهم Modals والتحقق من عدم وجود overflow.

إذا فشل أي اختبار خارجي، احتفظ برسالة الخطأ + اسم العملية + المستخدم/الصلاحية + Currency + Document Reference لإعادة تتبع Root Cause في المشروع.

## النشر

لم يتم تنفيذ Production deployment.

بعد نجاح جميع الاختبارات الخارجية/Flutter فقط:

```bash
npm run deploy:production
```

الهدف الموثق في verifier:
- Supabase: `havlqebmnjdcwmpaaqew`
- Firebase Hosting: `kaj-erp`
