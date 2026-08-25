# هيكلية Quality Line ERP

## الطبقات

### 1. العرض Presentation
- `lib/features/**/pages`
- `lib/features/**/widgets`
- `lib/core/widgets`
- `lib/design_system`

تعرض البيانات وتستدعي Controllers فقط. لا تتصل هذه الطبقة بـSupabase مباشرة.

### 2. إدارة الحالة Controllers
- `lib/features/**/controllers`

تحتوي على حالات التحميل والخطأ والبيانات والفلاتر، وتنسق بين الصفحة والمستودع من دون SQL أو RPC مباشر.

### 3. المستودعات Repositories
- `lib/features/**/repositories`
- `lib/features/**/data`

تحتوي على الاستعلامات وRPC والتحويل بين Map والنماذج، وتنشر حدث تغيير بعد Mutation ناجح.

### 4. النماذج Models
- `lib/features/**/models`

تحتوي على قراءة الحقول القديمة والجديدة، والتحقق من البيانات، والتحويل إلى Map. تُستخدم القراءة الدفاعية للبيانات القادمة من Supabase.

### 5. البنية المشتركة Core
- المصادقة والسحابة: `lib/core/cloud`
- أحداث التحديث: `lib/core/events`
- الصلاحيات: `lib/core/security` و`lib/core/permissions`
- الطباعة والتصدير: `lib/core/printing` و`lib/core/exporting`
- الترجمة: `lib/core/localization`
- تفضيلات المستخدم: `lib/core/preferences`

### 6. التوجيه Routing
- `lib/app/route_names.dart`: أسماء المسارات فقط.
- `lib/app/routes.dart`: بناء Routes وربطها بالصفحات.

تفصل هذه القاعدة Feature عن Router وتمنع دورات Imports.

### 7. قاعدة البيانات
- `supabase/migrations`
- `supabase/functions`

PostgreSQL هو المصدر النهائي للحقيقة في المخزون والحسابات والحذف المترابط وFIFO والصلاحيات.

## قواعد التعديل

- تعديل UI: يقتصر غالبًا على Presentation وDesign System.
- تعديل Business Rule: ينفذ في RPC/Migration وRepository مع اختبار سلوكي وعقد بنيوي عند الحاجة.
- تعديل أسماء العرض: في Localization، وليس بتغيير أعمدة قاعدة البيانات.
- تعديل المستندات المطبوعة: في Printing/Exporting مع الحفاظ على مصدر البيانات.
- تعديل Preferences: يبقى مربوطًا بـuser id، وليس مفتاحًا عامًا.
- الانتقال بين الصفحات: يستخدم `AppRouteNames` داخل Features.
- الكتابة إلى البيانات: تتم داخل Repository ويعقبها نشر حدث إلى `AppDataChangeBus`.

## نظام التصميم V4

- `lib/design_system/kaj_design_tokens.dart`: الألوان والمسافات والزوايا والظلال.
- `lib/design_system/kaj_surface.dart`: الأسطح القابلة لإعادة الاستخدام.
- `lib/design_system/kaj_section_header.dart`: رؤوس الأقسام.
- `lib/app/theme.dart`: الثيمان الداكن والفاتح.
- `lib/core/widgets/app_background.dart`: خلفية الهوية.
- `lib/core/widgets/app_launch_shell.dart`: Splash/Login/Cloud Account.
- `lib/core/widgets/app_top_navigation.dart`: القائمة العلوية والجانبية.

## حدود Supabase وFirebase

### Supabase
- Auth.
- PostgreSQL.
- RPC.
- Edge Functions الإدارية.
- Realtime عند الحاجة.

### Firebase
- Hosting فقط.
- `firebase.json` يحتوي على إعدادات الاستضافة، ولا توجد Firestore أو Firebase Auth في التطبيق.
