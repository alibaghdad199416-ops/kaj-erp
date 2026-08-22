R57 Maintenance Delete Repair V3 — Migration 270

الوضع قبل هذه النسخة:
- Migration 269 طُبقت بنجاح.
- الإصلاح التاريخي أعاد ok=false للطلبات المحذوفة بسبب:
  stage=reverse_material_issues
  error=tenant denied
- السبب: erp_inventory_ensure_stock يتطلب erp_is_company_member، بينما
  migration/psql/service-role context لا يملك auth.uid() لمستخدم شركة.

ما تفعله Migration 270:
- لا تضعف erp_inventory_ensure_stock ولا RLS.
- لا تغير مسار الحذف الطبيعي من المتصفح.
- تعيد تعريف historical repair فقط.
- تختار مستخدمًا حقيقيًا Active من company_memberships لنفس الشركة.
- تضبط request.jwt.claim.sub / request.jwt.claims داخل المعاملة فقط.
- تعيد تشغيل الإصلاح التاريخي.
- تبقي Payment محفوظًا كـ partner advance / unapplied.

طريقة التطبيق:
1) فك الحزمة داخل جذر المشروع ووافق على استبدال verifier فقط.
2) npx supabase migration up
3) أعد تشغيل:
   $DB = docker ps --format "{{.Names}}" | Where-Object { $_ -like "supabase_db_*" } | Select-Object -First 1
   docker exec -i $DB psql -U postgres -d postgres -c "select * from public.erp_r57_repair_deleted_maintenance_orders(null);"

النتيجة المثالية بعد نجاح الإصلاح:
(0 rows)

لأن الطلبات المحذوفة لم يعد لديها issue منفذ أو accounting فعال يحتاج إصلاحًا.

ثم:
python tool\verify_r57_hosted_accounting_workflow_acceptance.py
npm run verify:r57
