\set ON_ERROR_STOP on
\pset pager off

begin;

do $$
declare
  v_invoice_definition text;
  v_issue_definition text;
  v_cost_totals_definition text;
  v_count bigint;
begin
  select pg_get_functiondef('public.erp_v736_post_maintenance_invoice(uuid,uuid)'::regprocedure)
    into v_invoice_definition;
  select pg_get_functiondef('public.erp_r57_execute_maintenance_material_issue(uuid,uuid,uuid,uuid,text,numeric,timestamptz)'::regprocedure)
    into v_issue_definition;
  select pg_get_functiondef('public.erp_r87_maintenance_material_cost_totals(uuid,uuid,boolean)'::regprocedure)
    into v_cost_totals_definition;

  -- R87 deliberately moved inventory-cost posting out of the invoice and into
  -- the material-issue event. The issue must consume FIFO in the native product
  -- cost currency and post the definition-bound cost + inventory accounts.
  if v_issue_definition not like '%erp_inventory_fifo_consumptions%'
     or v_issue_definition not like '%erp_maintenance_bound_accounts%'
     or v_issue_definition not like '%costExpenseAccountId%'
     or v_issue_definition not like '%assetAccountId%'
     or v_issue_definition not like '%maintenance_material_issue_cost%'
     or v_issue_definition not like '%v_cost_currency%'
     or v_issue_definition not like '%journal_entry_id=v_cost_journal%' then
    raise exception 'r58_material_issue_cost_posting_not_active';
  end if;

  -- The commercial invoice owns receivable/revenue only. It retains FIFO cost
  -- traceability by currency but must not create a second inventory-cost journal.
  if v_invoice_definition not like '%erp_maintenance_bound_accounts%'
     or v_invoice_definition not like '%maintenance_invoice_revenue%'
     or v_invoice_definition not like '%invoice_item_bindings%'
     or v_invoice_definition not like '%actualFifoCostByCurrency%'
     or v_invoice_definition not like '%inventoryCostPostingOwner%'
     or v_invoice_definition not like '%material_issue_event%'
     or v_invoice_definition like '%maintenance_invoice_cost%' then
    raise exception 'r58_invoice_revenue_ownership_not_active';
  end if;

  -- Cross-currency maintenance must preserve native inventory valuation instead
  -- of folding unlike currencies into the document currency.
  if v_cost_totals_definition not like '%group by cost_currency%'
     or v_cost_totals_definition not like '%erp_v764_definition_currency%' then
    raise exception 'r58_native_cost_currency_aggregation_not_active';
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

  -- Executed issue events with active FIFO evidence must retain the same actual
  -- total cost as their authoritative FIFO consumptions.
  select count(*) into v_count
  from (
    select i.company_id,i.id,
      coalesce(i.total_cost,0) issue_cost,
      coalesce(sum(fc.total_cost),0) fifo_cost
    from public.erp_maintenance_material_issues i
    join public.erp_maintenance_material_issue_lines il
      on il.company_id=i.company_id and il.issue_id=i.id
    left join public.erp_inventory_fifo_consumptions fc
      on fc.company_id=il.company_id and fc.delivery_id=il.issue_id
      and fc.sales_order_id=il.maintenance_order_id
      and fc.item_id=il.product_id and fc.warehouse_id=il.warehouse_id
      and fc.status='active'
    where i.status='executed'
    group by i.company_id,i.id,i.total_cost
  ) q where abs(q.issue_cost-q.fifo_cost)>0.0001;
  if v_count<>0 then raise exception 'r58_active_issue_fifo_cost_mismatch:%',v_count; end if;

  if has_function_privilege('anon',
       'public.erp_maintenance_bound_accounts(uuid,text,text,boolean)','execute')
     or has_function_privilege('authenticated',
       'public.erp_maintenance_bound_accounts(uuid,text,text,boolean)','execute') then
    raise exception 'r58_internal_account_resolver_exposed';
  end if;
end $$;

rollback;
select 'R58 maintenance item accounting runtime PASS' as result;
