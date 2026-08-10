# Quality Line ERP — R24 Runtime Accounting / Invoice / Payment / UI Closure

التاريخ: 2026-08-08

## الهدف
إغلاق الأعطال التي ظهرت في التشغيل الحقيقي بعد R23، وليس الاكتفاء بفحوص المصدر: ثبات ربط حسابات الصناديق بعد الحفظ/Refresh، سندات القبض والصرف، التحويلات بين الصناديق، فواتير الشراء والبيع والصيانة، الدفعات بنفس العملة وبعملة مختلفة، بطء الواجهة، `setState during build`، شريط Flutter الأصفر/الأسود، وتطبيق اللغة الفعلي.

## إصلاحات Production — Supabase
تم نشر خمس migrations من R24 مباشرة على Production:

1. `20260808085021_r24_runtime_accounting_payment_performance_closure.sql`
   - أزال إعادة الربط التاريخية الثقيلة من Save/Post/Transfer العادي.
   - جعل deferred reconciliation محدودًا بالـCash Transaction الحالية وبهوية حتمية.
   - أصلح حارس حقول سند القبض/الصرف حتى لا يحذف `type` وحقول الهوية المرجعية.
   - وحّد `accountId` و`account_id` على الحساب الحالي.
   - أصلح الربط المكرر فقط عندما توجد مطابقة حتمية واحدة بالاسم/العملة وحساب غير مستخدم.

2. `20260808085451_r24_journal_currency_invoice_closure.sql`
   - يضيف عملة القيد إلى كل Journal Line قبل تشغيل integrity triggers.
   - يمنع اختلاف عملة السطر صراحةً عن عملة القيد.

3. `20260808090027_r24_sales_invoice_immutable_logistics_closure.sql`
   - فاتورة البيع تتحقق من Snapshot التسليم المعتمد بدل إعادة فحص مكان السيارة الحالي بعد Delivery.
   - فحص الرصيد/مكان السيارة الحي يبقى لمرحلة التجهيز فقط.

4. `20260808090250_r24_sales_fifo_alias_closure.sql`
   - أصلح alias SQL المبهم `l.id` في محرك FIFO للبيع.

5. `20260808091343_r24_partner_dual_ledger_canonical_closure.sql`
   - الصيانة والعملاء والموردون يستخدمون `erp_workflow_partner_account` كمصدر canonical لحسابي USD/IQD بدل مفاتيح JSON القديمة.

## إصلاح الصناديق والحسابات
- تم إنهاء Transaction PostgREST عالقة قديمة كانت في COMMIT وتمنع Realtime/Refresh.
- لم يعد تعديل الصندوق يشغّل scan/rebind لكل التاريخ داخل نفس Transaction.
- EBL USD مربوط بالحساب الصحيح `4b43fb7e-e239-4994-8e2a-fb08e00c691c` بدل حساب BGW USD.
- لا توجد حاليًا أي duplicate active cashbox ledger bindings.
- Reconciliation الحالي: جميع الصناديق الأربعة Difference = 0.

## اختبارات Production الحية — كلها داخل Transaction ثم ROLLBACK
لم تُترك بيانات اختبارية:

- سند قبض يدوي: PASS.
- سند صرف يدوي: PASS.
- تحويل صندوق USD إلى USD: PASS.
- تحويل صندوق USD إلى IQD: PASS.
- فاتورة الشراء PI00012: PASS، direct Supplier ↔ Inventory، والكلفة 150 USD في الاختبار.
- دفعة شراء بنفس عملة الفاتورة: PASS.
- فاتورة البيع SI00013 بعد اعتماد الشراء: PASS.
- FIFO/COGS للبيع: 150 USD، مطابق لكلفة السيارة.
- قبض بيع بنفس عملة الفاتورة: PASS.
- شراء USD مدفوع من صندوق IQD عبر FX: PASS.
- بيع USD مقبوض في صندوق IQD عبر FX: PASS.
- فاتورة صيانة USD + قبض IQD عبر FX: PASS.
- الصيانة بقيت `capitalizationApplied=false`.

## إصلاحات Flutter/UI في المصدر
- `CashboxController` يدمج refresh requests المتزامنة (`_refreshInFlight`) ويمنع notify مكرر لنفس Loading state.
- `AppLazyTabView` لا يعمل `setState` أثناء build؛ التغيير أثناء frame يؤجل إلى post-frame callback.
- Add Cash Transaction لا يغيّر اختيار الصندوق/الحساب أثناء build؛ يستخدم selected IDs مشتقة.
- جميع `DropdownButtonFormField` في `lib/` أصبحت `isExpanded: true` لإزالة RenderFlex الأفقي المعروف.
- Dropdown سلة المحذوفات الذي ظهر في Console عند `recycle_bin_page.dart` عولج صراحةً مع ellipsis.
- إعداد اللغة أصبح يحفظ ثم يطبق `AppPreferencesController.setLocale(Locale(_language))`، مع English/Arabic واتجاه الواجهة من locale النشط.
- صف اللغة/العملة أصبح Responsive باستخدام `LayoutBuilder + Wrap`.

## فحوص المصدر والعقود
- `verify:r24`: PASS.
- R8 → R24: PASS بشكل مستقل.
- PostgreSQL CREATE OR REPLACE: PASS — 1221 definitions / 683 active signatures.
- PostgreSQL UUID/text boundaries: PASS — 682 active function signatures / 154 table schemas.
- Supabase-only structure: PASS — 329 reachable Dart files، 159 literal RPC calls معرفة، 31 executable tests، 222 migrations.
- Static Dart sanity: PASS — 332 Dart files.
- Localization: PASS.
- Modular runtime architecture: PASS.

## ملاحظة البناء والنشر
بيئة التنفيذ التي أنشأت R24 لا تحتوي Flutter/Dart/Firebase CLI، لذلك لم يتم ادعاء تشغيل `flutter analyze` أو `flutter test` أو fresh Flutter web build أو Firebase Hosting deploy من هذه البيئة. سكربت R24 على Windows يبقي هذه المراحل إلزامية قبل Firebase Hosting.

Supabase R24 منشور بالفعل على Production. واجهة Flutter المعدلة تحتاج Build/Deploy إلى Firebase حتى تظهر إصلاحات الأداء/اللغة/الـOverflow للمستخدمين.
