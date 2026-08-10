# R47 — إغلاق تبعيات وقت التشغيل في الإنتاج

يحافظ هذا الإصدار على حدود R46: القيود المحاسبية التجارية عند اعتماد الفاتورة، وليس عند اعتماد الأمر.

ويصلح أخطاء Production التي كشفها `supabase db lint --linked`:

- استعادة `erp_deterministic_uuid(text)` المطلوبة لتسوية عملة فاتورة الشراء.
- توجيه `erp_transfer_cloud_cash` التاريخية إلى محرك R22 المعتمد بدل helper مفقود.
- استبدال `jsonb_object_length` غير المتاحة بعدّ مفاتيح JSONB.
- إصلاح تعارض اسم record/alias في `erp_v66_reverse_maintenance_stock`.

لا يعيد هذا الإصدار المحاسبة إلى Order Approval أو Receipt/Delivery/Maintenance issue.
