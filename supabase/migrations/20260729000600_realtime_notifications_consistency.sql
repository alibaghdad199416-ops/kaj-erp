-- 17.69.0: realtime publication and notification consistency.
-- Idempotently publishes the tenant-scoped operational tables used by the
-- Flutter realtime bridge. Missing optional tables are intentionally skipped.
do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'erp_cars', 'erp_car_images', 'erp_warehouses',
    'erp_car_warehouse_transfers', 'erp_inventory',
    'erp_inventory_groups', 'erp_warehouse_stock',
    'erp_inventory_movements', 'erp_inventory_receipts',
    'erp_inventory_product_sales', 'erp_customers', 'erp_suppliers',
    'erp_sales', 'erp_installments', 'erp_purchases', 'erp_purchase_items',
    'erp_sales_orders_cloud', 'erp_sales_order_items_cloud',
    'erp_purchase_orders_cloud', 'erp_purchase_order_items_cloud',
    'erp_commercial_workflow_documents', 'erp_commercial_workflow_audit',
    'erp_cash_accounts', 'erp_cash_transactions', 'erp_journal_entries',
    'erp_journal_lines', 'erp_expenses', 'erp_reservations',
    'erp_enterprise_notifications', 'erp_records', 'branches', 'erp_accounts'
  ] loop
    if to_regclass('public.' || v_table) is not null then
      execute format('alter table public.%I replica identity full', v_table);
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
    end if;
  end loop;
end $$;

create or replace function public.erp_realtime_health(p_company_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_missing text[];
begin
  if not public.erp_is_company_member(p_company_id) then
    raise exception 'tenant denied';
  end if;

  select coalesce(array_agg(t.table_name order by t.table_name), array[]::text[])
    into v_missing
  from (values
    ('erp_cars'), ('erp_customers'), ('erp_suppliers'), ('erp_sales'),
    ('erp_purchases'), ('erp_installments'),
    ('erp_enterprise_notifications')
  ) as t(table_name)
  where to_regclass('public.' || t.table_name) is not null
    and not exists (
      select 1 from pg_publication_tables p
      where p.pubname = 'supabase_realtime'
        and p.schemaname = 'public'
        and p.tablename = t.table_name
    );

  return jsonb_build_object(
    'ok', cardinality(v_missing) = 0,
    'company_id', p_company_id,
    'publication', 'supabase_realtime',
    'missing_tables', to_jsonb(v_missing),
    'checked_at', now()
  );
end $$;

revoke all on function public.erp_realtime_health(uuid) from public, anon;
grant execute on function public.erp_realtime_health(uuid) to authenticated;
