begin;

-- R54 separates operational stock valuation from General Ledger posting.
-- Receipt/delivery/material issue own cost-layer state. Invoice approval only
-- posts accounting from that already established operational valuation.
do $$
begin
  if to_regprocedure('public.erp_approve_cloud_purchase_receipt_pre_r54_valuation(uuid,uuid)') is null then
    alter function public.erp_approve_cloud_purchase_receipt(uuid,uuid)
      rename to erp_approve_cloud_purchase_receipt_pre_r54_valuation;
  end if;
  if to_regprocedure('public.erp_approve_cloud_sales_delivery_pre_r54_valuation(uuid,uuid)') is null then
    alter function public.erp_approve_cloud_sales_delivery(uuid,uuid)
      rename to erp_approve_cloud_sales_delivery_pre_r54_valuation;
  end if;
  if to_regprocedure('public.erp_advance_cloud_maintenance_workflow_pre_r54_valuation(uuid,uuid)') is null then
    alter function public.erp_advance_cloud_maintenance_workflow(uuid,uuid)
      rename to erp_advance_cloud_maintenance_workflow_pre_r54_valuation;
  end if;
  if to_regprocedure('public.erp_r22_post_purchase_invoice_direct_pre_r54_valuation(uuid,uuid)') is null then
    alter function public.erp_r22_post_purchase_invoice_direct(uuid,uuid)
      rename to erp_r22_post_purchase_invoice_direct_pre_r54_valuation;
  end if;
end $$;

create or replace function public.erp_r54_refresh_receipt_valuation(
  p_company_id uuid,p_receipt_id uuid
) returns void language plpgsql security definer set search_path=public as $$
declare r record; v_average numeric;
begin
  for r in
    select item_type,item_id,warehouse_id,currency,
           sum(remaining_quantity*unit_cost)/nullif(sum(remaining_quantity),0) average_cost
    from public.erp_inventory_cost_layers
    where company_id=p_company_id and receipt_id=p_receipt_id
      and status in ('active','consumed')
    group by item_type,item_id,warehouse_id,currency
  loop
    v_average:=coalesce(r.average_cost,0);
    if r.item_type='product' then
      update public.erp_warehouse_stock
      set data=data||jsonb_build_object(
        'averageUnitCost',round(v_average,6),'valuationCurrency',upper(r.currency),
        'valuationPendingInvoice',true,'valuationReceiptId',p_receipt_id::text,'updatedAt',now()),
        updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and not is_deleted
        and coalesce(data->>'productId',data->>'product_id')=r.item_id
        and coalesce(data->>'warehouseId',data->>'warehouse_id')=r.warehouse_id;
      update public.erp_inventory_movements
      set data=data||jsonb_build_object(
        'unitCost',round(v_average,6),'costCurrency',upper(r.currency),
        'costMethod','FIFO','valuationReceiptId',p_receipt_id::text),
        updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and not is_deleted
        and data->>'referenceType'='purchase_receipt' and data->>'referenceId'=p_receipt_id::text
        and data->>'productId'=r.item_id and data->>'warehouseId'=r.warehouse_id;
    else
      update public.erp_cars set data=data||jsonb_build_object(
        'purchasePrice',round(v_average,6),'purchase_price',round(v_average,6),
        'costCurrency',upper(r.currency),'cost_currency',upper(r.currency),
        'valuationPendingInvoice',true,'valuationReceiptId',p_receipt_id::text,'updatedAt',now()),
        updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and id=r.item_id and not is_deleted;
    end if;
  end loop;
end;
$$;

create or replace function public.erp_approve_cloud_purchase_receipt(
  p_company_id uuid,p_receipt_id uuid
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['purchases.approve','purchases.update','purchases.create']);
  perform public.erp_approve_cloud_purchase_receipt_pre_r54_valuation(p_company_id,p_receipt_id);
  perform public.erp_fifo_register_purchase_receipt(p_company_id,p_receipt_id);
  perform public.erp_r54_refresh_receipt_valuation(p_company_id,p_receipt_id);
