-- Quality Line ERP 17.77.0: comprehensive testing and production-readiness diagnostics.
create or replace function public.erp_testing_readiness()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rls_tables integer;
  v_public_tables integer;
  v_missing_rls integer;
  v_audit_exists boolean;
  v_permissions_exists boolean;
  v_backup_exists boolean;
begin
  select count(*) into v_public_tables
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r';

  select count(*) into v_rls_tables
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity;

  select count(*) into v_missing_rls
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r'
    and exists (
      select 1 from information_schema.columns col
      where col.table_schema = 'public' and col.table_name = c.relname
        and col.column_name = 'company_id'
    )
    and not c.relrowsecurity;

  v_audit_exists := to_regclass('public.erp_audit_log') is not null;
  v_permissions_exists := to_regclass('public.erp_permission_roles') is not null;
  v_backup_exists := to_regclass('public.erp_backup_snapshots') is not null;

  return jsonb_build_object(
    'checked_at', now(),
    'public_tables', v_public_tables,
    'rls_tables', v_rls_tables,
    'tenant_tables_without_rls', v_missing_rls,
    'audit_ready', v_audit_exists,
    'permissions_ready', v_permissions_exists,
    'backup_ready', v_backup_exists,
    'ready', v_missing_rls = 0 and v_audit_exists and v_permissions_exists and v_backup_exists
  );
end;
$$;

revoke all on function public.erp_testing_readiness() from public;
grant execute on function public.erp_testing_readiness() to authenticated;
