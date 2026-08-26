begin;

-- Phase 2 security closure: privileged SECURITY DEFINER command surfaces must
-- never be executable by anon. Authenticated callers must pass the function's
-- own authorization checks; anonymous callers get no execution privilege.
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
      and p.proname in (
        'erp_open_cloud_service_case',
        'erp_r9_cloud_customer_service_report',
        'erp_reject_service_stock_movement'
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
