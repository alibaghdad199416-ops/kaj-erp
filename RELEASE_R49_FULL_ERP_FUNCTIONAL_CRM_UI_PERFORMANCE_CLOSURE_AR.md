# R49 — FULL ERP FUNCTIONAL CRM UI PERFORMANCE CLOSURE

## النطاق المنفذ على النسخة المرفوعة

تم التعامل مع ZIP المرفوع كمصدر الحقيقة، مع الحفاظ على حدود R44/R46/R47/R48 وعدم تنفيذ أي نشر إلى Supabase أو Firebase. ركز R49 على عيوب مؤكدة من الكود نفسه، وعلى تقوية عقود عدم التراجع بدل استبدال المنطق التشغيلي القائم.

## Root Cause

1. **Expected Value في الفرصة:** الحقل يستخدم `ThousandsInputFormatter` الذي ينتج نصًا مثل `12,500.00`، بينما validation والحفظ كانا يستخدمان `double.tryParse` مباشرة. النتيجة: القيمة المنسقة تفشل في parsing وقد تحفظ صفرًا. تم توحيد validation والحفظ على `ThousandsInputFormatter.parse`.
2. **بيانات CRM غير مكتملة:** Model/UI لم يكونا يحملان lifecycle stage، probability، currency، description، expected close date، win/loss reason. أضيفت عبر UI → Model → payload → read-back مع بقاء status القديم للتوافق مع business rules الحالية.
3. **Business reference للفرصة:** الواجهة كانت تولد `OPP-<timestamp>` بدل العقد 3 أحرف + 4 أرقام. أضيفت migration forward-only تنشئ `OPP0001`... لكل شركة، مع lock لمنع السباق وunique index، مع بقاء UUID هو المفتاح الداخلي.
4. **Read-back بعد إنشاء الفرصة:** controller كان يحتفظ بالنسخة المحلية فور الحفظ، ما قد يعرض projection قديمًا بعد server-side normalization. أصبح يعيد تحميل القائمة بعد insert حتى تكون الشاشة مبنية على القيمة الفعلية من الخادم.
5. **Verifier structure مع BOM:** `dart_defines.json` في الحزمة يحتوي UTF-8 BOM، بينما verifier كان يقرأه كـUTF-8 عادي ثم يفشل JSON decoding. أصبح verifier BOM-safe دون تغيير runtime config.

## Opportunity → Sales → Delivery → Invoice → Payment

- Opportunity: `erp_records` / `entity_type='opportunities'` هو مصدر بيانات CRM.
- Sales Order: `erp_sales_orders_cloud` مرتبط بـ`opportunity_id`، و`erp_r9_find_sales_order_by_opportunity` يعيد الأمر المرتبط لمنع إنشاء مسودة ثانية عند إعادة الفتح.
- Delivery: `erp_commercial_workflow_documents` / `module='sales'` / `document_type='delivery'`.
- Invoice: نفس جدول workflow مع `document_type='invoice'`.
- Payment: حالة الدفع والمبالغ ترجع من payload الفاتورة (`paidAmount`, `remainingAmount`) بعد محرك الدفع الآمن.
- Projection إلى Opportunity: `erp_sync_opportunity_sales_lifecycle` يعيد `salesOrderStatus`, `deliveryStatus`, `invoiceStatus`, `paymentStatus`, `paidAmount`, `remainingAmount` إلى الفرصة.

## قواعد التشغيل المحفوظة

- Purchase approval لا يزيد المخزون؛ Receipt approval يزيده.
- Sales approval لا ينقص المخزون؛ Delivery approval ينقصه.
- Maintenance material issue هو حركة المخزون للصيانة.
- القيد التجاري النهائي للشراء/البيع/الصيانة يبقى مملوكًا لاعتماد الفاتورة وفق R46.
- Payment مستقل عن Invoice/Order ويستمر عبر secure linked cashbox/FX chain في R48.
- R44 thumbnail optimization محفوظ، ولا توجد إعادة إلى Base64 originals أو per-card N+1 image load.

## الملفات المعدلة

- `lib/features/customer_service/models/opportunity_model.dart`
- `lib/features/customer_service/pages/add_opportunity_page.dart`
- `lib/features/customer_service/controllers/opportunities_controller.dart`
- `lib/features/settings/access/models/field_permission_catalog.dart`
- `tool/verify_supabase_only.py`
- `tool/verify_r49_full_erp_functional_crm_ui_performance_closure.py`
- `supabase/migrations/20260810021000_r49_crm_business_reference_closure.sql`
- `package.json`
- `RELEASE_R49_FULL_ERP_FUNCTIONAL_CRM_UI_PERFORMANCE_CLOSURE_AR.md`

## Migration الجديدة

`20260810021000_r49_crm_business_reference_closure.sql`

الغرض: توليد/توحيد Opportunity business reference بصيغة `OPP0001` مع uniqueness لكل tenant، مع UUID داخلي غير متغير. لا تعدل أي historical migration.

## نتائج التحقق في بيئة التنفيذ الحالية

- `npm run verify:database`: PASS — 1269 definitions / 714 active signatures، و713 active function signatures في type-boundary verification.
- `npm run verify:structure`: PASS — 335 reachable Dart files، 164 literal RPC calls، 31 executable tests، 239 migrations.
- `npm run verify:source`: PASS — 338 Dart files.
- `npm run verify:r49`: PASS — 16 gates.
- `npm run verify:r48`: PASS — 12 gates.
- `npm run verify:r47`: PASS — 6 gates.
- `npm run verify:r46`: PASS — 10 gates.
- `npm run verify:r44`: PASS — 9 gates.

### قيد بيئة التنفيذ

بيئة الحاوية الحالية لا تحتوي executable لـ`flutter` أو `dart`، لذلك لم يكن ممكنًا تشغيل `dart format` أو `flutter analyze` أو `flutter test` أو بناء Web فعليًا هنا. لم يتم إخفاء هذا القيد، ولا يُدّعى نجاح هذه الثلاثة دون تشغيلها. يجب تشغيل أوامرها أدناه محليًا قبل Production deployment.

## أوامر الفحص والتشغيل والمعاينة

```powershell
npm ci
npm run verify:database
npm run verify:structure
npm run verify:source
npm run verify:r44
npm run verify:r46
npm run verify:r47
npm run verify:r48
npm run verify:r49

dart format lib test integration_test
flutter analyze --fatal-infos --fatal-warnings
flutter test

npm run configure:production
npm run build:web
npm run run:web
```

## أوامر Supabase/Firebase — لا تنفذ إلا بعد المراجعة

```powershell
supabase migration list --linked
supabase db push --linked
npm run build:web
npx firebase-tools deploy --only hosting --project kaj-erp --non-interactive
```

## مشاكل/حدود متبقية فعلًا

- لم يتم تنفيذ اتصال حي بقاعدة Supabase الجديدة، لذلك إصلاحات invoice/user/warehouse/account persistence التي تعتمد على بيانات production أو RLS الفعلي لم تُختبر live من هذه البيئة. العقود الساكنة الحالية R46-R48 اجتازت verifiers.
- لم يتم تشغيل Flutter analyzer/tests بسبب عدم وجود Flutter/Dart في الحاوية.
- R49 يضيف Business Reference للفرص فقط في هذا التغيير؛ تعميم صيغة 7 محارف على Cars/Products/Materials يحتاج migration مستقلة بعد تدقيق numbering الحالي لكل entity لتجنب كسر مراجع مطبوعة أو قواعد موجودة.