end;
$$;

create or replace function public.erp_r54_consume_sales_delivery_fifo(
  p_company_id uuid,p_delivery_id uuid
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  d public.erp_commercial_workflow_documents%rowtype; a record;
  l public.erp_inventory_cost_layers%rowtype;
  v_needed numeric; v_existing numeric; v_take numeric; v_effective timestamptz;
  v_total numeric:=0; v_breakdown jsonb:='[]'::jsonb;
begin
  select * into d from public.erp_commercial_workflow_documents
  where company_id=p_company_id and id=p_delivery_id and module='sales'
    and document_type='delivery' and status='approved' and not is_deleted for update;
  if not found then raise exception 'approved_sales_delivery_required'; end if;
  v_effective:=coalesce(d.effective_at,d.created_at,now());
  perform public.erp_validate_operational_date(p_company_id,'sales',v_effective);

  for a in
    select x."itemType",x."itemId",max(x."description") description,
           x."warehouseId",sum(x.quantity) quantity
    from jsonb_to_recordset(d.payload->'allocations') as x(
      "itemType" text,"itemId" text,"description" text,"warehouseId" text,quantity numeric)
    group by x."itemType",x."itemId",x."warehouseId"
  loop
    select coalesce(sum(quantity),0) into v_existing
    from public.erp_inventory_fifo_consumptions
    where company_id=p_company_id and delivery_id=p_delivery_id and status='active'
      and item_type=a."itemType" and item_id=a."itemId" and warehouse_id=a."warehouseId";
    v_needed:=a.quantity-v_existing;
    if v_needed<0 then raise exception 'delivery_quantity_below_fifo_consumption:%',a."itemId"; end if;
    for l in
      select * from public.erp_inventory_cost_layers q
      where q.company_id=p_company_id and q.item_type=a."itemType" and q.item_id=a."itemId"
        and q.warehouse_id=a."warehouseId" and q.status in ('active','consumed')
        and q.remaining_quantity>0 and q.effective_at<=v_effective
      order by q.effective_at,q.created_at,q.id for update
    loop
      exit when v_needed<=0;
      v_take:=least(v_needed,l.remaining_quantity);
      update public.erp_inventory_cost_layers set
        remaining_quantity=remaining_quantity-v_take,
        status=case when remaining_quantity-v_take<=0 then 'consumed' else 'active' end,
        updated_at=now(),updated_by=auth.uid() where id=l.id;
      insert into public.erp_inventory_fifo_consumptions(
        company_id,delivery_id,sales_order_id,layer_id,item_type,item_id,warehouse_id,
        quantity,unit_cost,effective_at,status
      ) values(
        p_company_id,p_delivery_id,d.parent_id,l.id,a."itemType",a."itemId",a."warehouseId",
        v_take,l.unit_cost,v_effective,'active'
      ) on conflict(company_id,delivery_id,layer_id) do update set
        quantity=excluded.quantity,unit_cost=excluded.unit_cost,effective_at=excluded.effective_at,
        status='active',reversed_at=null;
      v_total:=v_total+(v_take*l.unit_cost);
      v_breakdown:=v_breakdown||jsonb_build_array(jsonb_build_object(
        'itemType',a."itemType",'itemId',a."itemId",'warehouseId',a."warehouseId",
        'layerId',l.id,'layerNumber',l.layer_number,'quantity',v_take,
        'unitCost',l.unit_cost,'totalCost',v_take*l.unit_cost));
      v_needed:=v_needed-v_take;
    end loop;
    if v_needed>0 then raise exception 'insufficient_delivery_cost_layers:%',a."itemId"; end if;
  end loop;

  with costs as (
    select item_id,warehouse_id,sum(quantity*unit_cost)/nullif(sum(quantity),0) average_cost
    from public.erp_inventory_fifo_consumptions
    where company_id=p_company_id and delivery_id=p_delivery_id and status='active'
    group by item_id,warehouse_id
  )
  update public.erp_inventory_movements m set
    data=m.data||jsonb_build_object('unitCost',c.average_cost,'movementDate',v_effective,
      'effectiveAt',v_effective,'costMethod','FIFO','fifoDeliveryId',p_delivery_id::text),
    updated_at=now(),updated_by=auth.uid()
  from costs c where m.company_id=p_company_id and not m.is_deleted
    and m.data->>'referenceType'='sales_delivery' and m.data->>'referenceId'=p_delivery_id::text
    and m.data->>'productId'=c.item_id and m.data->>'warehouseId'=c.warehouse_id;

  select coalesce(sum(total_cost),0) into v_total
  from public.erp_inventory_fifo_consumptions
  where company_id=p_company_id and delivery_id=p_delivery_id and status='active';
  update public.erp_commercial_workflow_documents set payload=
    (payload-'fifoCostJournalEntryId'-'costJournalEntryId')||jsonb_build_object(
      'costMethod','FIFO','operationalFifoBreakdown',v_breakdown,
      'operationalFifoTotalCost',round(v_total,6),'operationalFifoAppliedAt',now(),
      'valuationPendingInvoice',true,'accountingOwner','invoice'),updated_at=now()
  where company_id=p_company_id and id=p_delivery_id;
  return jsonb_build_object('totalCost',v_total,'breakdown',v_breakdown);
end;
$$;

create or replace function public.erp_approve_cloud_sales_delivery(
  p_company_id uuid,p_delivery_id uuid
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['sales.approve','sales.update','sales.create']);
  perform public.erp_fifo_prepare_opening_layers(p_company_id,p_delivery_id);
  perform public.erp_approve_cloud_sales_delivery_pre_r54_valuation(p_company_id,p_delivery_id);
  perform public.erp_r54_consume_sales_delivery_fifo(p_company_id,p_delivery_id);
end;
$$;

create or replace function public.erp_r54_allocate_maintenance_line_costs(
  p_company_id uuid,p_order_id uuid
) returns numeric language plpgsql security definer set search_path=public as $$
declare g record; p record; v_group_cost numeric; v_assigned numeric; v_line_cost numeric;
  v_index integer; v_count integer; v_total numeric:=0;
begin
  for g in
    select coalesce(mp.source_product_id,mp.product_id::text) product_id,
      coalesce(mp.source_warehouse_id,mp.warehouse_id::text,o.source_warehouse_id,o.warehouse_id::text) warehouse_id,
      sum(mp.quantity)::numeric quantity
    from public.erp_maintenance_parts mp join public.erp_maintenance_orders o
      on o.company_id=mp.company_id and o.id=mp.maintenance_order_id
    where mp.company_id=p_company_id and mp.maintenance_order_id=p_order_id
      and not mp.is_deleted and mp.line_type<>'service'
    group by 1,2
  loop
    select coalesce(sum(fc.total_cost),0) into v_group_cost
    from public.erp_inventory_fifo_consumptions fc
    where fc.company_id=p_company_id and fc.delivery_id=p_order_id
      and fc.sales_order_id=p_order_id and fc.status='active'
      and fc.item_type='product' and fc.item_id=g.product_id and fc.warehouse_id=g.warehouse_id;
    v_assigned:=0; v_index:=0;
    select count(*) into v_count from public.erp_maintenance_parts mp
    where mp.company_id=p_company_id and mp.maintenance_order_id=p_order_id
      and not mp.is_deleted and mp.line_type<>'service'
      and coalesce(mp.source_product_id,mp.product_id::text)=g.product_id
      and coalesce(mp.source_warehouse_id,mp.warehouse_id::text)=g.warehouse_id;
    for p in select * from public.erp_maintenance_parts mp
      where mp.company_id=p_company_id and mp.maintenance_order_id=p_order_id
        and not mp.is_deleted and mp.line_type<>'service'
        and coalesce(mp.source_product_id,mp.product_id::text)=g.product_id
        and coalesce(mp.source_warehouse_id,mp.warehouse_id::text)=g.warehouse_id
      order by mp.id for update
    loop
      v_index:=v_index+1;
      v_line_cost:=case when v_index=v_count then v_group_cost-v_assigned
        else round(v_group_cost*(p.quantity/g.quantity),2) end;
      update public.erp_maintenance_parts set total_cost=v_line_cost,
        unit_cost=round(v_line_cost/nullif(p.quantity,0),2),updated_at=now() where id=p.id;
      v_assigned:=v_assigned+v_line_cost;
    end loop;
    if abs(v_assigned-v_group_cost)>0.000001 then
      raise exception 'maintenance_fifo_line_allocation_mismatch:%:%',v_assigned,v_group_cost;
    end if;
    v_total:=v_total+v_group_cost;
  end loop;
  update public.erp_maintenance_orders set parts_cost=round(v_total,2),
    total_cost=round(labor_cost+v_total,2),profit=round(sale_price-(labor_cost+v_total),2),updated_at=now()
  where company_id=p_company_id and id=p_order_id;
  return v_total;
end;
$$;

create or replace function public.erp_advance_cloud_maintenance_workflow(
  p_company_id uuid,p_order_id uuid
) returns void language plpgsql security definer set search_path=public as $$
declare v_before text; v_after text; v_effective timestamptz;
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['maintenance.approve']);
  select workflow_stage,coalesce(maintenance_date,now()) into v_before,v_effective
  from public.erp_maintenance_orders where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found then raise exception 'maintenance_order_not_found'; end if;
  perform public.erp_advance_cloud_maintenance_workflow_pre_r54_valuation(p_company_id,p_order_id);
  select workflow_stage into v_after from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id and not is_deleted;
  if v_before='stock_issue_draft' and v_after='stock_issue_approved' then
    perform public.erp_r53_consume_maintenance_fifo(p_company_id,p_order_id,v_effective);
    perform public.erp_r54_allocate_maintenance_line_costs(p_company_id,p_order_id);
  end if;
