-- Phase 2: Database + Migrations + RPC + RLS + Auth deep gate.
-- Runs only against a disposable database after every migration has applied.
-- Fail closed: any security invariant violation aborts the gate.

begin;

-- 1) Every tenant-bearing public table must use RLS.
do $$
declare r record;
begin
  for r in
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public'
      and c.relkind='r'
      and exists (
        select 1 from information_schema.columns x
        where x.table_schema='public' and x.table_name=c.relname and x.column_name='company_id'
      )
      and c.relname not in ('schema_migrations')
      and not c.relrowsecurity
  loop
    raise exception 'PHASE2 RLS_DISABLED tenant table: %',r.relname;
  end loop;
end $$;

-- 2) Tenant tables must have at least one policy for authenticated access.
do $$
declare r record;
begin
  for r in
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r' and c.relrowsecurity
      and exists (
        select 1 from information_schema.columns x
        where x.table_schema='public' and x.table_name=c.relname and x.column_name='company_id'
      )
      and not exists (
        select 1 from pg_policies p
        where p.schemaname='public' and p.tablename=c.relname
      )
  loop
    raise exception 'PHASE2 RLS_NO_POLICY tenant table: %',r.relname;
  end loop;
end $$;

-- 3) No anon/authenticated direct DML grants on tenant-bearing ERP tables.
do $$
declare r record;
begin
  for r in
    select table_name, grantee, privilege_type
    from information_schema.role_table_grants g
    where g.table_schema='public'
      and g.grantee in ('anon','authenticated')
      and g.privilege_type in ('INSERT','UPDATE','DELETE')
      and exists (
        select 1 from information_schema.columns c
        where c.table_schema='public' and c.table_name=g.table_name and c.column_name='company_id'
      )
      and g.table_name not in ('profiles','company_memberships')
  loop
    raise exception 'PHASE2 DIRECT_DML_GRANT % % %',r.grantee,r.privilege_type,r.table_name;
  end loop;
end $$;

-- 4) Sensitive internal/auth tables are never directly readable by client roles.
do $$
declare r record;
begin
  for r in
    select table_name, grantee, privilege_type
    from information_schema.role_table_grants
    where table_schema='public'
      and table_name in ('erp_audit_log','erp_canonical_deletion_tombstones','erp_document_processing_jobs')
      and grantee in ('anon','authenticated')
      and privilege_type in ('SELECT','INSERT','UPDATE','DELETE')
  loop
    raise exception 'PHASE2 SENSITIVE_DIRECT_GRANT % % %',r.grantee,r.privilege_type,r.table_name;
  end loop;
end $$;

-- 5) SECURITY DEFINER functions must pin search_path to prevent object-shadowing.
do $$
declare r record;
begin
  for r in
    select n.nspname,p.proname,p.oid
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prosecdef
      and coalesce(array_to_string(p.proconfig,','),'') not like '%search_path=%'
  loop
    raise exception 'PHASE2 SECURITY_DEFINER_UNPINNED: %.%',r.nspname,r.proname;
  end loop;
end $$;

-- 6) Public client roles must not receive EXECUTE on known administrative helpers.
do $$
declare r record;
begin
  for r in
    select n.nspname,p.proname
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.prosecdef
      and p.proname ~ '(^|_)(admin|bootstrap|delete_all|purge|service|superuser)($|_)'
      and has_function_privilege('anon',p.oid,'EXECUTE')
  loop
    raise exception 'PHASE2 ANON_ADMIN_EXECUTE: %.%',r.nspname,r.proname;
  end loop;
end $$;

-- 7) Auth and membership primitives required by RLS must exist and be callable.
do $$
begin
  if to_regprocedure('public.is_active_company_member(uuid)') is null then
    raise exception 'PHASE2 missing membership primitive';
  end if;
  if to_regprocedure('public.is_company_admin(uuid)') is null then
    raise exception 'PHASE2 missing admin primitive';
  end if;
  if to_regprocedure('public.erp_cloud_user_has_permission(uuid,text)') is null then
    raise exception 'PHASE2 missing permission primitive';
  end if;
end $$;

-- 8) Required security-critical RPCs must be SECURITY DEFINER and search-path pinned.
do $$
declare name text; oidv oid;
begin
  foreach name in array array[
    'erp_v2300_create_sales_order','erp_v2300_create_purchase_order',
    'erp_v2300_transfer_cloud_cash','erp_v2300_transfer_inventory_stock_batch',
    'erp_register_cloud_document_blob','erp_r49_opportunity_command',
    'erp_r9_get_cloud_master_record','erp_r9_list_cloud_master_records',
    'erp_r49_cloud_global_search','erp_r15_reconcile_company_state'
  ] loop
    select p.oid into oidv from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname=name limit 1;
    if oidv is null then raise exception 'PHASE2 missing critical RPC: %',name; end if;
    if not (select prosecdef from pg_proc where oid=oidv) then raise exception 'PHASE2 RPC_NOT_SECURITY_DEFINER: %',name; end if;
    if not exists(select 1 from pg_proc where oid=oidv and coalesce(array_to_string(proconfig,','),'') like '%search_path=%') then raise exception 'PHASE2 RPC_UNPINNED_SEARCH_PATH: %',name; end if;
  end loop;
end $$;

-- 9) Policy expressions on tenant tables must reference the tenant boundary.
do $$
declare r record;
begin
  for r in
    select schemaname,tablename,policyname,coalesce(qual,'')||' '||coalesce(with_check,'') as expr
    from pg_policies
    where schemaname='public'
      and tablename in (
        select table_name from information_schema.columns
        where table_schema='public' and column_name='company_id'
      )
      and (qual is not null or with_check is not null)
      and lower(coalesce(qual,'')||' '||coalesce(with_check,'')) not like '%company_id%'
      and lower(coalesce(qual,'')||' '||coalesce(with_check,'')) not like '%is_active_company_member%'
      and lower(coalesce(qual,'')||' '||coalesce(with_check,'')) not like '%is_company_admin%'
  loop
    raise exception 'PHASE2 POLICY_TENANT_BOUNDARY_MISSING: %.%',r.tablename,r.policyname;
  end loop;
end $$;

-- 10) RLS must be forced for high-value audit/security tables so table owners cannot bypass it.
do $$
declare r record;
begin
  for r in
    select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public'
      and c.relname in ('erp_audit_log','erp_document_processing_jobs','erp_canonical_deletion_tombstones')
      and c.relkind='r'
      and c.relrowsecurity
      and not c.relforcerowsecurity
  loop
    raise exception 'PHASE2 RLS_NOT_FORCED: %',r.relname;
  end loop;
end $$;

commit;

select 'PHASE2_DATABASE_AUTH_RLS_PASS' as quality_gate;
