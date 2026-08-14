-- R57: keep every retained application Realtime binding in the publication.
-- All listed tables already enforce RLS and carry a direct company_id scope.
do $$
declare
  v_table text;
begin
  if not exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) then
    raise exception 'supabase_realtime publication is required';
  end if;

  foreach v_table in array array[
    'company_memberships',
    'erp_fixed_assets',
    'erp_maintenance_orders',
    'erp_maintenance_parts',
    'erp_maintenance_payments',
    'erp_permission_roles',
    'erp_role_permission_grants',
    'erp_user_role_assignments'
  ] loop
    if to_regclass(format('public.%I', v_table)) is null then
      raise exception 'Required Realtime table public.% does not exist', v_table;
    end if;

    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = v_table
    ) then
      execute format(
        'alter publication supabase_realtime add table public.%I',
        v_table
      );
    end if;
  end loop;
end
$$;
