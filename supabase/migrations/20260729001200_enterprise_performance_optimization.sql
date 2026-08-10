-- Quality Line ERP 17.76.0 - enterprise performance optimization
begin;

-- Tenant/date indexes for the highest traffic ERP tables. Each statement is guarded
-- so this migration remains compatible with installations that do not enable every module.
do $$
declare
  i integer;
  t text;
  c1 text;
  c2 text;
  idx text;
  targets text[][] := array[
    array['erp_sales','company_id','created_at'],
    array['erp_purchases','company_id','created_at'],
    array['erp_customers','company_id','updated_at'],
    array['erp_suppliers','company_id','updated_at'],
    array['erp_vehicles','company_id','updated_at'],
    array['erp_journal_entries','company_id','entry_date'],
    array['erp_journal_lines','company_id','journal_entry_id'],
    array['erp_inventory_receipts','company_id','created_at'],
    array['erp_warehouse_stock','company_id','warehouse_id'],
    array['erp_sales_orders_cloud','company_id','created_at'],
    array['erp_purchase_orders_cloud','company_id','created_at'],
    array['erp_backup_snapshots','company_id','created_at'],
    array['erp_master_audit_log','company_id','created_at'],
    array['erp_user_role_assignments','company_id','user_uid'],
    array['erp_role_permission_grants','company_id','role_id']
  ];
begin
  for i in 1..coalesce(array_length(targets,1),0) loop
    t := targets[i][1];
    c1 := targets[i][2];
    c2 := targets[i][3];
    if to_regclass('public.' || t) is not null
       and exists (select 1 from information_schema.columns where table_schema='public' and table_name=t and column_name=c1)
       and exists (select 1 from information_schema.columns where table_schema='public' and table_name=t and column_name=c2) then
      idx := 'idx_' || t || '_perf_' || substr(md5(c1 || ',' || c2),1,8);
      execute format('create index if not exists %I on public.%I (%I, %I)', idx, t, c1, c2);
    end if;
  end loop;
end $$;

-- Lightweight statistics endpoint for administrators.
create or replace function public.erp_performance_table_stats(p_company_id uuid)
returns table(
  table_name text,
  estimated_rows bigint,
  total_bytes bigint,
  index_bytes bigint,
  sequential_scans bigint,
  index_scans bigint
)
language sql
security definer
set search_path = public, pg_catalog
as $$
  select
    s.relname::text,
    coalesce(s.n_live_tup,0)::bigint,
    pg_total_relation_size(s.relid)::bigint,
    pg_indexes_size(s.relid)::bigint,
    coalesce(s.seq_scan,0)::bigint,
    coalesce(s.idx_scan,0)::bigint
  from pg_stat_user_tables s
  where s.schemaname = 'public'
    and s.relname like 'erp\_%' escape '\'
  order by pg_total_relation_size(s.relid) desc
  limit 100;
$$;

create or replace function public.erp_performance_health(p_company_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_indexes int;
  v_missing int;
  v_large int;
  v_db_size bigint;
begin
  select count(*) into v_indexes
  from pg_indexes where schemaname='public' and tablename like 'erp\_%' escape '\';

  select count(*) into v_missing
  from information_schema.columns c
  where c.table_schema='public' and c.column_name='company_id'
    and c.table_name like 'erp\_%' escape '\'
    and not exists (
      select 1 from pg_indexes i
      where i.schemaname='public' and i.tablename=c.table_name
        and i.indexdef ilike '%(company_id%'
    );

  select count(*) into v_large
  from pg_stat_user_tables s
  where s.schemaname='public' and s.relname like 'erp\_%' escape '\'
    and pg_total_relation_size(s.relid) >= 50 * 1024 * 1024;

  select pg_database_size(current_database()) into v_db_size;

  return jsonb_build_object(
    'ok', v_missing = 0,
    'indexes', v_indexes,
    'missing_tenant_indexes', v_missing,
    'large_tables', v_large,
    'database_size_bytes', v_db_size,
    'company_id', p_company_id,
    'checked_at', now()
  );
end;
$$;

revoke all on function public.erp_performance_table_stats(uuid) from public;
revoke all on function public.erp_performance_health(uuid) from public;
grant execute on function public.erp_performance_table_stats(uuid) to authenticated;
grant execute on function public.erp_performance_health(uuid) to authenticated;

commit;
