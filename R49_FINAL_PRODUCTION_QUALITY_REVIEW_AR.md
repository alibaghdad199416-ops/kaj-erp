# R49 — Final Production-Quality Review

## حالة التسليم

هذه النسخة هي أفضل نسخة أمكن تنفيذها وفحصها مباشرة داخل بيئة العمل الحالية انطلاقًا من أحدث R49 ZIP في المحادثة، مع المحافظة على إصلاحات R44/R46/R47/R48/R49 السابقة وعدم تنفيذ أي نشر Production.

لا يعتمد معيار القبول هنا على Compile أو PASS منفرد؛ تمت مراجعة العقود الوظيفية والبيانات والمحاسبة والمخزون والترابط والصلاحيات والـCRM والـUI/UX والاستجابة واللغة والأداء وسلسلة التحقق معًا. أي شيء لم يمكن تشغيله فعليًا موثق صراحة في قسم القيود.

## أهم الأسباب الجذرية والإصلاحات

### 1. CRM / Opportunity

- كان Expected Value يستخدم formatter للفواصل بينما parsing القديم لم يكن متوافقًا بالكامل مع القيمة المنسقة. مسار الحفظ الحالي يستخدم `ThousandsInputFormatter.parse` في validation والحفظ.
- تحديث الفرصة كان يكتب إلى PostgreSQL ثم يبقي الكائن المحلي المرسل، ما يسمح بظهور state قديم إذا غيّر trigger أو projection قيمة على الخادم. تم تحويل update إلى canonical server read-back عبر إعادة تحميل الفرص بعد نجاح الحفظ.
- Pipeline كان يجمع Expected Value من USD وIQD في رقم واحد. تم فصل التجميع حسب العملة وعرض كل قيمة بعملتها وprecision المناسب.
- أضيفت مزامنة lifecycle forward-only تجعل Stage/Probability يعكسان Sales workflow الحقيقي بدل status شكلي فقط.
- تم الحفاظ على قاعدة إعادة استخدام أمر البيع المرتبط وعدم إنشاء Order إضافي عند إعادة فتح الفرصة.

### 2. Opportunity → Sales → Delivery → Invoice → Payment

مصادر الحقيقة بعد الإصلاح:

1. Opportunity يحتفظ بالبيانات التجارية وبالرابط إلى Sales Order.
2. Sales Order هو مصدر حالة الأمر.
3. Approved Delivery هو مصدر الحالة اللوجستية وخروج المخزون.
4. Approved Invoice هو مصدر حالة الفوترة والقيد التجاري/COGS.
5. Payment allocations/transactions هي مصدر Paid/Remaining/Payment Status.
6. `erp_sync_opportunity_sales_lifecycle` يعيد projection هذه الحالات إلى الفرصة دون جعل projection مصدر حقيقة بديلًا.

الـprojection الجديد ينتقل تقريبًا: Draft Order → Proposal، Approved/Delivery → Negotiation، Approved Invoice → Won، Fully Paid → Closed، وCancelled/Void → Lost.

### 3. المحاسبة والمخزون

تم الحفاظ على الحدود السابقة وعدم عكسها:

- Purchase Approval ≠ Stock Increase.
- Purchase Receipt = Stock Increase فقط.
- Purchase Invoice Approval = accounting owner للشراء.
- Sales Approval ≠ Stock Decrease.
- Sales Delivery = Stock Decrease فقط.
- Sales Invoice Approval = accounting/COGS owner.
- Maintenance Material Issue = inventory movement فقط.
- Maintenance Invoice Approval = billing/accounting owner.
- Payment مستقل عن Order/Invoice approval.

R46/R47/R48 ما زالت تمر بالكامل، بما في ذلك invoice-owned accounting، linked cashbox FX payment guards، ومنع Ledger Difference workarounds غير الصحيحة.

### 4. Account Codes

كان هناك مسار عرض/Parsing يستطيع معاملة Account Code كرقم. تم تثبيت الأكواد كـText identifiers دون `double.tryParse` أو rounding، بحيث يبقى مثل `1000.05` كما هو حرفيًا.

### 5. Business References

- Opportunity: `OPP0001...` من migration R49 السابقة.
- Cars: السجلات الجديدة/الفارغة تحصل على `CAR0001...` مع الحفاظ على custom legacy references.
- Inventory/Product master: السجلات ذات code الفارغ تحصل على `PRD0001...`.
- UUIDs الداخلية لم تتغير.
- لا يوجد Material master منفصل فعليًا في بنية المشروع الحالية؛ المواد/المنتجات تستخدم master المخزون نفسه، لذلك لم يتم اختراع MAT table أو عقد جديد يكرر مصدر الحقيقة.

