-- Quality Line ERP 18.0.0
-- Restrict production health checks to operational ERP tenant tables.

begin;

create or replace function public.erp_production_release_health()
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_rls_without_policy integer;
  v_company_tables_without_rls integer;
begin
  select count(*)
  into v_rls_without_policy
  from pg_class c
  join pg_namespace n
    on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind = 'r'
    and c.relrowsecurity
    and (
      left(c.relname, 4) = 'erp_'
      or c.relname = 'company_memberships'
    )
    and not exists (
      select 1
      from pg_policy p
      where p.polrelid = c.oid
    );

  select count(*)
  into v_company_tables_without_rls
  from information_schema.columns col
  join pg_class c
    on c.relname = col.table_name
  join pg_namespace n
    on n.oid = c.relnamespace
   and n.nspname = col.table_schema
  where col.table_schema = 'public'
    and col.column_name = 'company_id'
    and c.relkind = 'r'
    and (
      left(col.table_name, 4) = 'erp_'
      or col.table_name = 'company_memberships'
    )
    and not c.relrowsecurity;

  return jsonb_build_object(
    'release', '18.0.0',
    'authProvider', 'supabase',
    'databaseProvider', 'supabase-postgresql',
    'hostingProvider', 'firebase-hosting',
    'rlsTablesWithoutPolicies', v_rls_without_policy,
    'companyTablesWithoutRls', v_company_tables_without_rls,
    'ready',
      v_rls_without_policy = 0
      and v_company_tables_without_rls = 0,
    'checkedAt', now()
  );
end;
$function$;

grant execute
on function public.erp_production_release_health()
to authenticated;

commit;
