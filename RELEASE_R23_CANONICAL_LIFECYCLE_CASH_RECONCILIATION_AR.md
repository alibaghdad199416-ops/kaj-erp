# Quality Line ERP — R23

R23 يبني فوق R22 ولا يغيّر `dart_defines.json` أو أهداف Production.

## الإصلاحات

- دورة السيارة التشغيلية أصبحت مشتقة من المستندات الحالية والـtombstones، ولا تعتمد على نصوص `status` القديمة لاتخاذ قرار Purchase/Sale.
- `erp_r22_phase26_cloud_command` أصبح توقيع PostgREST واحدًا: `(text,text,jsonb)` مع صلاحية `authenticated` وإعادة تحميل schema.
- حساب الصندوق الحالي يوحَّد بين `account_id` و`accountId` لمنع رجوع الارتباط القديم بعد الحفظ.
- Cashbox/GL reconciliation يستخدم الحساب الحالي فقط.
- إعادة الربط التاريخية تعتمد على Cash Transaction ID، ثم Transfer ID + جهة التحويل + Cashbox/current ledger. المبلغ للتحقق بعد إثبات الهوية فقط.
- المصالحة تستخدم `FOR UPDATE SKIP LOCKED` حتى لا تعلق Production عند وجود معاملة نشطة.
- Purchase accounting المباشر وSales/FIFO accounting في R22 لم يتم تغييرهما.

## التحقق

```powershell
npm run verify:r23
npm run verify:database
npm run verify:structure
npm run validate:r23:workspace
```

## النشر

```powershell
npm run deploy:r23:production
```

النشر يرفض أي migration غير متوقعة، وSupabase يبقى Backend الوحيد بينما Firebase Hosting فقط للواجهة.

## حالة Production

تم تطبيق migrations الخاصة بـR23 على Supabase Production والتحقق الحي من Purchase للسيارة داخل `ROLLBACK`، وPhase26 health check، ومصالحة الصناديق. فروقات الصناديق الأربعة أصبحت `0`.

لم يتم نشر Firebase Hosting من هذه البيئة لأن Flutter/Dart SDK وFirebase CLI غير متاحين فيها. لم يتغير أي Dart runtime في R23؛ لذلك الواجهة المنشورة R22 متوافقة فوراً مع إصلاحات Supabase المطبقة. سكربت `deploy:r23:production` يبقي analyze/test/fresh web build إلزامية قبل أي نشر Hosting لاحق.
