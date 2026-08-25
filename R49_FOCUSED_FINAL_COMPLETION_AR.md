# R49 — FOCUSED FINAL COMPLETION & DELIVERY REPORT

## الحالة
تم تنفيذ جولة Focused مستقلة على آخر ZIP مصدق، مع إبقاء نطاق الرسائل التسع كاملًا. هذه الحزمة لا تعتبر `PASS` البنيوي بديلًا عن Runtime؛ التصنيف أدناه يفصل بين ما شُغّل فعليًا وما يحتاج Flutter/browser/live Supabase.

## أهم الأسباب الجذرية التي أُغلقت في هذه الجولة
1. **Permission/runtime surfaces قديمة**: بعض المسارات التاريخية كانت أوسع من canonical R49 wrappers أو لا ترفض stale writes بما يكفي. تم تثبيت granular permissions، company/tenant checks وstale-version rejection في المسارات الفعلية، مع إبقاء implementations التاريخية داخلية حيث يلزم.
2. **Financial currency truth**: أُزيلت silent USD fallbacks من subledger/reporting paths؛ البيانات ذات العملة المفقودة أو غير المدعومة تفشل مغلقة بدل أن تتحول إلى USD.
3. **Inventory valuation ناقص للسيارات**: Dashboard/Reports كان يمكن أن يعتمد product FIFO فقط. أصبح valuation يشمل `product` و`car` cost layers ويجمع حسب العملة.
4. **Net Profit غير محاسبي**: تم استبدال Sales−Purchases−Expenses arithmetic بمصدر GL صحيح: posted Revenue−Expense lines حسب العملة والفترة.
5. **Installment mutation surface**: جدول الأقساط workflow-owned؛ standalone browser mutators القديمة أصبحت داخلية، بينما القراءة والتحصيل يمران عبر المسار canonical.
6. **Search / stale results**: Opportunities أُضيفت للبحث العام، النتائج المالية أصبحت currency-aware، والـcache يبطل نفسه بعد committed cross-module changes.
7. **Cashbox failure resistance**: الحفظ يفشل مغلقًا عند Currency/Active state غير صالحين، وصلاحيات save/delete محمية في Backend، والحذف يرفض صندوقًا له حركات مالية.
8. **Release/documentation traceability**: تم توحيد `AppReleaseInfo`, `web/version.json`, boot token، README وSTART_HERE على R49 بدل metadata قديمة.
9. **Historical verifier drift**: Gates قديمة كانت تطلب أسماء RPC أقدم رغم وجود wrappers R49 أقوى. تم تعديل الفاحص ليثبت السلسلة الحالية دون إعادة Runtime إلى عقد أضعف.

## قواعد ERP المحفوظة
- Purchase Order approval لا يزيد المخزون ولا يملك posting النهائي؛ Receipt هو حد الكمية وInvoice هو حد accounting التجاري.
- Sales Order approval لا ينقص المخزون؛ Delivery هو حد الكمية وInvoice هو حد revenue/COGS posting.
- Maintenance material issue/consumption هو حد الحركة المخزنية؛ Invoice هو حد accounting النهائي.
- Payment مستقل عن Invoice.
- Cashbox/FX linked-payment guards محفوظة.
- R44 thumbnail optimization محفوظة؛ لا per-card original-image RPC.
- UUID يبقى المفتاح الداخلي، والمراجع التجارية القصيرة تبقى واجهة تشغيلية.

## Migrations R49 الحالية
1. `20260810021000_r49_crm_business_reference_closure.sql`
2. `20260810030000_r49_end_to_end_opportunity_lifecycle_readback.sql`
3. `20260810031000_r49_master_business_references.sql`
4. `20260810040000_r49_invoice_idempotency_quality_closure.sql`
5. `20260810050000_r49_installment_currency_fixed_asset_boundary.sql`
6. `20260810060000_r49_product_identity_accounting_integrity.sql`
7. `20260810070000_r49_permission_scope_integrity.sql`
8. `20260810080000_r49_independent_delivery_search_traceability.sql`
9. `20260810090000_r49_focused_final_permission_runtime_closure.sql`
10. `20260810100000_r49_financial_subledger_currency_integrity.sql`
11. `20260810110000_r49_accounting_profit_installment_surface_closure.sql`

كلها Forward-Only؛ لم يتم تعديل migration تاريخية مطبقة في هذه الجولة.

