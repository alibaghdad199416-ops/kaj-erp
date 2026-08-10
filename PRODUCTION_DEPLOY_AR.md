# نشر R14 إلى Production

استخدم فقط مسار R14 الحالي. لا تعِد تكوين `dart_defines.json` ولا Supabase/Firebase.

## تلقائي وآمن

```powershell
npm run deploy:production
```

الترتيب داخل السكربت:

1. `validate:r14:windows` بالكامل.
2. Supabase dry-run.
3. رفض أي migration غير متوقعة.
4. دفع `20260808001500_r14_runtime_rpc_invoice_root_closure.sql` إن كانت pending.
5. عرض migration list.
6. Firebase Hosting إلى `kaj-erp`.

Supabase: `havlqebmnjdcwmpaaqew`
Firebase: `kaj-erp`
Hosting: `https://kaj-erp.web.app`

Edge Functions لم تتغير في R14 ولا يعاد نشرها.
