# Repository Agent Instructions

These instructions apply to the entire repository. Treat this as a production ERP: preserve data, financial correctness, authorization boundaries, and the user's existing work.

## Inspect Before Acting

- Never invent a command, path, workflow, environment value, project ID, or deployment target. Before acting, inspect the current `package.json`, `pubspec.yaml`, relevant files under `tool/`, `.github/workflows/quality-gates.yml`, `supabase/config.toml`, `firebase.json`, `.firebaserc`, and the relevant repository documentation (`README.md`, `START_HERE_AR.md`, and release/deployment notes).
- Inspect only what is relevant to the task. Read neighboring implementation and tests before changing behavior.
- Check `git status` and the relevant diffs before editing. Existing modified or untracked files are user work; do not discard, overwrite, reformat, or otherwise modify unrelated changes.
- Do not perform deployments, production configuration, remote database mutations, Git history changes, or remote-branch operations unless the user explicitly requests them and the exact target has been verified.

## Actual Project Structure

This is a Flutter Web ERP (`quality_line_erp`, Dart SDK `>=3.12.0 <4.0.0`, Flutter `>=3.44.0`) backed by Supabase and hosted on Firebase Hosting.

- `lib/main.dart`: Flutter entry point.
- `lib/app/`: application-level composition.
- `lib/core/`: shared accounting, audit, cloud, data, documents, errors, events, exporting, filtering, finance, localization, logging, media, models, notifications, performance, platform, preferences, printing, release, security, startup, testing, utilities, and widgets.
- `lib/design_system/`: shared KAJ design tokens and UI components.
- `lib/features/`: feature-oriented modules for accounting, auth, business partners, customer service/CRM, dashboard, global search, inventory, maintenance, notifications, purchases, sales, settings, and splash.
- `assets/images/`: packaged image assets declared by `pubspec.yaml`.
- `web/`: Flutter web shell, manifest, icons, bootstrap, security policy, and headers.
- `test/`: unit, widget, contract, and workflow tests, with `core/`, `features/`, and `support/` subtrees.
- `integration_test/`: Flutter integration tests.
- `supabase/migrations/`: ordered PostgreSQL migrations.
- `supabase/functions/`: Edge Functions, currently including `admin-create-user/` and `admin-manage-user/`.
- `supabase/config.toml`: local Supabase/Auth/API configuration; migrations are enabled and PostgreSQL major version is 17.
- `tool/`: Python verification/release helpers and PowerShell validation/deployment orchestration.
- `verification/`: stored verification reports; do not confuse historical reports with a current successful run.
- `firebase.json`: Firebase Hosting serves `build/web`, applies the SPA rewrite, security headers, and cache rules.
- `.github/workflows/quality-gates.yml`: authoritative CI sequence (Flutter 3.44.8, Python 3.13, Node 22).
- `docs/` and root Markdown files: audits, release records, runbooks, and current entry-point documentation.

No Android, iOS, desktop, or other Flutter platform directory is present; the repository's defined build target is web.

## Actual Commands

Run commands from the repository root. Prefer the named npm scripts because they encode repository-specific behavior.

### Setup and local web run

```powershell
npm ci
flutter pub get
npm run run:web
```

`npm run run:web` runs `flutter run -d edge --dart-define-from-file=dart_defines.json`. Do not replace committed/maintained production connection files merely to validate the package.

### Format, analyze, and test

```powershell
npm run format
npm run format:check
npm run analyze
npm run test
npm run test:coverage
```

These map respectively to Dart formatting of `lib test integration_test`, formatting verification, `flutter analyze --fatal-infos --fatal-warnings`, `flutter test`, and the expanded coverage test run. `npm run format` modifies files: review its scope first and never use it to churn unrelated user changes.

### Repository verification

```powershell
npm run verify
npm run verify:structure
npm run verify:database
npm run verify:modular-runtime
npm run verify:source
npm run verify:localization
npm run verify:package
npm run verify:deployment-target
npm run verify:delivery
npm run verify:final
npm run verify:workspace
npm run verify:all
npm run check
powershell -NoProfile -ExecutionPolicy Bypass -File tool/validate_r49_workspace.ps1
```

