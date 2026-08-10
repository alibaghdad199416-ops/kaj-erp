# R49 — PRODUCT IDENTITY & FULL-SYSTEM CLOSURE AUDIT

**التاريخ:** 2026-08-10
**النطاق:** الرسائل الست مجتمعة بوصفها Master Specification واحدة.
**سياسة النشر:** لم يتم تنفيذ أي Production deployment إلى Supabase أو Firebase.

## الخلاصة

هذه الجولة بدأت من آخر نسخة `R49 FULL AUTONOMOUS COMPLETION` وحافظت على إصلاحاتها، ثم أضافت مراجعة مستقلة موجهة لهوية Quality Line ERP كنظام سيارات/قطع غيار/مخزون/محاسبة متعدد المستخدمين والعملات.

المعيار المستخدم لم يكن Compile/Verifier فقط، بل: سلامة البيانات → Workflow → المحاسبة والمخزون → الصلاحيات والعلاقات → UX/Responsive/Localization → الأداء → Regression.

## مشاكل إضافية اكتُشفت وأُصلحت في هذه الجولة

### 1) Read models كانت تختلق Currency/Status عند نقص البيانات

**Root Cause:** عدة `fromMap` paths استخدمت `USD`/`IQD` أو حالات مثل `posted`/`approved`/`completed` كـfallback عند قراءة سجل موجود. هذا يجعل بيانات ناقصة تبدو صحيحة بدل كشف المشكلة.

**الإصلاح:** القراءة authoritative لا تختلق العملة أو حالة الترحيل. Defaults بقيت فقط في نماذج إنشاء سجل جديد عندما تكون قيمة ابتدائية UI مقصودة. من أمثلة الإصلاح:

- Opportunity / Supplier / Sale / Purchase / Maintenance.
- Ledger Account / Journal Entry / Account Statement.
- Cashbox / Cash Transaction / Expense / Installment.
- Inventory / Car / Dashboard / Report export.
- `MaintenanceOrderModel`: status المفقود أصبح محافظًا (`draft`) بدل `completed`، و`isSoldCar` يقبل bool/0/1/string بصورة دفاعية.
- Expense approval المفقود لا يُفترض Approved.

أضيف `test/authoritative_financial_read_models_test.dart` كـRegression test ليعمل عند توفر Flutter SDK.

### 2) عمليات على مستند محفوظ كانت تفترض USD إذا غابت العملة

**Root Cause:** Sales/Purchase payment workflows وبعض draft reloads كانت تستخدم `order['currency'] ?? 'USD'`.

**الإصلاح:** السجل المحفوظ يجب أن يحمل USD أو IQD صريحة. العملة المفقودة/غير الصالحة توقف الإجراء برسالة مستخدم واضحة بدل إنشاء دفعة أو تعديل مستند بعملة مختلقة. Accounting balances وFixed Assets لم تعد تعرض USD كبديل صامت عند نقص العملة.

### 3) Maintenance paid invoice كان يمكن أن يسقط إلى حساب ذمم عام

**Root Cause:** مسار الصيانة المدفوعة التاريخي كان يستطيع استخدام حساب عام بالكود 1400 إذا لم يكن Customer محددًا.

**الإصلاح:** Migration جديدة Forward-Only تلف المسار النشط: الصيانة المدفوعة تتطلب Customer حقيقيًا، تتحقق من dual partner ledgers، تحل حساب العميل حسب العملة، ثم تمر عبر account guard. لا يوجد generic receivable fallback في wrapper الجديد.

### 4) طبقة المرفقات لم تكن متطابقة الصلاحيات بين UI/RPC/Storage

**Root Cause:** بعض Document RPCs التاريخية `SECURITY DEFINER` لم تكن تحتوي boundary كاملًا لكل mutation، وStorage policies كانت تعتمد عضوية الشركة بدل صلاحية Sales/Purchases المرتبطة بالمستند. كما أن UI upload لم يطلب Update permission صراحة.

**الإصلاح من الجذر:**

- Upload من Order Details يطلب `_updatePermission`.
- Sales document: `sales.view` للقراءة و`sales.update` للكتابة.
- Purchase document: `purchases.view` للقراءة و`purchases.update` للكتابة.
- Generic document mutation يبقى Admin-only.
- Grant permission وLegal Hold مقيدان بالإدارة.
- implementations القديمة سُحب منها EXECUTE للمستخدمين العاديين.
- canonical wrappers فقط هي surface المسموح بها.
- Storage SELECT/INSERT/UPDATE تستخدم نفس document permission boundary.
- Safe UUID parser يجعل malformed Storage path مرفوضًا بدل cast exception.

### 5) فلسفة Master-Data Accounting تم تثبيتها كRegression contract

مراجعة أحدث accounting engine أثبتت أن Sales/Purchase posting النشط يعتمد بالفعل على تعريف العنصر:

- Inventory Asset Account من Master Data.
- Sales COGS/Cost Expense من Master Data.
- USD/IQD Revenue Accounts من Master Data.
- Partner ledger حسب العملة.
- `erp_phase2_account_guard` للحساب/type/currency.
- Purchase item currency guard.

لم يتم الرجوع إلى fallbacks تاريخية. أضيف Gate R49 لمنع Regression في هذه الفلسفة.

## Migration الجديدة

`supabase/migrations/20260810060000_r49_product_identity_accounting_integrity.sql`

Forward-Only، ولم يتم تعديل migration تاريخية. تغطي:

1. Maintenance paid-customer/account boundary.
2. Document/attachment permission closure عبر RPC + Storage.
3. Safe Storage UUID parsing.
4. Revocation للـpre-R49 document implementations مع إبقاء canonical authenticated surface فقط.