end;
$$;

-- Preserve an operational receipt layer when the legacy invoice engine reaches
-- its historical UPSERT. The invoice may attach accounting metadata, but must
-- not reset quantity already consumed after receipt.
create or replace function public.erp_r54_preserve_receipt_layer_valuation()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if old.receipt_id is not null and old.source_type='purchase_receipt'
     and new.source_type='purchase_invoice' then
    new.original_quantity:=old.original_quantity;
    new.remaining_quantity:=old.remaining_quantity;
    new.unit_cost:=old.unit_cost;
    new.currency:=old.currency;
    new.asset_account_id:=old.asset_account_id;
    new.cost_expense_account_id:=old.cost_expense_account_id;
    new.source_type:=old.source_type;
    new.status:=old.status;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_r54_preserve_receipt_layer_valuation on public.erp_inventory_cost_layers;
create trigger trg_r54_preserve_receipt_layer_valuation before update
on public.erp_inventory_cost_layers for each row
execute function public.erp_r54_preserve_receipt_layer_valuation();

create or replace function public.erp_r22_post_purchase_invoice_direct(
  p_company_id uuid,p_invoice_id uuid
) returns jsonb language plpgsql security definer set search_path=public as $$
declare d public.erp_commercial_workflow_documents%rowtype; v_receipt uuid;
  v_invoice_total numeric; v_layer_total numeric; v_result jsonb;
