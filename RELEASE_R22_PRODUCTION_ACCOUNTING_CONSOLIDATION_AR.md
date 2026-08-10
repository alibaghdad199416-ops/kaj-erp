# Quality Line ERP — R22 Production Accounting Consolidation

## الهدف
R22 هو إصدار توحيد محاسبي/تشغيلي بعد نجاح R21 في Production. لا يعالج عرضاً منفرداً؛ بل يغلق مصادر التباين التي ظهرت في اعتماد فواتير البيع/الشراء وفي الصناديق/General Ledger وفي آثار الإصدارات التاريخية.

## ما تم تغييره

### 1. اعتماد فواتير الشراء: Supplier ↔ Inventory مباشرة
- أضيف `erp_r22_approve_purchase_invoice` فوق عقد واحد قابل للتشخيص.
- `erp_r22_post_purchase_invoice_direct` لا يمر عبر clearing/capitalization legacy.
- قيد الشراء الجديد: Debit إلى `assetAccountId` من تعريف المنتج/السيارة، Credit إلى حساب المورد بنفس عملة الفاتورة.
- الشراء يبقى single-currency: عملة تعريف المادة يجب أن تطابق عملة الفاتورة.
- الاستلام يبقى quantity/state فقط، والفاتورة هي مالك المحاسبة والـvaluation.
- يتم إنشاء/تحديث cost layers وaverage cost في نفس اعتماد الفاتورة، بدون cost/capitalization journal ثانوي.

### 2. اعتماد المبيعات: عقد Canonical واحد
- Flutter يستدعي `erp_r22_approve_sales_invoice`.
- R22 ينفذ preflight V23.0.2/V7.6.7 ثم يدخل مباشرة إلى محرك Sales invoice-owned/FIFO المثبت.
- لا يمر العميل الجديد عبر سلسلة R14→V762→V760→V750.
- Revenue/Customer يبقيان بعملة الفاتورة، Inventory/COGS بعملة التكلفة/FIFO كما هو مطلوب.

### 3. توافق فوري مع R21 المنشورة
بعد دفع migration R22، يعاد تعريف العقود القديمة التالية لتفوض إلى R22:
- `erp_r14_approve_sales_invoice`
- `erp_r14_approve_purchase_invoice`
- `erp_v762_approve_workflow_invoice`
- `erp_approve_cloud_sales_workflow_invoice`
- `erp_approve_cloud_purchase_workflow_invoice`
- approve invoice في `erp_manage_commercial_order_component_v3`
- `erp_r9_transfer_cloud_cash` و`erp_r15_transfer_cloud_cash`

هذا يعني أن tab قديم من R21 يستفيد من إصلاح الاعتماد والتحويل بعد DB push حتى قبل اكتمال تحديث Hosting.

### 4. إعادة بناء قيود الشراء التاريخية الملوثة
- أضيف `erp_r22_normalize_legacy_purchase_invoice`.
- R15/R16 reconciliation القديم أصبح يفوض إليه بدلاً من V7.6.0 clearing/FX normalization.
- يعاد بناء **المحاسبة المشتقة فقط** من أمر/فاتورة الشراء الأصلية إلى Supplier↔Inventory.
- لا يعاد تشغيل FIFO أو valuation التاريخي؛ هذه حقائق مصدرية تبقى كما هي.
- إذا كان تاريخ المستند في فترة مغلقة، يستخدم technical period transaction-local فقط خلال نفس transaction.
- الفاتورة تحفظ `r22RetiredJournalIds` للقيود التي تم إيقافها، ويسجل Audit Log عملية rebuild.
- إذا كانت حالة تاريخية متعددة العملات أو غير قابلة للحسم، تفشل مغلقة وتبقى ظاهرة في reconciliation؛ لا يتم تعديلها عشوائياً.

