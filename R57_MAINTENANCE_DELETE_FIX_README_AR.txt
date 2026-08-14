R57 Maintenance Delete / Reverse Integrity Fix

انسخ محتويات هذا ZIP إلى جذر المشروع:
C:\Projects\Quality-Line-ERP-R49-FOCUSED-FINAL-COMPLETION

الملفات:
- supabase/migrations/20260813004000_r57_maintenance_delete_reversal_integrity.sql
- supabase/tests/verify_r57_maintenance_delete_reversal_integrity.sql
- tool/verify_r57_hosted_accounting_workflow_acceptance.py

بعد النسخ:
1) npx supabase status
2) npx supabase migration up
3) python tool\verify_r57_hosted_accounting_workflow_acceptance.py
4) npm run verify:r57

لا تستخدم db reset.
لا تستخدم db push أو أي Remote deployment.

Browser acceptance:
- أنشئ أمر صيانة جديد وصرف من مخزنين.
- صدّق الفاتورة وسجل دفعة.
- احذف أمر الصيانة.
- يجب أن تعود الكميات إلى كل مخزنها الصحيح.
- يجب أن تختفي قيود فاتورة الصيانة/ذمة العميل الناتجة عن الفاتورة.
- يجب أن تبقى الدفعة المالية في الحسابات/الصندوق كـ customer unapplied credit / partner_advance.
- حذف الدفعة نفسها يتم يدويًا من الحسابات/الصندوق فقط.

المigration يحتوي أيضًا إصلاحًا لمرة واحدة للأوامر المحذوفة سابقًا التي بقيت لها R57 issue events أو قيود فاتورة فعالة.
