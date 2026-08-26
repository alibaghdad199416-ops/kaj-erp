# Quality Line ERP — Final Cross-Stage Integrity Closure

Premium bilingual Flutter Web ERP for automotive, spare-parts, inventory, sales, purchases, maintenance, CRM, accounting, cashboxes and multi-currency workflows.

- **Backend:** Supabase PostgreSQL/Auth/RPC/Realtime.
- **Hosting:** Firebase Hosting only.
- **Currencies:** USD and IQD with guarded linked-cashbox/FX workflows.
- **Languages:** English + Arabic/RTL.
- **Release:** `22.9.8+229008` — Final Cross-Stage Integrity Closure (R57/R58/R59).

The current operational and deployment entry point is [`START_HERE_AR.md`](START_HERE_AR.md). Verification is authoritative from `npm run verify:workspace`, which includes the stage 11/12 closure verifiers and the final cross-stage integrity audit.

Do not replace the existing production connection files while validating this package. Production deployment is intentionally **not** performed during development.

Full workspace validation on a machine with Flutter/Dart installed:

```powershell
npm ci
flutter pub get
npm run verify:workspace
npm run format:check
npm run analyze
npm run test
```

Before any production deployment, review the Supabase dry run and migration list:

```powershell
npx supabase db push --linked --dry-run
npx supabase migration list --linked
```