### 5. Cashbox ↔ GL: هوية صريحة من لحظة التحويل
- `erp_r22_transfer_cloud_cash` يكتب `cashTransactionId` و`cashAccountId` على cash-side journal lines عند الإنشاء.
- تحويل نفس العملة ينشئ قيداً متوازناً واحداً.
- FX ينشئ source/target journals متوازنة مع clearing فقط لعملية FX، بدون Ledger Difference journal.
- `erp_r22_bind_cash_transaction_exact` لا يستخدم amount-only matching.
- الترتيب هوية transaction/journal/reference/current ledger، ويشترط مرشحاً واحداً فقط.
- 0 أو أكثر من 1 مرشح = canonical reconciliation issue، ولا يتم تعديل قيد غير مؤكد.
- `erp_r22_repair_cash_transfer` يعالج التاريخ باستخدام Transfer ID + source/target transaction + direction.

### 6. Reconciliation مستمر لكن Incremental
`erp_r22_reconcile_company_state` يعمل قبل تحميل modules عند دخول System Admin، لكنه لا يعيد full rebuild في كل login:
- R16 full canonical pass فقط عند وجود Tombstone/master/capitalization contamination.
- يعاد ربط الصناديق التي لديها difference فقط.
- يعاد فحص التحويلات التي لم تحصل بعد على `r22CanonicalCashBinding` أو لديها issue مفتوح فقط.
- بعد تنظيف الحالة تصبح logins اللاحقة خفيفة.

### 7. Accounting PostgREST namespace موحد
واجهة Accounting/Cashbox الحالية لم تعد تستدعي أي `erp_r9_*` مباشرة في repositories/pages الرئيسية. تم توفير R22 aliases للقراءة والكتابة المحاسبية، منها:
- ledger accounts
- journal lines/manual journals
- account statement / balance before
- trial balance
- receivables/payables
- partner subledger
- detailed accounting / cash flow
- expenses
- fixed assets/depreciation
- cashbox balances/reconciliation/transfers

كل R22 write alias يبقي R9 granular field-permission guards خلفه؛ تم تغيير namespace لا إزالة الصلاحيات.

### 8. حماية صلاحيات الدوال الداخلية
الدوال الداخلية التالية ليست browser-executable للمستخدم authenticated:
- `erp_r22_invoice_preflight`
- `erp_r22_post_purchase_invoice_direct`
- `erp_r22_normalize_legacy_purchase_invoice`

العميل يستدعي فقط approval/reconciliation contracts الرسمية؛ approve يتحقق من `sales.approve` أو `purchases.approve`.

## Production Readiness
R22 probe يثبت:
- R22 Phase-26
- Sales approval
- Purchase approval
- Direct purchase posting
- Historical purchase rebuild
- Cash transfer
- Cash reconciliation
- Canonical state reconciliation
- master contract health
- persistent deletion registry
- identity-safe cash reconciliation

`CANONICAL_DATA_STATE` يبقى mandatory.

## نتائج الفحص في بيئة التغليف
لا يتوفر Flutter/Dart SDK في بيئة التغليف، لذلك لم يتم الادعاء بتشغيل analyzer/test/build هنا. تم تشغيل الفحوص المتاحة:
- PostgreSQL CREATE OR REPLACE: 1193 definitions / 676 active signatures — PASS
- PostgreSQL UUID/Text boundaries: 675 signatures / 154 schemas — PASS
- Flutter RPC static contract: 159 literal calls, all defined — PASS
- migrations: 213 — PASS
- Dart static source sanity: 332 files — PASS
- R8/R9/R14/R15/R16/R17/R18/R19/R20/R21/R22 gates — PASS بعد تحديث البوابات التاريخية لقبول R22 كامتداد أقوى
- V7.4.3 → V7.6.6 specialized accounting/FX/UI gates — PASS
- production target remains Supabase `fjiaxdorunedmltgqtty`, Firebase `kaj-erp` — PASS

التحقق الحقيقي من Flutter يتم على Windows بواسطة `npm run validate:r22:windows` ويشمل analyzer + 77 tests الحالية + fresh web build.

## migration الجديدة
`20260808043000_r22_production_accounting_consolidation.sql`

بعد نجاح R21 في Production يجب أن تكون هي migration الوحيدة في dry-run.
