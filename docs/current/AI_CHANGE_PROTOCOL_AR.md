# بروتوكول تعديل المشروع بواسطة ChatGPT أو أي مطور

## المطلوب عند استلام مهمة جديدة

1. تحديد الوحدة والملفات الفعلية ذات الصلة.
2. البحث عن اختبار سلوكي موجود قبل كتابة كود جديد.
3. تحديد هل المطلوب قاعدة سلوك في Flutter أم عقدًا بنيويًا ثابتًا داخل `tool/`.
4. عدم نسخ صفحة كاملة إذا كان التعديل ممكنًا في مكوّن مشترك.
5. عدم إضافة Service أو Repository مكرر.
6. عدم إنشاء Migration تعيد تعريف وظائف كثيرة من دون حاجة.
7. عدم تعديل Firebase أو Supabase identifiers.
8. تشغيل البوابات بعد كل مجموعة تغييرات.

## ترتيب التنفيذ

```text
Design tokens / shared component
→ page or dialog
→ controller only if required
→ repository only if required
→ migration/RPC only if required
→ behavior tests
→ structural verification
```

## قائمة الفحص قبل التسليم

- `npm run format`
- `npm run verify`
- `npm run analyze`
- `npm run test`
- `npm run build:web`
- أو الأمر الجامع للإصدار: `npm run check:release`

## قواعد الاختبارات

- اختبار Flutter يجب أن يختبر نتيجة أو سلوكًا قابلًا للملاحظة.
- ممنوع أن يقرأ اختبار Flutter ملفات المصدر ويبحث عن اسم متغير أو كلمة محددة.
- العقود البنيوية، مثل منع Supabase داخل Widgets أو منع دورات Imports، توضع في أدوات Python داخل `tool/`.
- عند إصلاح Bug أضف اختبارًا يعيد إنتاجه قبل الإصلاح متى كان ذلك ممكنًا.

## ممنوعات

- نص مرئي مختلط عربي/إنجليزي.
- استدعاء Supabase مباشرة من Widget أو Page.
- استيراد `app/routes.dart` من Feature؛ استخدم `AppRouteNames`.
- استعمال `service_role` في Web.
- Firebase Auth أو Firestore.
- حذف سجل مرتبط من الواجهة من دون RPC المخصص.
- حساب FIFO في الواجهة.
- الاعتماد على رقم مستند يولد محليًا إذا كان له Sequence في PostgreSQL.
- تخزين تفضيل مستخدم بمفتاح عام.
- نسيان نشر حدث التحديث بعد Mutation ناجح.

## عند تعديل الصور

- السيارة: استخدم `CarImagesRepository` و`CarImagesEditor`.
- المنتج: استخدم `erp_product_images` والواجهات الموجودة في AddInventoryPage.
- الصورة الأولى حسب `sortOrder` هي الصورة الرئيسية.
- الحذف والاستبدال وإعادة الترتيب يجب أن تحدث السجل نفسه.