- `verify:workspace` is the repository's comprehensive verification chain and `verify:all` aliases it.
- `verify:final` runs the current final/RPC/accounting/source/localization/structure/database/UI audit chain.
- `verify:database` runs both PostgreSQL contract and type-boundary checks.
- `verify:delivery` verifies package sanity and the deployment target.
- `check` runs the workspace verification chain, format check, analyzer, and tests.
- Numerous release-specific `verify:v*`, `verify:r*`, and `validate:r*:workspace` scripts also exist in `package.json`; run every one applicable to the affected subsystem/release. Inspect its definition before use.

CI runs, in order: `npm run verify:delivery`, `npm ci`, `flutter pub get`, `npm run format`, `npm run verify:all`, `npm run format:check`, `npm run analyze`, `npm run test`, and `npm run build:web`.

### Web release build

```powershell
npm run build:web
```

This prepares the release, runs `flutter build web --release --no-wasm-dry-run --no-web-resources-cdn --dart-define-from-file=dart_defines.json`, prepares local CanvasKit, and verifies the web release. `npm run check:release` runs formatting, the full check, and this web build; because formatting mutates files, inspect the worktree before using it.

### Production-capable commands (do not run by default)

The repository defines `db:push`, `hosting:deploy`, `configure:production`, `deploy:production`, `deploy:supabase`, `deploy:firebase`, and release-specific `deploy:r*:production` scripts. These can mutate linked Supabase or Firebase production state. Their existence is not authorization to run them. A dry-run/list inspection documented by the repository is:

```powershell
npx supabase db push --linked --dry-run
npx supabase migration list --linked
```

Even read-oriented linked commands require confirming the intended project and available authorization first.

## Required Engineering Workflow

For every fix, follow this sequence strictly:

1. **Inspect:** examine repository state, relevant source, tests, configuration, scripts, and documentation; reproduce or characterize the issue without changing behavior.
2. **Diagnose:** identify the failing workflow, invariant, boundary, and evidence. Distinguish symptoms from causes.
3. **Root-cause:** trace the defect to its earliest correctable cause, including database/RPC contracts and cross-module effects where applicable.
4. **Implement:** make the smallest coherent change that fixes the root cause. Preserve public contracts unless the task explicitly changes them. Do not modify unrelated user work.
5. **Test:** add or update focused regression coverage and run the narrowest relevant checks first, followed by all applicable repository verification scripts.
6. **Fix:** investigate every failure; do not hide failures, weaken assertions, remove checks, or label a reproducible failure “pre-existing” without evidence and user disclosure.
7. **Retest:** rerun the failed checks and the full applicable verification set until clean.

Do not declare completion while any known, reproducible, in-scope, fixable error, warning, failing test, analyzer issue, formatting issue, verification failure, broken workflow, or security/data-integrity defect remains. Zero known fixable errors is the completion standard. If an external or environmental blocker genuinely prevents a check, report the exact command, output, impact, and what remains unverified; never represent it as passing.

Before declaring a task complete, run all applicable repository verification scripts, not only a focused test. At minimum consider `format:check`, `analyze`, `test`, `verify:workspace`/`verify:all`, relevant release-specific checks, and `build:web` when web/runtime/release behavior is affected.

## Supabase Migration and RPC Safety

