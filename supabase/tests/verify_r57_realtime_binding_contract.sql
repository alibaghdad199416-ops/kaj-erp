begin;

do $$
declare
  v_binding record;
  v_relation regclass;
begin
  for v_binding in
    select *
    from (values
      ('erp_cars', 'company_id'),
      ('erp_car_images', 'company_id'),
      ('erp_warehouses', 'company_id'),
      ('erp_car_warehouse_transfers', 'company_id'),
      ('erp_inventory', 'company_id'),
      ('erp_inventory_groups', 'company_id'),
      ('erp_warehouse_stock', 'company_id'),
      ('erp_inventory_movements', 'company_id'),
      ('erp_inventory_receipts', 'company_id'),
      ('erp_inventory_product_sales', 'company_id'),
      ('erp_customers', 'company_id'),
      ('erp_suppliers', 'company_id'),
      ('erp_sales', 'company_id'),
      ('erp_installments', 'company_id'),
      ('erp_purchases', 'company_id'),
      ('erp_purchase_items', 'company_id'),
      ('erp_sales_orders_cloud', 'company_id'),
      ('erp_sales_order_items_cloud', 'company_id'),
      ('erp_purchase_orders_cloud', 'company_id'),
      ('erp_purchase_order_items_cloud', 'company_id'),
      ('erp_commercial_workflow_documents', 'company_id'),
      ('erp_commercial_workflow_audit', 'company_id'),
      ('erp_cash_accounts', 'company_id'),
      ('erp_cash_transactions', 'company_id'),
      ('erp_journal_entries', 'company_id'),
      ('erp_journal_lines', 'company_id'),
      ('erp_expenses', 'company_id'),
      ('erp_maintenance_orders', 'company_id'),
      ('erp_maintenance_parts', 'company_id'),
      ('erp_maintenance_payments', 'company_id'),
      ('erp_fixed_assets', 'company_id'),
      ('erp_fiscal_periods', 'company_id'),
      ('erp_reservations', 'company_id'),
      ('erp_enterprise_notifications', 'company_id'),
      ('erp_records', 'company_id'),
      ('erp_permission_roles', 'company_id'),
      ('erp_role_permission_grants', 'company_id'),
      ('erp_user_role_assignments', 'company_id'),
      ('company_memberships', 'company_id'),
      ('erp_accounts', 'organization_id')
    ) as bindings(table_name, tenant_column)
  loop
    v_relation := to_regclass(format('public.%I', v_binding.table_name));
    if v_relation is null then
      raise exception 'Realtime binding table public.% is missing',
        v_binding.table_name;
    end if;

    if not exists (
      select 1
      from pg_attribute
      where attrelid = v_relation
        and attname = v_binding.tenant_column
        and attnum > 0
        and not attisdropped
    ) then
      raise exception 'Realtime filter %.% is missing',
        v_binding.table_name, v_binding.tenant_column;
    end if;

    if not has_column_privilege(
      'authenticated', v_relation, v_binding.tenant_column, 'select'
    ) then
      raise exception 'Realtime filter %.% is not selectable by authenticated',
        v_binding.table_name, v_binding.tenant_column;
    end if;

    if not (select relrowsecurity from pg_class where oid = v_relation) then
      raise exception 'Realtime binding public.% does not enforce RLS',
        v_binding.table_name;
    end if;

    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = v_binding.table_name
    ) then
      raise exception 'Realtime binding public.% is not published',
        v_binding.table_name;
    end if;
  end loop;
end
$$;

rollback;