begin
  select * into d from public.erp_commercial_workflow_documents
  where company_id=p_company_id and id=p_invoice_id and module='purchases'
    and document_type='invoice' and not is_deleted for update;
  if not found then raise exception 'workflow_invoice_not_found'; end if;
  if d.status='approved' then
    return public.erp_r22_post_purchase_invoice_direct_pre_r54_valuation(p_company_id,p_invoice_id);
  end if;
  v_receipt:=nullif(d.payload->>'logisticsDocumentId','')::uuid;
  v_invoice_total:=public.erp_try_numeric(d.payload->>'totalAmount',0);
  select coalesce(sum(original_quantity*unit_cost),0) into v_layer_total
  from public.erp_inventory_cost_layers
  where company_id=p_company_id and receipt_id=v_receipt and source_type='purchase_receipt';
  if v_receipt is null or v_layer_total<=0 then raise exception 'purchase_receipt_valuation_required'; end if;
  if abs(v_invoice_total-v_layer_total)>0.01 then
    raise exception 'purchase_invoice_operational_valuation_mismatch:%:%',v_invoice_total,v_layer_total;
  end if;
  v_result:=public.erp_r22_post_purchase_invoice_direct_pre_r54_valuation(p_company_id,p_invoice_id);
  update public.erp_commercial_workflow_documents set payload=payload||jsonb_build_object(
    'operationalValuationPreserved',true,'operationalValuationTotal',v_layer_total)
  where company_id=p_company_id and id=p_invoice_id;
  return v_result||jsonb_build_object('operationalValuationPreserved',true);