- Never edit, rename, reorder, delete, squash, or rewrite an applied historical migration in `supabase/migrations/`. Correct schema or data behavior with a new forward-only migration.
- Before creating a migration, inspect existing migrations, `supabase/config.toml`, migration status, repository verification scripts, and current Supabase CLI help/version. Use the repository's installed/pinned CLI and its supported migration creation command; do not invent filenames or ordering.
- Never run `supabase db reset`, truncate tables, drop production objects/data, delete users, reseed production, or otherwise delete/reset production data merely to fix a problem. Design a non-destructive, forward-only repair and preserve auditability.
- Treat `db:push`, linked commands, SQL execution, Edge Function deployment, and production configuration as production mutations. Require explicit user authorization and verify the project reference/target and dry-run output first. Never deploy as a side effect of testing.
- Make migrations rerunnable or safely guarded where practical, transactionally safe, narrowly scoped, and compatible with existing production rows. Plan rollback/mitigation without assuming destructive reversal.
- For tables exposed through `public`/the Data API, enforce RLS and explicit least-privilege grants/policies. Never expose service-role credentials in Flutter/web code. Do not use user-editable metadata for authorization.
- For every RPC, inspect all overloads, callers, grants, RLS interaction, `search_path`, volatility, nullability, and return shape. Avoid ambiguous overloads. Revoke default `PUBLIC` execute access and grant only intended roles.
- Do not add `SECURITY DEFINER` to bypass a permission failure. Prefer invoker rights. If definer rights are genuinely necessary, use a fixed safe `search_path`, schema-qualify objects, enforce authorization inside the function, minimize privileges, and verify grants and RLS behavior.
- Preserve accounting idempotency, document/posting uniqueness, inventory invariants, and concurrency behavior. Test success, denial, duplicate/retry, invalid input, and rollback/atomicity paths.
- Validate migrations/RPCs locally or in an explicitly authorized safe environment, run database contract/type-boundary checks and relevant release checks, inspect the migration diff/list, and use database/security advisors when available before any authorized push.

## Firebase Hosting Safety

- Firebase is Hosting-only here. The configured project aliases resolve to `kaj-erp`, public output is `build/web`, and all routes rewrite to `/index.html`.
- Never run `hosting:deploy`, `deploy:firebase`, `deploy:production`, `firebase deploy`, or a release deployment script without explicit user authorization in the current task and verification of the target project.
- Build and verify locally first with `npm run build:web`. Inspect `firebase.json`, `.firebaserc`, generated `build/web`, CSP/security headers, cache rules, and deployment-target verification before an authorized deployment.
- Do not weaken CSP, security headers, SPA rewrites, or cache-busting rules as a shortcut. Verify assets and CanvasKit remain locally served as intended and that no secrets or private configuration enter `build/web`.
- Deployment and production configuration are never part of ordinary testing. Do not create preview channels, alter project aliases, or change remote Hosting state unless explicitly requested.

## Git Safety

- Begin by inspecting `git status --short` and relevant diffs. Preserve unrelated tracked, modified, staged, and untracked user files.
- Never use destructive history/worktree commands such as `git reset --hard`, destructive checkout/restore, `git clean`, force push, rebase of shared history, or branch deletion unless the user explicitly requests the exact operation and scope.
- Do not amend, squash, rewrite, commit, push, merge, tag, or modify remote branches unless explicitly requested. Never force-push production/shared branches.
- Keep changes task-scoped. Do not mass-format, normalize line endings, regenerate unrelated outputs, or “clean up” nearby code without need.
- Before handoff, review `git diff --check`, `git diff`, and `git status`; report exactly what changed and what was verified.

## ERP Verification Expectations

When relevant to the affected code, explicitly verify:

- accounting balance, double-entry/posting behavior, cashboxes, payments, settlements, rounding, idempotency, and authoritative read models;
- inventory quantities, allocations, warehouse transfers, purchase/sale/maintenance effects, lifecycle transitions, and concurrent/retry behavior;
- permissions, RLS, role/action guards, record ownership, denial paths, privileged RPCs, and admin workflows;
- USD/IQD and any supported currencies, exchange rates, currency-specific precision/rounding, linked cashbox/FX flows, formatting, and mixed-currency totals;
- English and Arabic localization, RTL/LTR direction, translated labels/errors/reports/PDFs, locale-aware numbers/dates, and absence of hard-coded user-facing strings;
- responsive UI at narrow, medium, and wide widths, overflow, dialogs, tables, navigation, keyboard/mouse behavior, loading/empty/error states, and web runtime behavior;
- every affected end-to-end workflow and its downstream accounting, inventory, audit, notification, export/printing, permission, and persistence consequences.

Focused tests are necessary but not sufficient: finish by running all applicable repository gates and retesting after every corrective change.
