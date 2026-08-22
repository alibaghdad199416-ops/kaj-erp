# Fresh local Supabase installation

The supported clean-room database verification command is:

```powershell
npm run verify:fresh-db
```

Run it from the repository root with Docker available. The command creates a uniquely named disposable **local** Supabase stack, replays the complete authoritative migration directory, runs final-state and R50-R52 runtime security tests, runs schema lint, and removes only that validated disposable stack. Any failure produces a nonzero exit code.

## Canonical pre-R37 dependency repair

Historical migration R37 references `public.erp_r35_cloud_command(text, text, jsonb)` before the timestamped canonical R35 migration creates it. Applied historical migrations remain immutable. The forward repair `20260809124735_r57_pre_r37_cloud_command_dependency.sql` is a newly introduced, previously unapplied migration ordered immediately before R37. It conditionally creates the exact fail-closed parser dependency only when the function is absent.

The compatibility function has only the exact required signature and return type. It is `SECURITY INVOKER`, has a fixed `search_path`, grants no browser or service role execution, and always raises an error if called. Existing databases where the canonical function already exists are unchanged. During fresh replay the later canonical R35 migration replaces the placeholder.

`tool/verify_fresh_database.ps1` now replays only the authoritative migration directory; it injects no hidden pre-migration SQL. After replay, `supabase/tests/verify_fresh_install_final_state.sql` proves that the placeholder is absent and that the active function has the canonical SQL body, `SECURITY DEFINER` setting, fixed `search_path`, and canonical privileges. `supabase/tests/verify_r50_r52_runtime.sql` then exercises the affected runtime and tenant/permission denial paths.

## Existing-database R57 reconciliation

An existing database can already contain migrations through `20260812153000` while lacking the newly introduced older version `20260809124735`. Ordinary Supabase push correctly refuses that out-of-order gap. Use the repository command `npm run db:push`; `tool/guarded_supabase_db_push.py` inspects migration history and keeps normal chronological push as the default.

Only when `20260809124735` is the sole missing migration older than the latest applied version does the guard run a bounded `--include-all` dry-run. The preview must contain that exact compatibility migration and only legitimate newer migrations. Any other historical gap aborts before mutation. The compatibility migration executes as a safe no-op over the existing canonical function, after which later deployments return to ordinary push automatically.

Never use `--include-all` directly or use `migration repair` for this case. Repair would mark history without proving that the migration executed.

## Production prohibition

This workflow is for disposable local Docker state only. It must never be used as a remote migration or production bootstrap. The orchestrator rejects the authoritative production ref `havlqebmnjdcwmpaaqew`, rejects non-local Supabase/database environment URLs, uses only CLI `--local` operations, validates the Docker project label before SQL execution, and scopes cleanup to its generated project ID and temporary directory.

Do not add `--linked`, `--db-url`, `db push`, `migration repair`, or remote reset behavior to this workflow. Production migration application remains a separate, explicitly authorized deployment operation.
