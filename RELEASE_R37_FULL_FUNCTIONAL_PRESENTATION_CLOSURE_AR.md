# Quality Line ERP — R37 Full Functional & Presentation Closure

هذا الإصدار يغلق جولة التشغيل الأخيرة الخاصة بضغط بطاقات السيارات/المواد/المخازن/الشركاء، تفاصيل وتعديل المنتج، Product History وMovement Log مع Excel/PDF منظم باللغة الإنجليزية، Excel لسلة المهملات، تصدير الفرص التجارية، تحسين تفاصيل أوامر البيع والشراء، إصلاح الربط الثنائي الاتجاه بين الفرصة وأمر البيع، وتحسين مسار الصيانة.

## Backend Production
تم نشر عقدي R37 على Supabase Production:
- `20260809124736_r37_full_functional_presentation_closure`
- `20260809125507_r37_maintenance_labor_only_closure`

R37 يستخدم `erp_r37_cloud_command` بدل العقود القديمة، ويستخدم `erp_r37_create_cloud_maintenance_order` الذي يسمح بصيانة أجور/خدمة فقط بدون اشتراط قطع غيار. التصديق يستخدم `erp_r37_advance_maintenance_workflow`.

## الفرصة التجارية
المصالحة أصبحت تدعم `salesOrderId` و`saleId` في الفرصة وتعيد ربط `sales_orders_cloud.opportunity_id` ثم تشغل المزامنة canonical لدورة Delivery/Invoice/Payment.

## التحقق
نجحت بوابات R34→R37، عقود PostgreSQL، Type Boundaries، Supabase RPC graph، Static Dart sanity، Localization، Package sanity وProduction target.

ملاحظة: يجب تشغيل Flutter analyzer/tests/runtime على جهاز العمل قبل Firebase لأن SDK غير متوفر في بيئة إعداد الحزمة.
