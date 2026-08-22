# Quality Line ERP — R49 Focused Final Completion

Premium bilingual Flutter Web ERP for automotive, spare-parts, inventory, sales, purchases, maintenance, CRM, accounting, cashboxes and multi-currency workflows.

- **Backend:** Supabase PostgreSQL/Auth/RPC/Realtime.
- **Hosting:** Firebase Hosting only.
- **Currencies:** USD and IQD with guarded linked-cashbox/FX workflows.
- **Languages:** English + Arabic/RTL.
- **Release:** `22.9.8+229008`, R49 focused final completion.

The current operational and deployment entry point is [`START_HERE_AR.md`](START_HERE_AR.md). The final verification report for this delivery is `R49_FOCUSED_FINAL_COMPLETION_AR.md`.

Do not replace the existing production connection files while validating this package. Production deployment is intentionally **not** performed during development.

Fresh local Supabase replay and database runtime verification:

```powershell
npm run verify:fresh-db
```

This command uses only a uniquely named disposable local Docker stack and refuses production/non-local targets. The repository-owned compatibility prelude preserves immutable historical migrations and is proven replaced by the canonical R35 implementation. See [`supabase/FRESH_INSTALL.md`](supabase/FRESH_INSTALL.md) for the architecture and safety contract.

Full workspace validation on a machine with Flutter/Dart installed:

```powershell
npm ci
flutter pub get
powershell -NoProfile -ExecutionPolicy Bypass -File tool/validate_r49_workspace.ps1
```

After validation, review the Supabase dry run before any production deployment:

```powershell
npx supabase db push --linked --dry-run
npx supabase migration list --linked
```
