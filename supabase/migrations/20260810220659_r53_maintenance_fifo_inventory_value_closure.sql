begin;

-- R53 closes the maintenance valuation gap discovered by the product-identity
-- audit. Stock issues already reduce warehouse quantity; invoice posting is the
-- accounting owner and must consume the same product/warehouse FIFO layers
-- before it calculates the inventory-credit journal.
create or replace function public.erp_r53_consume_maintenance_fifo(
  p_company_id uuid,
  p_order_id uuid,
  p_effective_at timestamptz
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_order public.erp_maintenance_orders%rowtype;
  v_line record;
  v_layer public.erp_inventory_cost_layers%rowtype;
  v_needed numeric;
  v_existing numeric;
  v_take numeric;
  v_group_cost numeric;
  v_total_cost numeric:=0;
  v_breakdown jsonb:='[]'::jsonb;
begin
  select * into v_order
  from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id and not is_deleted
  for update;
  if not found then raise exception 'maintenance_order_not_found'; end if;

  for v_line in
    select coalesce(mp.source_product_id,mp.product_id::text) as product_id,
           coalesce(mp.source_warehouse_id,mp.warehouse_id::text,
                    v_order.source_warehouse_id,v_order.warehouse_id::text) as warehouse_id,
           sum(mp.quantity)::numeric as quantity
    from public.erp_maintenance_parts mp
    where mp.company_id=p_company_id and mp.maintenance_order_id=p_order_id
      and not mp.is_deleted and mp.line_type<>'service'
    group by coalesce(mp.source_product_id,mp.product_id::text),
             coalesce(mp.source_warehouse_id,mp.warehouse_id::text,
                      v_order.source_warehouse_id,v_order.warehouse_id::text)
  loop
    if v_line.product_id is null or v_line.warehouse_id is null then
      raise exception 'maintenance_stock_link_missing';
    end if;

    select coalesce(sum(fc.quantity),0),coalesce(sum(fc.total_cost),0)
      into v_existing,v_group_cost
    from public.erp_inventory_fifo_consumptions fc
    where fc.company_id=p_company_id and fc.delivery_id=p_order_id
      and fc.sales_order_id=p_order_id and fc.status='active'
      and fc.item_type='product' and fc.item_id=v_line.product_id
      and fc.warehouse_id=v_line.warehouse_id;

    v_needed:=v_line.quantity-v_existing;
    if v_needed<0 then
      raise exception 'maintenance_quantity_below_existing_cost_consumption:%',v_line.product_id;
    end if;

    for v_layer in
      select * from public.erp_inventory_cost_layers l
      where l.company_id=p_company_id and l.item_type='product'
        and l.item_id=v_line.product_id and l.warehouse_id=v_line.warehouse_id
        and l.status in ('active','consumed') and l.remaining_quantity>0
        and l.effective_at<=p_effective_at
      order by l.effective_at,l.created_at,l.id
      for update
    loop
      exit when v_needed<=0;
      v_take:=least(v_needed,v_layer.remaining_quantity);
      update public.erp_inventory_cost_layers
      set remaining_quantity=remaining_quantity-v_take,
          status=case when remaining_quantity-v_take<=0 then 'consumed' else 'active' end,
          updated_at=now(),updated_by=auth.uid()
      where id=v_layer.id;
      insert into public.erp_inventory_fifo_consumptions(
        company_id,delivery_id,sales_order_id,layer_id,item_type,item_id,
        warehouse_id,quantity,unit_cost,effective_at,status
      ) values(
        p_company_id,p_order_id,p_order_id,v_layer.id,'product',v_line.product_id,
        v_line.warehouse_id,v_take,v_layer.unit_cost,p_effective_at,'active'
      ) on conflict(company_id,delivery_id,layer_id) do update set
        quantity=excluded.quantity,unit_cost=excluded.unit_cost,
        effective_at=excluded.effective_at,status='active',reversed_at=null;
      v_group_cost:=v_group_cost+(v_take*v_layer.unit_cost);
      v_needed:=v_needed-v_take;
    end loop;

    if v_needed>0 then
      raise exception 'insufficient_maintenance_cost_layers:%',v_line.product_id;
    end if;

    update public.erp_maintenance_parts mp
    set unit_cost=round(v_group_cost/nullif(v_line.quantity,0),2),
        total_cost=round(v_group_cost*(mp.quantity/v_line.quantity),2),
        updated_at=now()
    where mp.company_id=p_company_id and mp.maintenance_order_id=p_order_id
      and not mp.is_deleted and mp.line_type<>'service'
      and coalesce(mp.source_product_id,mp.product_id::text)=v_line.product_id
      and coalesce(mp.source_warehouse_id,mp.warehouse_id::text,
                   v_order.source_warehouse_id,v_order.warehouse_id::text)=v_line.warehouse_id;

    v_total_cost:=v_total_cost+v_group_cost;
    v_breakdown:=v_breakdown||jsonb_build_array(jsonb_build_object(
      'itemType','product','itemId',v_line.product_id,'warehouseId',v_line.warehouse_id,
      'quantity',v_line.quantity,'totalCost',v_group_cost,
      'unitCost',v_group_cost/nullif(v_line.quantity,0)));
  end loop;

  update public.erp_maintenance_orders
  set parts_cost=round(v_total_cost,2),total_cost=round(labor_cost+v_total_cost,2),
      profit=round(sale_price-(labor_cost+v_total_cost),2),updated_at=now()
  where company_id=p_company_id and id=p_order_id;

  return jsonb_build_object('totalCost',v_total_cost,'breakdown',v_breakdown);
end;
$$;

revoke all on function public.erp_r53_consume_maintenance_fifo(uuid,uuid,timestamptz)
  from public,anon,authenticated;
grant execute on function public.erp_r53_consume_maintenance_fifo(uuid,uuid,timestamptz)
  to service_role;

create or replace function public.erp_v736_post_maintenance_invoice(
  p_company_id uuid,
  p_order_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_order public.erp_maintenance_orders%rowtype;
  v_currency text;
  v_partner_account text;
  v_result jsonb;
  v_entry jsonb;
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['maintenance.approve']);

  select * into v_order from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id and not is_deleted
  for update;
  if not found then raise exception 'maintenance_order_not_found'; end if;

  -- Preserve historical/idempotent invoices. Only a first posting may create
  -- FIFO consumption and its journal, in the same database transaction.
  if v_order.invoice_journal_entry_id is not null then
    return public.erp_v736_post_maintenance_invoice_pre_r49_identity(p_company_id,p_order_id);
  end if;

  if v_order.pricing_type='paid' then
    if v_order.customer_id is null then raise exception 'paid_maintenance_customer_required'; end if;
    v_currency:=upper(coalesce(v_order.currency_code,''));
    if v_currency not in ('USD','IQD') then raise exception 'maintenance_currency_invalid:%',v_currency; end if;
    perform public.erp_v764_assert_partner_dual_ledgers(p_company_id,v_order.customer_id::text,'customer');
    v_partner_account:=public.erp_workflow_partner_account(
      p_company_id,'customer',v_order.customer_id::text,v_currency);
    perform public.erp_phase2_account_guard(p_company_id,v_partner_account,'asset',v_currency);
  end if;

  perform public.erp_r53_consume_maintenance_fifo(
    p_company_id,p_order_id,coalesce(v_order.maintenance_date,now()));
  v_result:=public.erp_v736_post_maintenance_invoice_pre_r49_identity(p_company_id,p_order_id);

  for v_entry in select value from jsonb_array_elements(coalesce(v_result->'costJournalEntries','[]'::jsonb))
  loop
    update public.erp_inventory_fifo_consumptions fc
    set journal_entry_id=v_entry->>'journalEntryId'
    from public.erp_inventory_cost_layers l
    where fc.company_id=p_company_id and fc.delivery_id=p_order_id
      and fc.sales_order_id=p_order_id and fc.status='active' and l.id=fc.layer_id
      and upper(l.currency)=upper(v_entry->>'currency');
  end loop;
  return v_result||jsonb_build_object('fifoValuationApplied',true);
end;
$$;

revoke all on function public.erp_v736_post_maintenance_invoice(uuid,uuid)
  from public,anon;
grant execute on function public.erp_v736_post_maintenance_invoice(uuid,uuid)
  to authenticated,service_role;

notify pgrst,'reload schema';
commit;
