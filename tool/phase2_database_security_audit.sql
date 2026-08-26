-- Phase 2: Database + Migrations + RPC + RLS + Auth deep gate.
-- Disposable database only; fail closed on security invariant violations.

begin;

-- 1) Every ERP tenant-bearing table must use RLS. Supabase infrastructure tables are excluded.
do $$
declare r record;
begin
  for r in
    select c.relname
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r'
      and c.relname not like 'supabase_%'
      and c.relname <> 'schema_migrations'
      and exists (select 1 from information_schema.columns x where x.table_schema='public' and x.table_name=c.relname and x.column_name='company_id')
      and not c.relrowsecurity
  loop raise exception 'PHASE2 RLS_DISABLED tenant table: %',r.relname; end loop;
end $$;

-- 2) Every RLS-enabled tenant table must expose at least one policy.
do $$
declare r record;
begin
  for r in
    select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r' and c.relrowsecurity
      and c.relname not like 'supabase_%'
      and exists (select 1 from information_schema.columns x where x.table_schema='public' and x.table_name=c.relname and x.column_name='company_id')
      and not exists (select 1 from pg_policies p where p.schemaname='public' and p.tablename=c.relname)
  loop raise exception 'PHASE2 RLS_NO_POLICY tenant table: %',r.relname; end loop;
end $$;

-- 3) Client roles must not receive direct DML on tenant ERP tables (business writes go through guarded APIs/RPCs).
do $$
declare r record;
begin
  for r in
    select table_name,grantee,privilege_type
    from information_schema.role_table_grants g
    where g.table_schema='public' and g.grantee in ('anon','authenticated')
      and g.privilege_type in ('INSERT','UPDATE','DELETE')
      and g.table_name not like 'supabase_%'
      and exists (select 1 from information_schema.columns c where c.table_schema='public' and c.table_name=g.table_name and c.column_name='company_id')
      and g.table_name not in ('profiles','company_memberships')
  loop raise exception 'PHASE2 DIRECT_DML_GRANT % % %',r.grantee,r.privilege_type,r.table_name; end loop;
end $$;

-- 4) Security/audit internals are never directly exposed to anon/authenticated.
do $$
declare r record;
begin
  for r in
    select table_name,grantee,privilege_type from information_schema.role_table_grants
    where table_schema='public'
      and table_name in ('erp_audit_log','erp_canonical_deletion_tombstones','erp_document_processing_jobs')
      and grantee in ('anon','authenticated')
      and privilege_type in ('SELECT','INSERT','UPDATE','DELETE')
  loop raise exception 'PHASE2 SENSITIVE_DIRECT_GRANT % % %',r.grantee,r.privilege_type,r.table_name; end loop;
end $$;

-- 5) All SECURITY DEFINER functions must pin search_path.
do $$
declare r record;
begin
  for r in
    select n.nspname,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prosecdef
      and coalesce(array_to_string(p.proconfig,','),'') not like '%search_path=%'
  loop raise exception 'PHASE2 SECURITY_DEFINER_UNPINNED: %.%',r.nspname,r.proname; end loop;
end $$;

-- 6) Known administrative SECURITY DEFINER helpers must not be callable anonymously.
do $$
declare r record;
begin
  for r in
    select n.nspname,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prosecdef
      and p.proname ~ '(^|_)(admin|bootstrap|delete_all|purge|service|superuser)($|_)'
      and has_function_privilege('anon',p.oid,'EXECUTE')
  loop raise exception 'PHASE2 ANON_ADMIN_EXECUTE: %.%',r.nspname,r.proname; end loop;
end $$;

-- 7) Membership/permission primitives required by tenant isolation must exist.
do $$
begin
  if to_regprocedure('public.is_active_company_member(uuid)') is null then raise exception 'PHASE2 missing is_active_company_member(uuid)'; end if;
  if to_regprocedure('public.is_company_admin(uuid)') is null then raise exception 'PHASE2 missing is_company_admin(uuid)'; end if;
  if to_regprocedure('public.erp_cloud_user_has_permission(uuid,text)') is null then raise exception 'PHASE2 missing erp_cloud_user_has_permission(uuid,text)'; end if;
end $$;

-- 8) Critical workflow RPCs must be SECURITY DEFINER with pinned search_path.
do $$
declare name text; oidv oid;
begin
  foreach name in array array[
    'erp_v2300_create_sales_order','erp_v2300_create_purchase_order','erp_v2300_transfer_cloud_cash',
    'erp_v2300_transfer_inventory_stock_batch','erp_register_cloud_document_blob','erp_r49_opportunity_command',
    'erp_r9_get_cloud_master_record','erp_r9_list_cloud_master_records','erp_r49_cloud_global_search','erp_r15_reconcile_company_state'
  ] loop
    select p.oid into oidv from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname=name order by p.oid limit 1;
    if oidv is null then raise exception 'PHASE2 missing critical RPC: %',name; end if;
    if not (select prosecdef from pg_proc where oid=oidv) then raise exception 'PHASE2 RPC_NOT_SECURITY_DEFINER: %',name; end if;
    if not exists(select 1 from pg_proc where oid=oidv and coalesce(array_to_string(proconfig,','),'') like '%search_path=%') then raise exception 'PHASE2 RPC_UNPINNED_SEARCH_PATH: %',name; end if;
  end loop;
end $$;

-- 9) Tenant policies must visibly encode the tenant boundary.
do $$
declare r record; expr text;
begin
  for r in
    select schemaname,tablename,policyname,coalesce(qual,'')||' '||coalesce(with_check,'') as expr
    from pg_policies
    where schemaname='public'
      and tablename in (select table_name from information_schema.columns where table_schema='public' and column_name='company_id')
      and tablename not like 'supabase_%'
  loop
    expr:=lower(r.expr);
    if expr not like '%company_id%' and expr not like '%is_active_company_member%' and expr not like '%is_company_admin%' then
      raise exception 'PHASE2 POLICY_TENANT_BOUNDARY_MISSING: %.%',r.tablename,r.policyname;
    end if;
  end loop;
end $$;

-- 10) High-value security/audit tables must force RLS.
do $$
declare r record;
begin
  for r in
    select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r'
      and c.relname in ('erp_audit_log','erp_document_processing_jobs','erp_canonical_deletion_tombstones')
      and c.relrowsecurity and not c.relforcerowsecurity
  loop raise exception 'PHASE2 RLS_NOT_FORCED: %',r.relname; end loop;
end $$;

commit;
select 'PHASE2_DATABASE_AUTH_RLS_PASS' as quality_gate;