Production orchestrator أصبح يتوقع **ست migrations R49** فقط ويرفض أي pending migration غير معروفة.

## ما تم الحفاظ عليه من الجولات السابقة

- Opportunity lifecycle وExpected Value persistence/read-back.
- Opportunity ↔ Sales ↔ Delivery ↔ Invoice ↔ Payment projection.
- One active Sales Order per Opportunity behavior.
- Receipt/Delivery/Material Issue inventory boundaries.
- Invoice-owned accounting.
- Cashbox/FX linked payments and transfer guards.
- Multi-currency financial summaries بدون جمع USD وIQD في scalar واحد.
- Inventory FIFO/value-by-currency.
- R44 Thumbnail Optimization بدون per-card original image RPC.
- Business References مع بقاء UUID keys داخلية.
- Responsive dialog reflow وعدم استخدام fixed-canvas scaling.
- Fixed Assets repository boundary.
- Localization architecture Arabic/English.

## نتائج التحقق — Verified فعليًا في هذه البيئة

- `npm run verify` — PASS.
- `npm run verify:final` components — PASS عند تشغيلها؛ الأمر المركب ظهر كاملًا سابقًا ثم في آخر تشغيل تجاوز مهلة الأداة بعد Database verifier، لذلك لا نسجله كـPASS منفرد أخير.
- `verify:database` — PASS.
  - 1299 PostgreSQL CREATE/REPLACE definitions.
  - 726 active signatures.
- PostgreSQL text/UUID boundaries — PASS.
  - 725 active signatures.
  - 154 table schemas.
- `verify:structure` — PASS.
  - 338 reachable Dart source files + 3 test-only.
  - 164 literal RPC calls، كلها معرفة.
  - 33 executable tests + 1 support file.
  - 244 migrations.
- Static Dart source sanity — PASS، 341 Dart files.
- Localization verifier — PASS.
- UI/localization audit — PASS.
  - raw unlocalized UI candidates: 0.
  - runtime-localized AppText literals: 375.
  - non-design-system color literals: 76.
  - non-design-system radius literals: 112.
- `verify:package` — PASS.
- `verify:delivery` — PASS.
- `verify:deployment-target` — PASS.
- R8→R25 — PASS بعد آخر التعديلات.
- R26→R49 — PASS بعد آخر التعديلات.
- R44 — 9/9 PASS.
- R46 — 10/10 PASS.
- R47 — 6/6 PASS.
- R48 — 12/12 PASS.
- R49 — **45/45 PASS**.
- Independent static scans:
  - no direct Supabase access inside UI pages/widgets.
  - no unresolved TODO/FIXME/HACK/XXX in runtime/source SQL/tool code scan.
  - no empty Dart `catch {}` found.
  - no direct fixed UI width/height >=500 outside the intended launch-shell breakpoint.
  - frontend config rejects `service_role`/`sb_secret` keys.

## Requires Integration Verification

هذه البنود **ليست PASS في هذه البيئة**:

1. `dart format` — Dart CLI غير مثبت.
2. `flutter analyze` — Flutter SDK غير مثبت.
3. `flutter test` — Flutter SDK غير مثبت.
4. `flutter build web` — Flutter SDK غير مثبت.
5. Browser walkthrough حقيقي Zoom 100%، RTL/LTR، Empty/Loading/Error/long text/large data.
6. End-to-End against a real migrated Supabase database with representative company data.
7. Supabase Security/Performance Advisors: تمت محاولة تشغيلهما read-only على المشروع المرتبط لكن الاتصال رفض العملية بسبب صلاحية MCP (`You do not have permission to perform this action`).

تمت محاولة تنزيل Flutter SDK محليًا أيضًا، لكن بيئة التنفيذ لا تملك DNS/Internet من الـcontainer، لذلك تعذر تنزيل SDK. لم يتم الادعاء بتشغيل أي من البنود السابقة.

## Quality/Visual note

UI audit ما زال يحصي 76 Color literals و112 Radius literals خارج Design System. لم يتم إجراء replace آلي أعمى لأن جزءًا منها status semantics / launch identity / PDF / pill styling. بدون Flutter visual runtime سيكون تصفير الرقم هدفًا شكليًا قد يضر Information Hierarchy. المخالفات الوظيفية المثبتة في responsive/overflow/data display تم إصلاحها، لكن Visual Acceptance النهائي يبقى ضمن Browser integration أعلاه.

## أوامر الفحص النهائية

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

أو على Windows/PowerShell باستخدام الـvalidator المجهز:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/validate_r49_workspace.ps1
```

هذا الـvalidator ينفذ npm ci + flutter pub get + format + كل R49/workspace gates + analyzer + tests + fresh web build.

## أوامر النشر — لا تُنفذ قبل نجاح Integration Verification

Dry-run Supabase فقط:

```bash
npx supabase db push --linked --dry-run
npx supabase migration list --linked
```

النشر المجهز بعد المراجعة:

```bash
npm run deploy:production
```

المسار يثبت أولًا workspace validation/fresh web build، ثم Supabase dry-run ويرفض migrations غير المتوقعة، ثم push عند الحاجة، ثم Firebase Hosting. **لم يتم تشغيل هذا الأمر أثناء التطوير.**

## حالة DONE

**Statically/Contract Verified إلى أعلى مستوى متاح في البيئة الحالية، وليس Final Runtime Production Acceptance.**

لا توجد مشكلة محلية مثبتة متبقية اكتُشفت في هذه الجولة ويمكن إصلاحها بأمان دون Flutter runtime أو قاعدة Supabase مطبق عليها migrations/بيانات حقيقية. Final Production acceptance مشروط بنجاح Flutter analyzer/tests/build والـbrowser/E2E integration المذكور أعلاه.
