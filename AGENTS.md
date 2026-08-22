# Project Safety Rules

- The local workspace is the source of truth.
- Preserve all existing uncommitted changes.
- Preserve all existing untracked files.
- Never run:
  - git checkout -- .
  - git restore in any form
  - git stash in any form
  - git reset --hard
  - git clean in any form
  - supabase db reset
  - supabase db push
  - supabase link
- Do not move, rename, delete, or overwrite untracked files unless explicitly requested.
- Before running any potentially destructive command, stop and request explicit approval.
- Never delete the existing `kaj-erp-r87-*` files or `merge-kaj-r87-*.ps1` files unless explicitly requested.
- Do not connect to or modify production Supabase.
- Use local Supabase only:
  - API: http://127.0.0.1:54321
  - Studio: http://127.0.0.1:54323
- Before changing code:
  1. Inspect
  2. Diagnose
  3. Identify root cause
  4. Explain the intended files to change
  5. Then implement
  6. Test
  7. Fix
  8. Retest
- Never delete, overwrite, or revert unrelated local changes.
- Before modifying tracked files, inspect the existing implementation and related tests.
- Do not make unrelated refactors.
- Keep changes minimal and scoped to the requested issue.
- Never access or modify production services.
- Never expose or print secrets from `.env` files.
