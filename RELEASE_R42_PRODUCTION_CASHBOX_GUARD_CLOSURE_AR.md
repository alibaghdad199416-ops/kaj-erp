# Quality Line ERP — R42 Production Cashbox Guard Closure

التاريخ: 2026-08-09

## سبب الإصدار
كشف الفحص الحي على Production أن EBL USD وEBL IQD كانا قد عادا إلى حسابي BGW عبر مسار كتابة Legacy رغم أن RPC الحفظ الحديثة كانت تتحقق من الحساب. لذلك تم نقل الحماية من مستوى RPC فقط إلى مستوى جدول `erp_cash_accounts` نفسه.

## الإصلاحات
- إعادة EBL USD إلى حسابه Asset USD ذي الكود `1102`.
- إعادة EBL IQD إلى حسابه Asset IQD ذي الكود `1110`.
- توحيد `accountId`, `account_id`, `canonical`, `ledgerAccountId` على قيمة واحدة.
- `erp_r23_cashbox_ledger_account_id` أصبح يفضل `canonical`.
- Trigger `trg_r42_cashbox_before_write_guard` يعمل على INSERT/UPDATE لكل write path.
- التحقق من أن الحساب موجود وفعال ونوعه `asset` وعملته مطابقة تمامًا لعملة الصندوق.
- منع ربط Ledger فعال بأكثر من Cashbox فعال في نفس الشركة.
- Unique index `erp_cash_account_ledger_company_uq` للحماية من السباق بين الكتابات المتزامنة.
- Flutter يستخدم `erp_r42_list_cash_accounts` و`erp_r42_save_cash_account`.
- Model يكتب ويقرأ جميع aliases canonical.
- RPC فحص: `erp_r42_cashbox_guard_health`.

## Production
Migration المسجلة فعليًا:
`20260809170859 r42_production_cashbox_guard_closure`

الحالة بعد الإصلاح:
- EBL USD -> code 1102 -> `4b43fb7e-e239-4994-8e2a-fb08e00c691c`
- EBL IQD -> code 1110 -> `a713e3b8-a44b-4225-a08e-5f8afa90d565`
- `duplicateActiveLedgerBindings = 0`
- `problemCount = 0`
- `healthy = true`

تم اختبار محاولة Legacy لكتابة `accountId=acc-1100` وحده؛ أعادت القاعدة القيمة canonical الصحيحة تلقائيًا. وتم اختبار محاولة تغيير جميع aliases إلى `acc-1100` فتم رفضها بـ `cashbox_ledger_account_already_bound:acc-1100`.

## ملاحظة Flutter
هذه البيئة لا تحتوي Flutter/Dart SDK. لذلك يجب تشغيل `flutter analyze`, `flutter test`, وWeb runtime على جهاز Windows قبل Firebase deploy.
