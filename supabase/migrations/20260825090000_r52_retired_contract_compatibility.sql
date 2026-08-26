begin;

-- Forward-only compatibility repair for the ordered migration chain.
-- 20260728001200 intentionally retired the legacy contract module and archived
-- its tables, but 20260826003000_r52_full_integrity_closure still uses the
-- retired erp_contracts shape as a source for document-processing jobs.
-- Recreate only that schema-compatible source so the migration chain is
-- replayable. The table is not a supported client/runtime contract surface.
create table if not exists public.erp_contracts (
  company_id uuid not null,
  id uuid not null,
  data jsonb not null default '{}'::jsonb,
  is_deleted boolean not null default false,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(company_id,id)
);

alter table public.erp_contracts enable row level security;
revoke all on public.erp_contracts from public, anon, authenticated;
drop policy if exists erp_contracts_compatibility_client_deny on public.erp_contracts;
create policy erp_contracts_compatibility_client_deny
  on public.erp_contracts
  for all to anon, authenticated
  using (false)
  with check (false);

comment on table public.erp_contracts is
  'Migration compatibility source only. The legacy contract module was retired by 20260728001200; document processing jobs use this schema shape during replay.';

commit;
