# Quality Line ERP 22.8.1 — Final Release Corrective Patch

إصدار تصحيحي لمرشح 22.8.0 يعالج أخطاء التحليل والبناء الظاهرة في سجل الاعتماد:

- توفيق حالات المبيعات والمشتريات مع واجهة `KajSystemState` الحالية.
- إضافة aliases مركزية لـ `warningAmber` و`pageBackground`.
- تنظيف الاستيرادات غير المستخدمة التي ظهرت في التحليل.
- معالجة ملاحظات Dart 3.12 المبلغ عنها في السجل.
- إصلاح سكربت الاعتماد ليوقف التنفيذ فور فشل أي أمر خارجي.
- تحديث الإصدار إلى `22.8.1+228001`.

يجب اعتماد الإصدار فقط بعد نجاح السكربت التالي على جهاز يحتوي Flutter SDK:

```powershell
PowerShell -ExecutionPolicy Bypass -File tool/final_release_check.ps1
```
