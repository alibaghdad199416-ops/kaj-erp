# Quality Line ERP — R39 Canonical Acceptance

أكمل R39 فجوات ظهرت بعد مراجعة R38 نفسها:

- إصلاح Product Details DataTable الذي كان يستخدم `const` مع `context.l10n` ويهدد التجميع.
- توحيد إنشاء وتعديل الصيانة على عقود R39 canonical.
- قبول معرف السيارة الأساسي أو aliases التاريخية في إنشاء الصيانة.
- دعم تعديل صيانة labor-only بدون قطع غيار، مع حذف القطع السابقة عند التحويل إلى labor-only.
- الحفاظ على مرحلة Workflow والدفعات عند تعديل أمر صيانة مرتبط.
- Migration Production: `20260809161514_r39_canonical_maintenance_compile_closure`.

لا توجد تغييرات على إعدادات Production.
