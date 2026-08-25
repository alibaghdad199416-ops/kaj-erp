# مراجعة وإصلاح KAJ ERP — 2026-08-26

## المرحلة الأولى

تم اكتشاف أن آخر commit على `main` استبدل `lib/main.dart` بالكامل بتطبيق تجريبي صغير، مع فقدان bootstrap والتوجيه والتهيئة الأصلية للـ ERP. تم استعادة entrypoint الصحيح من baseline R49 إلى فرع الإصلاح دون تعديل `main` مباشرة.

### Supabase blockers المكتشفة من lint المحلي المقدم

- `public.erp_document_processing_jobs` غير موجودة بينما `erp_r9_system_monitor_command` يعتمد عليها.
- dynamic SQL يبني relation باسم `public."{erp_cars,...}"` بدلاً من معالجة أسماء الجداول كلٌ على حدة في R15/R16.
- استخدام `record` غير مهيأ مع dynamic SQL في R9 master-record functions.
- `erp_r49_cloud_global_search` يشير إلى `erp_records.created_at` رغم أن العمود غير موجود.
- دوال معلنة `STABLE` تستدعي تعبيرات/دوال `VOLATILE`.
- دوال معلنة `IMMUTABLE` تستخدم تعبيرات `STABLE`.
- عدم تطابق `text` و`jsonb` في `erp_phase2_post_scrap`.
- مجموعة من المتغيرات والمعاملات غير المستخدمة.

هذه المرحلة لا تدّعي أن قاعدة البيانات أصبحت سليمة بعد؛ سيتم إصلاح كل blocker بواسطة migrations جديدة forward-only بعد تتبع الـ callers والـ schema الفعلي.

## قواعد السلامة

- لا يوجد نشر إلى Supabase أو Firebase ضمن هذه المرحلة.
- لا يوجد reset أو حذف بيانات.
- لا يتم تعديل migrations تاريخية مطبقة؛ الإصلاحات ستضاف كـ migrations جديدة.
