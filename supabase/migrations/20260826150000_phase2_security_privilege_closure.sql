begin;

-- Phase 2 security closure. Client roles must not directly mutate ERP state,
-- inspect server-maintained notification delivery state, or execute privileged
-- command surfaces anonymously. All business writes remain behind controlled
-- RPCs and their authorization checks.

-- Server-maintained notification state is fail-closed and forced through RLS.
alter table public.erp_notification_user_states enable row level security;
alter table public.erp_notification_user_states force row level security;
drop policy if exists erp_notification_user_states_client_deny on public.erp_notification_user_states;
create policy erp_notification_user_states_client_deny
  on public.erp_notification_user_states
  for all to anon, authenticated
  using (false)
  with check (false);
revoke all on public.erp_notification_user_states from public, anon, authenticated;

-- Internal audit and document-processing state is also forced through RLS.
alter table public.erp_audit_log enable row level security;
alter table public.erp_audit_log force row level security;
alter table public.erp_document_processing_jobs enable row level security;
alter table public.erp_document_processing_jobs force row level security;

-- Remove direct client-side DML from every public application table. This is
-- intentionally catalog-driven so future tables cannot silently retain the
-- default PostgREST write surface.
do $$
declare
  r record;
begin
  for r in
    select format('%I.%I', n.nspname, c.relname) as qualified_name
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r','p')
      and c.relname not like 'supabase_%'
      and c.relname <> 'schema_migrations'
  loop
    execute format(
      'revoke insert, update, delete on table %s from public, anon, authenticated',
      r.qualified_name
    );
  end loop;
end;
$$;

-- Sensitive internal state is never a direct client read surface.
revoke select on table
  public.erp_audit_log,
  public.erp_canonical_deletion_tombstones,
  public.erp_document_processing_jobs
from public, anon, authenticated;

-- Privileged service/admin-oriented routines must not be executable by anon.
do $$
declare
  r record;
begin
  for r in
    select n.nspname as schema_name,
           p.proname as function_name,
           pg_get_function_identity_arguments(p.oid) as identity_args
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
      and (
        p.proname in (
          'erp_open_cloud_service_case',
          'erp_r9_cloud_customer_service_report',
          'erp_reject_service_stock_movement'
        )
        or p.proname ~ '(^|_)(admin|bootstrap|delete_all|purge|service|superuser)($|_)'
      )
  loop
    execute format(
      'revoke execute on function %I.%I(%s) from public, anon',
      r.schema_name,
      r.function_name,
      r.identity_args
    );
  end loop;
end;
$$;

commit;
