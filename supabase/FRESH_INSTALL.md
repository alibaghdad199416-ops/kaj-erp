# Fresh local Supabase installation

The supported clean-room database verification command is:

```powershell
npm run verify:fresh-db
```

Run it from the repository root with Docker available. The command creates a uniquely named disposable **local** Supabase stack, replays the complete authoritative migration directory, runs final-state and R50-R52 runtime security tests, runs schema lint, and removes only that validated disposable stack. Any failure produces a nonzero exit code.

## Why a compatibility bootstrap is required

Historical migration R37 references `public.erp_r35_cloud_command(text, text, jsonb)` before the timestamped canonical R35 migration creates it. Applied migration history is immutable, so the repository does not edit, rename, reorder, backdate, or repair either migration. The Supabase CLI version used here has no supported pre-migration SQL hook; therefore `tool/verify_fresh_database.ps1` temporarily applies `supabase/fresh_install/r35_cloud_command_compatibility.sql` before ordinary local migration execution.

The compatibility function has only the exact required signature and return type. It is `SECURITY INVOKER`, has a fixed `search_path`, grants no browser or service role execution, and always raises an error if called. It exists solely so the historical chain can parse. The later canonical R35 migration replaces it.

After replay, `supabase/tests/verify_fresh_install_final_state.sql` proves that the placeholder is absent and that the active function has the canonical SQL body, `SECURITY DEFINER` setting, fixed `search_path`, and canonical privileges. `supabase/tests/verify_r50_r52_runtime.sql` then exercises the affected runtime and tenant/permission denial paths.

## Production prohibition

This workflow is for disposable local Docker state only. It must never be used as a remote migration or production bootstrap. The orchestrator rejects the authoritative production ref `havlqebmnjdcwmpaaqew`, rejects non-local Supabase/database environment URLs, uses only CLI `--local` operations, validates the Docker project label before SQL execution, and scopes cleanup to its generated project ID and temporary directory.

Do not add `--linked`, `--db-url`, `db push`, `migration repair`, or remote reset behavior to this workflow. Production migration application remains a separate, explicitly authorized deployment operation.
