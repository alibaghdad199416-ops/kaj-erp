\set ON_ERROR_STOP on
\pset pager off

begin;

do $$
declare
  v_definition text;
  v_count bigint;
begin
  select pg_get_functiondef('public.erp_v736_post_maintenance_invoice(uuid,uuid)'::regprocedure)
    into v_definition;
  if v_definition not like '%sum(fc.total_cost) actual_cost%'
     or v_definition not like '%erp_maintenance_bound_accounts%'
     or v_definition not like '%invoice_item_bindings%' then
    raise exception 'r58_item_bound_maintenance_posting_not_active';
  end if;

  select count(*) into v_count
  from (
    select il.company_id,il.issue_id,il.product_id,il.warehouse_id,
      sum(il.quantity) issue_quantity,
      coalesce((select sum(fc.quantity)
        from public.erp_inventory_fifo_consumptions fc
        where fc.company_id=il.company_id and fc.delivery_id=il.issue_id
          and fc.item_id=il.product_id and fc.warehouse_id=il.warehouse_id
          and fc.status='active'),0) fifo_quantity
    from public.erp_maintenance_material_issue_lines il
    join public.erp_maintenance_material_issues i
      on i.company_id=il.company_id and i.id=il.issue_id and i.status='executed'
    group by il.company_id,il.issue_id,il.product_id,il.warehouse_id
  ) q where abs(q.issue_quantity-q.fifo_quantity)>0.0001;
  if v_count<>0 then raise exception 'r58_active_issue_fifo_quantity_mismatch:%',v_count; end if;

  if has_function_privilege('anon',
       'public.erp_maintenance_bound_accounts(uuid,text,text,boolean)','execute')
     or has_function_privilege('authenticated',
       'public.erp_maintenance_bound_accounts(uuid,text,text,boolean)','execute') then
    raise exception 'r58_internal_account_resolver_exposed';
  end if;
end $$;

rollback;
select 'R58 maintenance item accounting runtime PASS' as result;