### 6. Responsive UI / Modals

- أزيل أسلوب تصغير Canvas ثابت عبر `FittedBox` من module windows؛ المحتوى يعيد ترتيب نفسه حسب المساحة الفعلية.
- resize أصبح مستقلًا للعرض والارتفاع بدل فرض Aspect Ratio ثابت.
- أضيف `AppResponsive` المركزي لضبط dialog width/height مقابل viewport.
- تم تحويل 16 شاشة/نافذة كانت تحمل قياسات كبيرة ثابتة مباشرة إلى القياس المركزي.
- فحص R49 الحالي لا يجد أي fixed UI `width/height >= 500px` خارج launch-shell breakpoint المقصود.
- أضيف `isExpanded: true` إلى Opportunity currency/stage dropdowns بعد أن كشف R24 احتمال yellow/black overflow مع النصوص الطويلة/العربية.
- محتوى AlertDialog أصبح bounded حسب المساحة المتاحة بدل constraints غير محدودة تخفي مشكلة layout.

### 7. Localization

آخر audit فعلي:

- Dart files: 339
- Raw unlocalized UI text candidates: **0**
- Runtime-localized text literals: 375
- Arabic وEnglish ما زالا مدعومين، مع فحوص RTL/LTR/labels الحالية في gates.

يوجد 76 color literals و111 radius literals خارج الطبقة المركزية وفق static audit. هذه ليست كلها أخطاء: تشمل launch identity، status semantics، PDF/pills واستثناءات محلية. لم يتم تنفيذ استبدال آلي شامل لها دون Flutter visual runtime لأن ذلك قد يفسد visual hierarchy. تم إصلاح المشاكل المثبتة في الـlayout والاستجابة بدل مطاردة رقم audit شكليًا.

### 8. Performance

تم الحفاظ على R44 بالكامل:

- لا يوجد per-card `loadImages()` للـCar cards.
- Car list thumbnails تأتي من `erp_r44_list_car_thumbnails` فقط.
- thumbnails صغيرة ومولدة/محفوظة منفصلة عن Base64 الأصلية.
- controller يقوم batching/cache للصور المصغرة.
- refresh coalescing وlazy heavy-module behavior المحمي في verifiers الأقدم بقي سليمًا.
- Opportunity Pipeline لم يعد يحتاج قيمة إجمالية مختلطة أو recomputation مالي خاطئ.

### 9. Supabase/Firebase target وDeployment

تم اكتشاف أن عددًا من أدوات deployment/verification القديمة بقي يحمل Supabase project ref قديمًا، رغم أن ZIP الأصلي R48 نفسه مرتبط بالمشروع الجديد. تم تصحيح الأدوات النشطة إلى:

- Supabase: `havlqebmnjdcwmpaaqew`
- Firebase: `kaj-erp`

السجلات التاريخية لم تُعدّل لأنها توثّق الماضي وليست مسارات تنفيذ.

تم إنشاء `tool/deploy_r49_production.ps1` و`tool/validate_r49_workspace.ps1` وتوجيه `deploy:production` إلى R49. الـorchestrator:

- يشغّل validation/build كاملًا أولًا.
- يعمل Supabase dry-run.
- يسمح فقط بالـ3 R49 migrations المتوقعة.
- يرفض أي migration إضافية غير متوقعة.
- يدفع migrations أولًا ثم يتحقق من عدم بقاء pending migrations.
- ينشر Firebase Hosting بعد نجاح DB فقط.

**لم يتم تشغيل هذا deployment أثناء التطوير.**

## Migrations الجديدة في R49

1. `20260810021000_r49_crm_business_reference_closure.sql` — موجودة من جولة R49 السابقة: Opportunity compact reference وإغلاق CRM reference contract.
2. `20260810030000_r49_end_to_end_opportunity_lifecycle_readback.sql` — forward-only: projection موحد لـOpportunity stage/probability/status من Sales/Delivery/Invoice/Payment.
3. `20260810031000_r49_master_business_references.sql` — forward-only: CAR/PRD references للسجلات الفارغة مع locking/uniqueness وعدم تغيير UUIDs أو custom legacy references.

لم يتم تعديل أي historical applied migration.

## نتائج التحقق الفعلية

### تم تشغيلها ونجحت

