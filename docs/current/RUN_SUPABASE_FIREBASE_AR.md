# دليل جاهزية Supabase Remote وFirebase Hosting

هذا المستند عقد فحص ونشر مرجعي لمشروع Quality Line ERP. الهدف المقصود هو:

`Flutter Web → Supabase havlqebmnjdcwmpaaqew → Firebase Hosting kaj-erp`

> **DO NOT EXECUTE WITHOUT EXPLICIT PRODUCTION AUTHORIZATION**
> أوامر الربط والدفع ونشر Edge Functions وFirebase أدناه مرجعية فقط. لا يجوز
> تنفيذها لمجرد تشغيل اختبارات المستودع.

## الحالة المثبتة في 2026-08-11

- Supabase CLI المقفول في المستودع: `2.109.1`، ويُشغّل عبر `npx supabase`.
- عدد الهجرات المحلية الموثوقة: **260** ملف SQL، مرتبة بالاسم/الإصدار.
- الحساب الحالي لا يملك صلاحية إدارة المشروع `havlqebmnjdcwmpaaqew`: قائمة
  المشاريع لم تعرضه، و`functions list --project-ref` أعاد HTTP 403.
- المستودع غير مرتبط حاليًا بمشروع بعيد. لذلك حالة الهجرات والوظائف البعيدة
  **BLOCKED / UNKNOWN** ولا يجوز استنتاج pending migrations دون وصول فعلي.
- إعداد الإصدار يستخدم HTTPS URL للمشروع ومفتاح `sb_publishable_` فقط. لا يوجد
  `service_role` أو `sb_secret_` في حزمة Flutter.

## Supabase Remote

### متطلبات الوصول والفحص الآمن

يلزم حساب Supabase يملك صلاحية قراءة المشروع المقصود، ثم:

```powershell
npm ci
npx supabase --version
npx supabase projects list --output json
npx supabase link --project-ref havlqebmnjdcwmpaaqew
npx supabase migration list --linked
npx supabase functions list --project-ref havlqebmnjdcwmpaaqew --output json
npx supabase db push --linked --dry-run
```

أمر `link` يغير الربط المحلي، و`db push --dry-run` لا يطبق SQL لكنه يتطلب
اعتمادًا صحيحًا. راجع أن كل ناتج يشير فقط إلى `havlqebmnjdcwmpaaqew`.

### بيان الهجرات المحلي

الدليل الكامل المادي هو `supabase/migrations/` وعدده 260. في غياب Remote
access تكون حالة **كل** ملف: Local=`YES`، Remote=`BLOCKED`، Pending=`UNKNOWN`.
آخر مجموعة ذات أولوية للإصدار، بالترتيب، هي:

| Version / file | Local | Remote | Classification / dependency |
|---|---:|---:|---|
| `20260810001000_r47_production_runtime_dependency_closure.sql` | YES | BLOCKED | historical predecessor |
| `20260810021000_r49_crm_business_reference_closure.sql` | YES | BLOCKED | forward-only after R47 |
| `20260810030000_r49_end_to_end_opportunity_lifecycle_readback.sql` | YES | BLOCKED | after R49 CRM reference |
| `20260810031000_r49_master_business_references.sql` | YES | BLOCKED | after lifecycle read-back |
| `20260810040000_r49_invoice_idempotency_quality_closure.sql` | YES | BLOCKED | after master references |
| `20260810050000_r49_installment_currency_fixed_asset_boundary.sql` | YES | BLOCKED | after invoice idempotency |
| `20260810060000_r49_product_identity_accounting_integrity.sql` | YES | BLOCKED | after installment boundary |
| `20260810070000_r49_permission_scope_integrity.sql` | YES | BLOCKED | after identity integrity |
| `20260810080000_r49_independent_delivery_search_traceability.sql` | YES | BLOCKED | after permission scope |
| `20260810090000_r49_focused_final_permission_runtime_closure.sql` | YES | BLOCKED | after search traceability |
| `20260810100000_r49_financial_subledger_currency_integrity.sql` | YES | BLOCKED | after focused closure |
| `20260810110000_r49_accounting_profit_installment_surface_closure.sql` | YES | BLOCKED | after subledger integrity |
| `20260810120139_r50_opportunity_reconciliation_tenant_guard.sql` | YES | BLOCKED | forward-only R50 security |
| `20260810144714_r51_opportunity_reconciliation_permission_bridge.sql` | YES | BLOCKED | depends on R50 |
| `20260810153311_r52_fresh_database_lint_runtime_closure.sql` | YES | BLOCKED | depends on R50/R51 |
| `20260810160000_r49_opportunity_round_trip_runtime_repair.sql` | YES | BLOCKED | after R52 by timestamp |
| `20260810192906_r49_opportunity_helper_acl_hardening.sql` | YES | BLOCKED | opportunity helper ACL hardening |
| `20260810220659_r53_maintenance_fifo_inventory_value_closure.sql` | YES | BLOCKED | forward-only R53 valuation closure |
| `20260810224144_r54_operational_inventory_valuation_timing_closure.sql` | YES | BLOCKED | forward-only R54; depends on R53 |
| `20260811084154_r55_opportunity_assignment_notifications.sql` | YES | BLOCKED | tenant-scoped Opportunity notifications |
| `20260811103921_r55_1_opportunity_terminal_state_guard.sql` | YES | BLOCKED | canonical Won/Lost semantics guard |
| `20260811113208_r55_1_sales_order_won_semantics_correction.sql` | YES | BLOCKED | latest local migration; Sales Order approval owns Opportunity Won |

