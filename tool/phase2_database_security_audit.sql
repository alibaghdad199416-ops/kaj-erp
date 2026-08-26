begin;

-- Phase 2: Database + Migrations + RPC + RLS + Auth deep gate.
-- Disposable database only; fail closed on security invariant violations.

do $$
declare v text;
begin
  select string_agg(c.relname,', ' order by c.relname) into v
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind='r' and c.relname not like 'supabase_%' and c.relname<>'schema_migrations'
    and exists(select 1 from information_schema.columns x where x.table_schema='public' and x.table_name=c.relname and x.column_name='company_id')
    and not c.relrowsecurity;
  if v is not null then raise exception 'PHASE2 RLS_DISABLED tenant tables: %',v; end if;
end $$;

do $$
declare v text;
begin
  select string_agg(c.relname,', ' order by c.relname) into v
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind='r' and c.relname not like 'supabase_%' and c.relrowsecurity
    and exists(select 1 from information_schema.columns x where x.table_schema='public' and x.table_name=c.relname and x.column_name='company_id')
    and not exists(select 1 from pg_policies p where p.schemaname='public' and p.tablename=c.relname);
  if v is not null then raise exception 'PHASE2 RLS_NO_POLICY tenant tables: %',v; end if;
end $$;

do $$
declare v text;
begin
  select string_agg(grantee||':'||privilege_type||':'||table_name,', ' order by table_name,grantee,privilege_type) into v
  from information_schema.role_table_grants g
  where g.table_schema='public' and g.grantee in ('anon','authenticated') and g.privilege_type in ('INSERT','UPDATE','DELETE')
    and g.table_name not like 'supabase_%'
    and exists(select 1 from information_schema.columns c where c.table_schema='public' and c.table_name=g.table_name and c.column_name='company_id')
    and g.table_name not in ('profiles','company_memberships');
  if v is not null then raise exception 'PHASE2 DIRECT_DML_GRANTS: %',v; end if;
end $$;

do $$
declare v text;
begin
  select string_agg(grantee||':'||privilege_type||':'||table_name,', ' order by table_name,grantee,privilege_type) into v
  from information_schema.role_table_grants
  where table_schema='public' and table_name in ('erp_audit_log','erp_canonical_deletion_tombstones','erp_document_processing_jobs')
    and grantee in ('anon','authenticated') and privilege_type in ('SELECT','INSERT','UPDATE','DELETE');
  if v is not null then raise exception 'PHASE2 SENSITIVE_DIRECT_GRANTS: %',v; end if;
end $$;

do $$
declare v text;
begin
  select string_agg(n.nspname||'.'||p.proname,', ' order by p.proname) into v
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.prosecdef and coalesce(array_to_string(p.proconfig,','),'') not like '%search_path=%';
  if v is not null then raise exception 'PHASE2 SECURITY_DEFINER_UNPINNED: %',v; end if;
end $$;

do $$
declare v text;
begin
  select string_agg(n.nspname||'.'||p.proname,', ' order by p.proname) into v
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.prosecdef and p.proname ~ '(^|_)(admin|bootstrap|delete_all|purge|service|superuser)($|_)'
    and has_function_privilege('anon',p.oid,'EXECUTE');
  if v is not null then raise exception 'PHASE2 ANON_ADMIN_EXECUTE: %',v; end if;
end $$;

do $$
begin
  if to_regprocedure('public.is_active_company_member(uuid)') is null then raise exception 'PHASE2 missing is_active_company_member(uuid)'; end if;
  if to_regprocedure('public.is_company_admin(uuid)') is null then raise exception 'PHASE2 missing is_company_admin(uuid)'; end if;
  if to_regprocedure('public.erp_cloud_user_has_permission(uuid,text)') is null then raise exception 'PHASE2 missing erp_cloud_user_has_permission(uuid,text)'; end if;
end $$;

do $$
declare name text; oidv oid;
begin
  foreach name in array array['erp_v2300_create_sales_order','erp_v2300_create_purchase_order','erp_v2300_transfer_cloud_cash','erp_v2300_transfer_inventory_stock_batch','erp_register_cloud_document_blob','erp_r49_opportunity_command','erp_r9_get_cloud_master_record','erp_r9_list_cloud_master_records','erp_r49_cloud_global_search','erp_r15_reconcile_company_state'] loop
    select p.oid into oidv from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname=name order by p.oid limit 1;
    if oidv is null then raise exception 'PHASE2 missing critical RPC: %',name; end if;
    if not (select prosecdef from pg_proc where oid=oidv) then raise exception 'PHASE2 RPC_NOT_SECURITY_DEFINER: %',name; end if;
    if not exists(select 1 from pg_proc where oid=oidv and coalesce(array_to_string(proconfig,','),'') like '%search_path=%') then raise exception 'PHASE2 RPC_UNPINNED_SEARCH_PATH: %',name; end if;
  end loop;
end $$;

do $$
declare r record; v text;
begin
  for r in select schemaname,tablename,policyname,lower(coalesce(qual,'')||' '||coalesce(with_check,'')) expr from pg_policies where schemaname='public' and tablename in(select table_name from information_schema.columns where table_schema='public' and column_name='company_id') and tablename not like 'supabase_%' loop
    if r.expr not like '%company_id%' and r.expr not like '%is_active_company_member%' and r.expr not like '%is_company_admin%' then v:=coalesce(v||', ','')||r.tablename||':'||r.policyname; end if;
  end loop;
  if v is not null then raise exception 'PHASE2 POLICY_TENANT_BOUNDARY_MISSING: %',v; end if;
end $$;

do $$
declare v text;
begin
  select string_agg(c.relname,', ' order by c.relname) into v from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and c.relname in('erp_audit_log','erp_document_processing_jobs','erp_canonical_deletion_tombstones') and c.relrowsecurity and not c.relforcerowsecurity;
  if v is not null then raise exception 'PHASE2 RLS_NOT_FORCED: %',v; end if;
end $$;

commit;
select 'PHASE2_DATABASE_AUTH_RLS_PASS' as quality_gate;
