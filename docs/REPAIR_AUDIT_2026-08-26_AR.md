# مراجعة وإصلاح KAJ ERP — 2026-08-26

## المرحلة الأولى

تم اكتشاف أن آخر commit على `main` استبدل `lib/main.dart` بالكامل بتطبيق تجريبي صغير، مع فقدان bootstrap والتوجيه والتهيئة الأصلية للـ ERP. تم استعادة entrypoint الصحيح من baseline R49 إلى فرع الإصلاح دون تعديل `main` مباشرة.

### الأدلة
- `lib/main.dart` الحالي قبل الإصلاح كان يحتوي LoginPage/HomePage تجريبيين فقط.
- baseline R49 يحتوي bootstrap الأصلي: CloudBootstrap وCloudTenantContext وStartupCoordinator وAppDependencies وMultiProvider.
- بقية التطبيق لا تزال تحتوي الوحدات الفعلية والتوجيه والصلاحيات.

## Supabase

تم تسجيل أخطاء lint الحرجة التالية من الفحص المحلي المقدم:

- مراجع إلى `public.erp_document_processing_jobs` غير الموجودة.
- dynamic SQL يستخدم اسم relation حرفياً كـ `public."{erp_cars,...}"` بدلاً من التعامل مع كل جدول بشكل منفصل.
- سجلات `record` غير مهيأة في دوال تعتمد على dynamic SQL.
- `erp_r49_cloud_global_search` يشير إلى `erp_records.created_at` غير الموجود.
- عدة دوال معلنة `STABLE` تستدعي تعبيرات/دوال `VOLATILE`.
- دوال معلنة `IMMUTABLE` تستخدم تعبيرات `STABLE`.
- عدم تطابق نوع `text` مع `jsonb` في `erp_phase2_post_scrap`.
- مجموعة كبيرة من المتغيرات/المعاملات غير المستخدمة.

هذه المرحلة لا تدّعي أن قاعدة البيانات أصبحت سليمة بعد؛ سيتم إصلاح كل blocker بواسطة migrations جديدة forward-only بعد تتبع الـ callers والـ schema الفعلي.

## قواعد السلامة

- لا يوجد نشر إلى Supabase أو Firebase ضمن هذه المرحلة.
- لا يوجد reset أو حذف بيانات.
- لا يتم تعديل migrations تاريخية مطبقة؛ الإصلاحات ستضاف كـ migrations جديدة.