عند توفر الوصول، خزّن ناتج `migration list --linked` وقارنه بكل الملفات الـ260.
لا تستخدم `migration repair` لإخفاء اختلاف. لا تدفع قبل أن يعرض dry-run فقط
الهجرات الجديدة المتوقعة وبنفس ترتيبها.

### قاعدة موجودة مقابل مشروع جديد فارغ

- قاعدة Production الموجودة ذات سجل تاريخي سليم تستقبل فقط الهجرات اللاحقة
  forward-only؛ عندئذ لا تعيد تشغيل R37/R35 القديمة ولا تواجه مشكلة bootstrap.
- compatibility prelude مطلوب فقط لإعادة بناء سلسلة المستودع على قاعدة فارغة.
  وهو harness محلي fail-closed وليس migration إنتاجية.
- إنشاء مشروع Remote جديد فارغ يتطلب بيئة staging مصرحًا بها أولًا: شغّل
  `npm run verify:fresh-db` محليًا، أنشئ prerequisite مكافئًا ومراجعًا ضمن إجراء
  bootstrap مستقل، طبّق السلسلة الكاملة، أثبت أن R35 canonical استبدله، شغّل
  اختبارات final-state/R50-R55 وadvisors، ثم وثّق baseline التاريخي. لا تنسخ
  `supabase/fresh_install/r35_cloud_command_compatibility.sql` إلى Production
  بصمت ولا تعدّل R37/R35 التاريخيتين. التفاصيل في `supabase/FRESH_INSTALL.md`.

### Edge Functions وAuth

| Function | Caller | Auth/tenant contract | Secrets/dependencies | Local status |
|---|---|---|---|---|
| `admin-create-user` | `SupabaseUserAdministrationService.createUser` | verified JWT + active membership + system admin; admin creation requires owner | platform `SUPABASE_URL`, anon/publishable compatibility key, service-role only inside Edge; Auth Admin, profiles, memberships, `erp_records` | source/static PASS; hosted E2E required |
| `admin-manage-user` | update/delete in `SupabaseUserAdministrationService` | verified JWT; same-company target; owner/admin hierarchy; self-disable/delete denied | same dependencies; update has compensating DB rollback and Auth-last ordering | source/static PASS; hosted E2E required |

`supabase/config.toml` keeps `verify_jwt = true` for both functions. The browser
sends the user session JWT; it never receives the service-role key. Deno is not
installed in the validated Windows environment and Docker Edge runtime was not
available, so authentic function mutation remains:

`EXTERNAL VERIFICATION REQUIRED — REMOTE AUTH/EDGE`

Authorized deployment order, only after migrations and security checks pass:

```powershell
# DO NOT EXECUTE WITHOUT EXPLICIT PRODUCTION AUTHORIZATION
npx supabase functions deploy admin-create-user --project-ref havlqebmnjdcwmpaaqew
npx supabase functions deploy admin-manage-user --project-ref havlqebmnjdcwmpaaqew
```

Then use a disposable non-owner test account to prove: unauthenticated denial,
cross-company denial, owner/admin hierarchy, create, edit, deactivate/reactivate,
duplicate email rollback, delete, membership/profile/ERP consistency, and that
failed updates leave Auth and database rows unchanged.

### Remote compatibility and smoke contract

| Client dependency | Expected remote object/config | Repository source | Current verification |
|---|---|---|---|
| Flutter bootstrap/Auth | project URL + publishable key; email Auth; signup disabled | `dart_defines.json`, `supabase/config.toml`, `CloudBootstrap` | local config PASS; remote BLOCKED |
| ERP reads/writes | 162 literal RPC calls and their active signatures | migrations + repository verification | local contract PASS; remote BLOCKED |
| tenant authorization | memberships, profiles, permission/RLS functions | authoritative migrations | local security gates PASS; remote advisors BLOCKED |
| documents | private `enterprise-documents` bucket and tenant/permission policies | foundation, document workflow and R49 migrations | local contract PASS; remote BLOCKED |
| Realtime | authenticated Postgres changes filtered by `company_id` | `CloudRealtimeBridge`, `CloudMasterDataService` | source PASS; remote publication BLOCKED |
| user administration | two Edge Functions above | `supabase/functions/` | source PASS; deployed inventory BLOCKED |

After authorized migration/function deployment, run database security/performance
advisors, login/logout/session restore, all principal CRUD/workflows, document
upload/download, Realtime refresh, search, PDF/Excel/print, installments,
notifications, and tenant-denial smoke tests using non-production test records.

## Firebase Hosting

The target remains `kaj-erp`; Hosting serves `build/web` with SPA rewrite to
`/index.html`. App shell, bootstrap, manifests, and `main.dart.js` are not cached
immutably; self-hosted CanvasKit is immutable. CSP permits only the required
Supabase HTTPS/WSS connections and local/static dependencies.

Pre-deploy:

```powershell
npm run verify:delivery
npm ci
flutter pub get
npm run verify:all
npm run format:check
npm run analyze
npm run test
npm run build:web
```

Authorized deploy command:

```powershell
# DO NOT EXECUTE WITHOUT EXPLICIT PRODUCTION AUTHORIZATION
npm run hosting:deploy
```

Post-deploy smoke checks: root and deep-link refresh, English/Arabic login,
session restore/logout, Supabase connectivity, no localhost requests, CanvasKit
served from Hosting, current version metadata, cache refresh, CSP console, core
CRUD/workflows, search, printing/export, and mobile/desktop responsive layouts.

No secret value belongs in this document, Flutter defines, Git history, or
Firebase Hosting output.