- `npm run verify:final` — PASS.
- Static Dart sanity — PASS، 339 Dart files.
- Localization — PASS.
- Structure — PASS: 336 reachable source files + 3 test-only support files، 164 literal RPC calls كلها معرفة، 32 executable tests + 1 support، 241 migrations.
- PostgreSQL CREATE OR REPLACE compatibility — PASS: **1272 definitions / 716 active signatures**.
- PostgreSQL text/UUID boundary — PASS: **715 signatures / 154 table schemas**.
- `npm run verify:package` — PASS.
- `npm run verify:deployment-target` — PASS.
- `npm run audit:ui` — PASS/audit generated.
- R8…R44 compatibility gates تم تشغيلها على مراحل وإصلاح ما ظهر منها؛ بعد التحديثات النهائية R31→R49 أعيدت كذلك ونجحت، وR44/R46/R47/R48/R49 ناجحة صراحة.
- R44 — 9/9.
- R46 — 10/10.
- R47 — 6/6.
- R48 — 12/12.
- R49 — **26/26**.

`npm run verify:workspace` شُغّل أيضًا، لكنه تجاوز مهلة أداة التنفيذ بعد نجاح سلسلة `npm run verify` والجزء الأساسي من `verify:final`; لذلك لا أسجله كـPASS واحد مكتمل. المكونات نفسها شُغلت منفردة/على دفعات كما هو موضح أعلاه.

### لم يمكن تشغيلها في هذه البيئة

البيئة الحالية لا تحتوي executable باسم `flutter` ولا `dart`. لذلك **لم يتم الادعاء** بتشغيل:

- `dart format`
- `npm run format:check`
- `flutter analyze`
- `flutter test`
- `flutter build web --release`
- visual browser runtime / real 100% zoom screenshots / manual RTL-LTR visual walkthrough

`quality-gates.yml` و`validate_r49_workspace.ps1` يفرضان هذه الخطوات قبل Production deployment. هذه هي أكبر نقطة قبول متبقية خارج ما يمكن إثباته هنا.

## أوامر الفحص والتشغيل

```powershell
npm ci
flutter pub get
npm run verify:delivery
npm run format
npm run verify:all
npm run format:check
npm run analyze
npm run test
npm run build:web
```

للمعاينة المحلية بعد نجاح build، استخدم مسار التشغيل المعتاد للمشروع أو `flutter run -d chrome --dart-define-from-file=dart_defines.json` إذا كان Chrome/Flutter مثبتين.

## أوامر Supabase الجديدة — لا تنفذ إلا بعد نجاح Flutter gates

```powershell
npx supabase link --project-ref havlqebmnjdcwmpaaqew
npx supabase db push --linked --dry-run
npx supabase db push --linked --yes
npx supabase migration list --linked
```

## أوامر Firebase Hosting — بعد نجاح Supabase والتحقق النهائي

```powershell
npx firebase-tools use kaj-erp
npx firebase-tools deploy --only hosting --project kaj-erp --non-interactive
```

أو استخدم الـorchestrator الموحّد الذي ينفذ validation → Supabase → Firebase بالترتيب:

```powershell
npm run deploy:production
```

## المشاكل/القيود المتبقية فعلًا

1. لا يمكن إعلان visual/runtime acceptance الكامل داخل هذه البيئة لأن Flutter/Dart غير مثبتين؛ يجب أن يمر R49 validator على جهاز/CI يحوي Flutter 3.44.8 قبل النشر.
2. static UI audit ما زال يسجل design literals خارج tokens (76 ألوان، 111 radii). لا يوجد دليل أنها كلها عيوب، ولم يتم عمل refactor آلي واسع بلا visual runtime.
3. لا توجد قاعدة Production حية موصولة هنا لاختبار transactions فعلية ضد بيانات المستخدم؛ database/RPC/RLS correctness هنا مثبتة بالعقود والمigrations/verifiers، لا بتنفيذ production transactions.

## معيار القبول قبل Production

لا تنشر إذا فشل أي من: `verify:delivery`, `verify:all`, `format:check`, `analyze`, `test`, `build:web`. وبعد ذلك يجب إجراء walkthrough بصري/وظيفي فعلي على Zoom 100% بالعربية والإنجليزية لمسارات:

- Opportunity → Sales → Delivery → Invoice → Payment
- Purchase → Receipt → Invoice → Payment
- Maintenance → Material Issue/Work → Invoice → Payment

مع التحقق من المخزون، القيود، الصناديق/FX، refresh/read-back، responsive dialogs، loading/error/disabled/partial/completed states.