end;
$$;

-- R53 remains historical. Replace only the current callable wrapper so invoice
-- posting reuses the issue-owned FIFO rows and then attaches the journal ID.
create or replace function public.erp_v736_post_maintenance_invoice(
  p_company_id uuid,p_order_id uuid
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_order public.erp_maintenance_orders%rowtype; v_currency text;
  v_partner_account text; v_result jsonb; v_entry jsonb;
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['maintenance.approve']);
  select * into v_order from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found then raise exception 'maintenance_order_not_found'; end if;
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
  perform public.erp_r54_allocate_maintenance_line_costs(p_company_id,p_order_id);
  v_result:=public.erp_v736_post_maintenance_invoice_pre_r49_identity(p_company_id,p_order_id);
  for v_entry in select value from jsonb_array_elements(coalesce(v_result->'costJournalEntries','[]'::jsonb)) loop
    update public.erp_inventory_fifo_consumptions fc set journal_entry_id=v_entry->>'journalEntryId'
    from public.erp_inventory_cost_layers l
    where fc.company_id=p_company_id and fc.delivery_id=p_order_id
      and fc.sales_order_id=p_order_id and fc.status='active' and l.id=fc.layer_id
      and upper(l.currency)=upper(v_entry->>'currency');
  end loop;
  return v_result||jsonb_build_object('fifoValuationApplied',true,'fifoValuationOwner','material_issue');
end;
$$;

revoke all on function public.erp_r54_refresh_receipt_valuation(uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_r54_consume_sales_delivery_fifo(uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_r54_allocate_maintenance_line_costs(uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_r54_preserve_receipt_layer_valuation() from public,anon,authenticated;
revoke all on function public.erp_approve_cloud_purchase_receipt_pre_r54_valuation(uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_approve_cloud_sales_delivery_pre_r54_valuation(uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_advance_cloud_maintenance_workflow_pre_r54_valuation(uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_r22_post_purchase_invoice_direct_pre_r54_valuation(uuid,uuid) from public,anon,authenticated;
grant execute on function public.erp_r54_refresh_receipt_valuation(uuid,uuid) to service_role;
grant execute on function public.erp_r54_consume_sales_delivery_fifo(uuid,uuid) to service_role;
grant execute on function public.erp_r54_allocate_maintenance_line_costs(uuid,uuid) to service_role;
grant execute on function public.erp_r22_post_purchase_invoice_direct(uuid,uuid) to service_role;
grant execute on function public.erp_approve_cloud_purchase_receipt(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_approve_cloud_sales_delivery(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_advance_cloud_maintenance_workflow(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_v736_post_maintenance_invoice(uuid,uuid) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