## VERIFIED — تم تشغيله فعليًا على آخر Code State
- `npm run verify` — PASS.
- `npm run verify:final` — PASS.
- `verify:source` — 343 Dart files؛ imports/exports سليمة ولا merge markers.
- `verify:localization` — PASS؛ العربية والإنجليزية في catalog والعناصر الثابتة لها exact English mappings.
- `verify:structure` — 340 reachable source files + 3 test-only؛ 162 literal RPC calls كلها معرفة؛ 35 executable tests + support file؛ 249 migrations.
- PostgreSQL compatibility — 1384 definitions / 796 active signatures.
- UUID/Text boundaries — 795 active signatures / 155 table schemas.
- `audit:final` — 0 raw unlocalized UI candidates؛ 76 non-design-system color literals؛ 112 radius literals.
- R8→R44 — PASS لكل Gate موجود.
- لا يوجد R45 verifier مستقل في `package.json`.
- R46 — 10/10 PASS.
- R47 — 6/6 PASS.
- R48 — 12/12 PASS.
- R49 — **78/78 PASS** بعد إضافة فحص وثائق الإصدار الحالية.
- `verify:package` — PASS.
- `verify:delivery` / deployment target — PASS.
- Supabase project ref المجهز: `havlqebmnjdcwmpaaqew`.
- Firebase project: `kaj-erp`.
- ZIP/package hygiene يفحص generated/local credentials ويمنع artifacts غير المطلوبة.

سجل سلسلة Regression محفوظ في `verification/R49_FOCUSED_FINAL_REGRESSION.txt`، وVerification Matrix في `docs/audit/R49_FOCUSED_VERIFICATION_MATRIX.md`.

## STATICALLY VERIFIED
- Accounting account resolution وcurrency/account guards في canonical SQL.
- Product + Car FIFO inventory valuation حسب العملة.
- Invoice idempotency وstale-write protections.
- CRM Opportunity ↔ Sales workflow projection/read-back.
- Cashbox/FX permission and currency boundaries.
- Multi-user permission surfaces وcompany isolation في canonical wrappers.
- Responsive source contracts وR44 performance contracts.
- Printing/export source paths وعدم اختلاق payment/journal rows.

## EXTERNAL VERIFICATION REQUIRED
بيئة التنفيذ الحالية لا تحتوي `flutter` أو `dart`، كما أن DNS الخارجي محجوب (`Could not resolve host: storage.googleapis.com`) لذلك تعذر تنزيل Flutter SDK. لذلك لم يتم الادعاء بتشغيل:
- `dart format`
- `flutter analyze`
- `flutter test`
- `flutter build web`
- Chrome visual walkthrough عند Zoom 100%
- Arabic RTL / English LTR visual inspection
- Live Supabase end-to-end accounting/inventory transactions
- multi-user concurrent browser test

هذه ليست `PASS` في هذا التقرير؛ تحتاج بيئة المستخدم الخارجية.

## أقصر فحص خارجي مطلوب
```powershell
npm ci
flutter pub get
powershell -NoProfile -ExecutionPolicy Bypass -File tool/validate_r49_workspace.ps1
```
ثم:
```powershell
npx supabase db push --linked --dry-run
npx supabase migration list --linked
```
بعد ذلك فقط اختبر على Live data الدورات:
- Opportunity → Sale → Delivery → Invoice → Payment
- Purchase → Receipt → Invoice → Payment
- Maintenance → Material Issue → Invoice → Payment
- Cross-currency Cashbox/FX payment/transfer
مع مستخدمين بصلاحيات مختلفة واختبار stale/double-submit/partial-payment.

إذا فشل اختبار خارجي، المطلوب إرجاع **نص الخطأ/stack/RPC response** فقط ليتم إصلاح Root Cause في المشروع، وليس تعديل الملفات يدويًا من المستخدم.

## Deployment
لم يتم تنفيذ Supabase/Firebase Production deployment ولم يتم Git commit/push. بعد نجاح الفحص الخارجي فقط:
```powershell
npm run deploy:production
```

## شهادة النطاق
ضمن ما أمكن تشغيله وفحصه داخل هذه البيئة: **لا توجد Failure مفتوحة أو Known Fixable Error اكتُشفت في الجولة الحالية وتم تركها دون إصلاح**. هذا لا يُعد ضمانًا مطلقًا بخلو البرنامج من أي bug مستقبلي، ولا يحوّل البنود الخارجية أعلاه إلى Runtime proof.
