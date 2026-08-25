# R49 — Independent Final Audit, Failure-Resistance & Delivery Certification

التاريخ: 2026-08-10

## الحكم
أُعيدت مراجعة المشروع من منظور مستقل مع افتراض وجود خطأ مخفي. كل خلل قابل للإصلاح تم إثباته في البيئة المحلية خلال هذه الجولة أُصلح قبل الحزم. لا يُستخدم هذا التقرير لادعاء نجاح Flutter/Web أو Live Supabase عندما لم تُشغّل تلك البيئة فعليًا.

## إصلاحات الجولة الثامنة
- توحيد Release metadata بين Dart و`web/version.json` وboot fallback على R49 Final Delivery Certification.
- إضافة Opportunities إلى Global Search عبر RPC server-side جديد مع Company isolation وصلاحية CRM، ودعم Business Reference والعنوان والعميل والمرحلة والحالة.
- جعل نتائج البحث المالية Currency-aware وعدم عرض مبلغ بلا عملة موثوقة.
- ربط Search cache بـ`AppDataChangeBus` حتى تُبطل النتائج بعد تغييرات الوحدات بدل بقاء stale cache.
- منع Global Search من اختلاق `posted` لقيد ناقص الحالة.
- جعل Active flags المالية fail-closed بدل اعتبار الحساب/الصندوق صالحًا عند payload ناقص.
- تقوية Cashbox backend: Currency وActive State صريحتان، Save/Create/Update/Delete خلف صلاحيات Accounting المناسبة، ومنع حذف صندوق لديه حركات مالية.
- تحديث R9 verifier لقبول R49 canonical server-side search بدل إجبار Runtime على RPC تاريخي أقدم.
- توحيد `START_HERE_AR.md` وإزالة إرشادات R42 المتقادمة من نقطة الدخول النهائية.
- إزالة `supabase/.temp` من التسليم وإضافته إلى `.gitignore` وPackage verifier لأنه CLI-generated state وليس مصدرًا مطلوبًا للتشغيل.

## VERIFIED — تم تشغيله فعليًا
- `npm run verify:r49`: PASS — 54/54 gates.
- `npm run verify:final`: PASS.
- Static Dart sanity: 341 Dart files، imports/exports سليمة، لا merge markers.
- Localization verifier: PASS؛ النصوص العربية الثابتة المستخدمة عبر AppText/AppTranslation لها exact English entries.
- Structure: 338 reachable + 3 test-only؛ 164/164 literal RPC calls معرفة؛ 33 executable tests + support؛ 246 migrations.
- PostgreSQL CREATE/REPLACE compatibility: 1308 definitions / 728 active signatures.
- PostgreSQL UUID/Text boundaries: 727 active signatures / 154 table schemas.
- UI/localization static audit: 0 raw unlocalized UI candidates.
- Historical regression: R8 PASS، R9 PASS بعد تحديث verifier للعقد canonical، R10→R44 PASS، R46/R47/R48 PASS، R49 PASS. لا يوجد verifier مستقل R45 في package.json.
- `verify:package`: PASS.
- `verify:delivery`: PASS.
- `verify:deployment-target`: PASS؛ Supabase `havlqebmnjdcwmpaaqew` وFirebase `kaj-erp`.

ملاحظة: تشغيل `verify:workspace` كأمر واحد تجاوز مهلة أداة التنفيذ أثناء `verify:final`، لذلك لا يُسجل كـPASS اسمي. تم تشغيل مكوناته ذات الصلة منفصلة/على مجموعات بعد آخر تعديل ونجحت كما هو موضح أعلاه.

## STATICALLY VERIFIED
- Invoice-owned accounting مقابل Receipt/Delivery/Material Issue logistics boundaries محفوظة عبر R46/R48/R49 regression.
- Sales Invoice idempotency/concurrent retry guard محفوظ.
- Cashbox/FX linked-payment guards محفوظة.
- Master-data accounting resolution وحماية currency/account type/active state محفوظة.
- Multi-currency summaries/valuation لا تجمع USD وIQD في scalar مالي واحد في المسارات التي أُغلقت.
- Opportunity ↔ Sales workflow projection/read-back محفوظة، والبحث الشامل أصبح يشمل CRM.
- Permission-scope administration tenant-bound، والمرفقات تتبع صلاحيات المستند في UI/RPC/Storage.
- R44 thumbnail optimization محفوظة.
- Optimistic-concurrency infrastructure موجودة لمسارات master/cash canonical التي اعتمدها النظام؛ لم يُضف overwrite صامت جديد في هذه الجولة.

## EXTERNAL VERIFICATION REQUIRED
بيئة التنفيذ الحالية لا تحتوي Flutter/Dart SDK ولا يمكنها تنزيل Flutter لأن DNS/Internet الخارجي غير متاح. لذلك يلزم في بيئتك:

```powershell
npm ci
flutter pub get
powershell -NoProfile -ExecutionPolicy Bypass -File tool/validate_r49_workspace.ps1
```

ويجب أن ينجح فعليًا: `dart format`/format check، `flutter analyze --fatal-infos --fatal-warnings`، `flutter test`، fresh Web build.

بعدها شغّل Web على Zoom 100% واختبر العربية RTL والإنجليزية LTR، الشاشات الصغيرة، النصوص الطويلة، Empty/Loading/Error، وأهم دورات Sales/Purchase/Maintenance/FX بمستخدمين ذوي صلاحيات مختلفة.

للـLive Supabase قبل أي نشر:
```powershell
npx supabase db push --linked --dry-run
npx supabase migration list --linked
```
ثم اختبر transaction results الفعلية: Journal balance/source/currency، inventory movements/value، partial/multiple payments، retry/duplicate submit، permission denied، ومستخدمين متزامنين على نفس المستند. Security/Performance Advisors يحتاجان صلاحية المشروع الخارجية.

## BLOCKED
- Flutter analyzer/tests/web build/browser visual walkthrough داخل هذه البيئة فقط بسبب غياب SDK وعدم توفر الشبكة لتنزيله.
- Live Supabase/Firebase/Auth/production-data validation بسبب عدم توفر البيئة الخارجية/الصلاحيات هنا.

## NO KNOWN FIXABLE ERRORS REMAIN
ضمن نطاق Source/SQL/static contracts/verifiers/package/deployment metadata الذي أمكن تشغيله محليًا، لا يبقى في نهاية هذه الجولة Failure معروف ظهر في الفحص ويمكن إصلاحه داخل البيئة وترك دون إصلاح. هذه العبارة لا تعني أن Runtime/Visual/Live Integration الذي لم يُشغّل قد تم إثباته.

## النشر
لم يُنفذ Production Deployment. بعد نجاح كل اختبارات بيئتك فقط:
```powershell
npm run deploy:production
```
