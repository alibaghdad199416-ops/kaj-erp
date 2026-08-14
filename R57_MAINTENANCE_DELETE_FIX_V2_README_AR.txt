R57 Maintenance Delete Fix V2

سبب هذه النسخة:
- Migration 269 السابقة وصلت إلى statement 5 (one-time historical repair) وفشلت.
- النسخة V2 لا تسمح لسجل تاريخي غير متناسق بإسقاط migration بالكامل.
- كل أمر محذوف يُصلح داخل subtransaction مستقل.
- عند الفشل ترجع الدالة المرحلة وSQLSTATE والخطأ الحقيقي.
- الدفع يبقى محفوظًا كـ partner_advance / unapplied.
- عكس FIFO والمخزون أصبح يتحمل حالة historical partial repair بحيث يُصلح كل جانب بصورة مستقلة مع fail-closed إذا تجاوز الكمية الأصلية للـissue event.

استبدل الملفين داخل جذر المشروع:
supabase/migrations/20260813004000_r57_maintenance_delete_reversal_integrity.sql
tool/verify_r57_hosted_accounting_workflow_acceptance.py

ثم:
npx supabase migration up

بعد النجاح شغّل:
$DB = docker ps --format "{{.Names}}" | Where-Object { $_ -like "supabase_db_*" } | Select-Object -First 1
docker exec -i $DB psql -U postgres -d postgres -c "select * from public.erp_r57_repair_deleted_maintenance_orders(null);"

إذا كانت النتيجة ok=true فالإصلاح التاريخي نجح.
إذا كانت ok=false أرسل JSON الناتج كما هو.
