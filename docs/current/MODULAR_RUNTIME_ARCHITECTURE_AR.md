# معمارية التشغيل المعيارية — Quality Line ERP

تاريخ الاعتماد: 4 أغسطس 2026

## الهدف

تمنع هذه المعمارية أن يؤدي تعديل موديل أو إضافة متطلب إلى سلسلة أخطاء في `main.dart` أو إلى نجاح الحفظ في Supabase مع بقاء الشاشة على بيانات قديمة. كل وحدة تعلن تبعياتها، وكل كتابة تنشر حدثًا موحدًا، وتبقى الواجهة منفصلة عن قاعدة البيانات.

## حدود كل منصة

- **Flutter Web:** واجهة التطبيق ومنطق العرض، مع دعم المتصفحات الحديثة.
- **Supabase:** تسجيل الدخول، عضوية الشركة، PostgreSQL، RPC، التخزين وRealtime.
- **Firebase Hosting:** استضافة ملفات Web الناتجة فقط.
- **اللغة:** الإنجليزية هي اللغة الافتراضية الأولى، والعربية لغة ثانية كاملة مع RTL، ويُحفظ اختيار كل مستخدم بصورة مستقلة.

## تدفق التطبيق

```text
main.dart
  └── AppDependencies (Composition Root)
        ├── جميع Controllers/Providers طويلة العمر
        ├── AppDataRefreshCoordinator
        └── ErpRuntimeCapabilitiesController

Repository/RPC ناجح أو Supabase Realtime
  └── AppDataChangeBus.publish(source, operation)
        └── AppDataRefreshCoordinator
              ├── يجمع الأحداث المتقاربة Debounce
              ├── يمنع تشغيل تحديثين متوازيين للوحدة نفسها
              ├── يعيد التشغيل إذا وصل حدث أثناء التحديث
              └── يحدّث الوحدات التابعة فقط مع إبطال الكاش

تسجيل الدخول
  └── AuthenticatedDataLoader
        └── erp_operational_readiness RPC
              └── AppModuleShell يعرض المتطلبات الناقصة بدل الفشل الصامت
```

## الملفات المركزية

- `lib/main.dart`: Bootstrap وتشغيل التطبيق فقط.
- `lib/app/bootstrap/app_dependencies.dart`: سجل Controllers وProviders وقواعد التحديث.
- `lib/app/route_names.dart`: ثوابت المسارات فقط، من دون استيراد صفحات أو Flutter Router.
- `lib/app/routes.dart`: بناء المسارات وربطها بالصفحات.
- `lib/core/events/app_data_refresh_coordinator.dart`: تنسيق تحديث البيانات.
- `lib/core/events/app_data_change_bus.dart`: قناة أحداث العمليات المحلية وRealtime.
- `lib/core/cloud/cloud_realtime_bridge.dart`: ربط جداول Supabase بمصادر الأحداث.
- `lib/core/cloud/erp_runtime_capabilities_controller.dart`: جاهزية متطلبات كل مسار.
- `lib/core/models/model_value_reader.dart`: قراءة آمنة لقيم Supabase ودعم `snake_case` و`camelCase`.
- `supabase/migrations/20260804090000_modular_runtime_readiness.sql`: فحص جاهزية الوحدات.

## حدود الطبقات

```text
Page / Widget
  → Controller
    → Repository
      → Supabase / RPC
```

- الصفحة لا تستورد `supabase_flutter` ولا تنفذ RPC أو Query مباشرة.
- Repository مسؤول عن القراءة والكتابة والتحويل ونشر حدث التغيير بعد نجاح Mutation.
- Controller مسؤول عن حالة العرض فقط: loading/data/error/filter.
- القواعد المحاسبية والمخزنية النهائية تبقى داخل PostgreSQL/RPC.

## طريقة تعديل موديل موجود

1. عدّل الموديل وRepository/RPC معًا؛ لا تغيّر اسم حقل في جهة واحدة فقط.
2. استخدم `ModelValueReader` داخل `fromMap` بدل التحويلات الهشة:

```dart
id: ModelValueReader.string(map, 'id'),
amount: ModelValueReader.decimal(map, 'amount'),
createdAt: ModelValueReader.dateTime(map, 'createdAt'),
```

3. عند تغيير اسم حقل، اترك Alias انتقاليًا:

```dart
ModelValueReader.string(
  map,
  'customerName',
  aliases: const <String>['clientName'],
)
```

4. أضف Migration جديدة فقط؛ لا تعدّل Migration سبق تطبيقها.
5. أضف اختبار تحويل وسلوك يغطي القيم الناقصة والنصية/الرقمية والأسماء القديمة والجديدة.
6. شغّل `npm run check`، ولإصدار الإنتاج شغّل `npm run check:release`.

## طريقة إضافة وحدة جديدة

1. أنشئ `lib/features/<module>/` مع `models`, `repositories`, `controllers`, `pages` حسب الحاجة.
2. سجّل Controller طويل العمر داخل `AppDependencies.create()` و`providers`. Controller الخاص بصفحة واحدة يمكن أن يبقى محليًا ويجب أن يكون واضحًا للبوابة المعمارية.
3. أضف `AppDataRefreshRule` باسم فريد وحدد مصادر البيانات التي تبطل الوحدة.
4. انشر حدث التغيير داخل Repository بعد نجاح الكتابة:

```dart
AppDataChangeBus.instance.publish(
  source: 'module_source',
  operation: 'create',
);
```

5. أضف جداول Realtime إلى `cloud_realtime_bridge.dart` عندما يمكن أن يأتي التغيير من مستخدم أو جهاز آخر.
6. أضف متطلب الوحدة إلى RPC الجاهزية وخريطة المسارات في `ErpRuntimeCapabilitiesController`.
7. استخدم `AppRouteNames` عند الانتقال، ولا تستورد `app/routes.dart` من Feature.
8. أضف اختبار Flutter للسلوك، وأضف قاعدة Python فقط إذا كان المطلوب عقدًا بنيويًا دائمًا.

## قواعد تمنع رجوع المشكلة

- ممنوع استيراد Feature Controllers داخل `main.dart`.
- ممنوع استدعاء Supabase مباشرة من `pages` أو `widgets`.
- ممنوع تحديث Controllers أخرى يدويًا من الصفحة؛ Repository ينشر حدث بيانات.
- ممنوع ترك مصدر Mutation أو Realtime بلا مستهلك تحديث.
- ممنوع الاعتماد على Cache بعد الكتابة.
- ممنوع استخدام `map['x'] as String` مع بيانات Supabase المتغيرة.
- ممنوع إنشاء دورة Imports؛ بوابة التحقق تفشل تلقائيًا عند وجودها.
- الحدث `source: 'all'` مخصص للعمليات التي تبطل النظام كله، مثل استعادة النسخة الاحتياطية.
- نقص Migration أو جدول يظهر كتوضيح داخل الوحدة، لا كصفحة فارغة.
- اختبارات Flutter تختبر السلوك؛ فحص النصوص والبنية الثابتة يبقى داخل `tool/`.

## أوامر التحقق والتشغيل

```powershell
flutter pub get
npm ci
npm run format
npm run check
npm run check:release
npx supabase db push --linked
firebase deploy --only hosting
```

يُطبّق Migration على Supabase قبل نشر Web، ثم تُبنى النسخة وتُنشر إلى Firebase Hosting.
