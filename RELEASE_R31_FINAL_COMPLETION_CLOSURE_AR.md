# R31 Final Completion Closure

- إزالة آخر fallback لتاريخ 1970 من Car/Product Asset History؛ التاريخ غير المتوفر يظهر كشرطة بدل تاريخ وهمي.
- زيادة مساحة بطاقات Warehouses / Customers / Suppliers ومحدد مواد الصيانة لتقليل RenderFlex المؤقت عند تغير اللغة أو القياس.
- تحديث Web release token إلى R31 لمنع Cache النسخ السابقة.
- جعل deploy:production يشير إلى R31 مع الاحتفاظ بكل بوابات R28-R30 السابقة.
- لا تغيير على dart_defines.json أو أهداف Supabase/Firebase.
