# Quality Line ERP 22.9.3 — إصلاح تجميع R1

يعالج هذا التصحيح أخطاء التحليل والبناء التي ظهرت بعد حزمة الإصلاحات 04–08:

- إزالة التكرار في dialogTheme و snackBarTheme و chipTheme.
- تصحيح توقيع WorkflowOperationException.fromPostgrest في الصيانة.
- تصحيح نوع fallback في MaintenanceOrderModel.
- تأمين callback إعادة البيع nullable.
- ربط KajFinalPdfLayout فعليًا بخدمة PDF وإزالة تحذير الحقل غير المستخدم.
