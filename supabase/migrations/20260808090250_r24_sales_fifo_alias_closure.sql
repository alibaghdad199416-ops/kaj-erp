-- R24 sales FIFO closure: avoid PL/pgSQL record-variable/SQL-alias ambiguity in invoice cost posting.
begin;

create or replace function public.erp_v736_post_sales_invoice_costs(
  p_company_id uuid,p_invoice_id uuid,p_order_id uuid,p_delivery_id uuid,p_effective_at timestamptz
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  d public.erp_commercial_workflow_documents%rowtype; a record; l public.erp_inventory_cost_layers%rowtype;
  v_accounts jsonb; v_data jsonb; v_needed numeric; v_existing numeric; v_take numeric;
  v_cost numeric; v_currency text; v_lines_by_currency jsonb:='{}'::jsonb;
  v_lines jsonb; v_entries jsonb:='[]'::jsonb; v_breakdown jsonb:='[]'::jsonb;
  c record; e record; v_entry text; v_old text;
begin
  select * into d from public.erp_commercial_workflow_documents
   where company_id=p_company_id and id=p_delivery_id and parent_id=p_order_id
     and module='sales' and document_type='delivery' and status='approved' and not is_deleted for update;
  if not found then raise exception 'approved_sales_delivery_required'; end if;

  -- Remove any journal created by older delivery-owned accounting, while
  -- preserving its active FIFO consumptions as the cost source for this invoice.
  v_old:=nullif(coalesce(d.payload->>'fifoCostJournalEntryId',d.payload->>'costJournalEntryId'),'');
  perform public.erp_v736_void_journal_id(p_company_id,v_old);
  perform public.erp_phase2_void_reference_journals(p_company_id,'sales_inventory_fifo',p_delivery_id::text);

  for a in
    select x."itemType",x."itemId",max(x."description") "description",
           x."warehouseId",sum(x.quantity) quantity
    from jsonb_to_recordset(d.payload->'allocations') as x(
      "itemType" text,"itemId" text,"description" text,"warehouseId" text,quantity numeric)
    group by x."itemType",x."itemId",x."warehouseId"
  loop
    select coalesce(sum(fc.quantity),0) into v_existing
    from public.erp_inventory_fifo_consumptions fc
    where fc.company_id=p_company_id and fc.delivery_id=p_delivery_id and fc.status='active'
      and fc.item_type=a."itemType" and fc.item_id=a."itemId" and fc.warehouse_id=a."warehouseId";
    v_needed:=a.quantity-v_existing;
    if v_needed<0 then raise exception 'invoice_quantity_below_existing_cost_consumption:%',a."description"; end if;

    if v_needed>0 and not exists(
      select 1 from public.erp_inventory_cost_layers x
      where x.company_id=p_company_id and x.item_type=a."itemType" and x.item_id=a."itemId"
        and x.warehouse_id=a."warehouseId" and x.status in ('active','consumed')
        and x.remaining_quantity>0 and x.effective_at<=p_effective_at
    ) then
      v_accounts:=public.erp_v736_item_accounting(p_company_id,a."itemType",a."itemId",null);
      v_data:=v_accounts->'data';
      if a."itemType"='car' then
        v_cost:=public.erp_try_numeric(v_data->>'purchasePrice',public.erp_try_numeric(v_data->>'costPrice',0))+
                public.erp_try_numeric(v_data->>'maintenanceCost',public.erp_try_numeric(v_data->>'maintenance_cost',0));
      else
        v_cost:=public.erp_try_numeric(v_data->>'unitCost',
          public.erp_try_numeric(v_data->>'unit_cost',public.erp_try_numeric(v_data->>'purchasePrice',0)));
      end if;
      insert into public.erp_inventory_cost_layers(
        company_id,item_type,item_id,warehouse_id,layer_number,effective_at,
        original_quantity,remaining_quantity,unit_cost,currency,asset_account_id,
        cost_expense_account_id,source_type
      ) values(
        p_company_id,a."itemType",a."itemId",a."warehouseId",
        'OPEN-INV-'||substr(replace(p_invoice_id::text,'-',''),1,16)||'-'||substr(md5(a."itemId"||a."warehouseId"),1,6),
        p_effective_at,v_needed,v_needed,greatest(v_cost,0),v_accounts->>'costCurrency',
        v_accounts->>'assetAccountId',v_accounts->>'costExpenseAccountId','invoice_opening'
      );
    end if;

    for l in
      select * from public.erp_inventory_cost_layers x
      where x.company_id=p_company_id and x.item_type=a."itemType" and x.item_id=a."itemId"
        and x.warehouse_id=a."warehouseId" and x.status in ('active','consumed')
        and x.remaining_quantity>0 and x.effective_at<=p_effective_at
      order by x.effective_at,x.created_at,x.id for update
    loop
      exit when v_needed<=0;
      v_take:=least(v_needed,l.remaining_quantity);
      update public.erp_inventory_cost_layers set remaining_quantity=remaining_quantity-v_take,
        status=case when remaining_quantity-v_take<=0 then 'consumed' else 'active' end,
        updated_at=now(),updated_by=auth.uid() where id=l.id;
      insert into public.erp_inventory_fifo_consumptions(
        company_id,delivery_id,sales_order_id,layer_id,item_type,item_id,warehouse_id,
        quantity,unit_cost,effective_at,status
      ) values(
        p_company_id,p_delivery_id,p_order_id,l.id,a."itemType",a."itemId",a."warehouseId",
        v_take,l.unit_cost,p_effective_at,'active'
      ) on conflict(company_id,delivery_id,layer_id) do update set
        quantity=excluded.quantity,unit_cost=excluded.unit_cost,effective_at=excluded.effective_at,
        status='active',reversed_at=null;
      v_needed:=v_needed-v_take;
    end loop;
    if v_needed>0 then raise exception 'insufficient_invoice_cost_layers:%',a."description"; end if;
  end loop;

  for c in
    select fc.*,layer.currency,layer.asset_account_id,layer.cost_expense_account_id,layer.layer_number
    from public.erp_inventory_fifo_consumptions fc
    join public.erp_inventory_cost_layers layer on layer.id=fc.layer_id
    where fc.company_id=p_company_id and fc.delivery_id=p_delivery_id and fc.status='active'
    order by layer.currency,layer.effective_at,layer.created_at
  loop
    v_currency:=upper(c.currency);
    v_lines:=coalesce(v_lines_by_currency->v_currency,'[]'::jsonb)||jsonb_build_array(
      jsonb_build_object('accountId',c.cost_expense_account_id,'debit',c.total_cost,'credit',0,
        'description','تكلفة بيع حسب الفاتورة','itemType',c.item_type,'itemId',c.item_id,
        'warehouseId',c.warehouse_id,'layerId',c.layer_id,'layerNumber',c.layer_number,
        'quantity',c.quantity,'unitCost',c.unit_cost),
      jsonb_build_object('accountId',c.asset_account_id,'debit',0,'credit',c.total_cost,
        'description','إخراج كلفة المخزون حسب الفاتورة','itemType',c.item_type,'itemId',c.item_id,
        'warehouseId',c.warehouse_id,'layerId',c.layer_id,'layerNumber',c.layer_number,
        'quantity',c.quantity,'unitCost',c.unit_cost)
    );
    v_lines_by_currency:=jsonb_set(v_lines_by_currency,array[v_currency],v_lines,true);
    v_breakdown:=v_breakdown||jsonb_build_array(jsonb_build_object(
      'currency',v_currency,'itemType',c.item_type,'itemId',c.item_id,'warehouseId',c.warehouse_id,
      'layerId',c.layer_id,'layerNumber',c.layer_number,'quantity',c.quantity,
      'unitCost',c.unit_cost,'totalCost',c.total_cost));
  end loop;

  for e in select key,value from jsonb_each(v_lines_by_currency) loop
    v_entry:=public.erp_phase2_insert_journal_at(
      p_company_id,'sales_invoice_cost_'||lower(e.key),p_invoice_id::text,
      public.erp_next_document_number(p_company_id,'sales_cost_journal_'||lower(e.key),'SIC-'||e.key,p_effective_at),
      'قيد كلفة فاتورة البيع حسب عملة المخزون',e.key,e.value,p_effective_at);
    update public.erp_inventory_fifo_consumptions fc set journal_entry_id=v_entry
    from public.erp_inventory_cost_layers layer
    where fc.company_id=p_company_id and fc.delivery_id=p_delivery_id and fc.status='active'
      and layer.id=fc.layer_id and upper(layer.currency)=upper(e.key);
    v_entries:=v_entries||jsonb_build_array(jsonb_build_object('currency',e.key,'journalEntryId',v_entry));
  end loop;

  update public.erp_commercial_workflow_documents set
    payload=(payload-'costJournalEntryId'-'fifoCostJournalEntryId')||jsonb_build_object(
      'accountingOwner','invoice','accountedByInvoiceId',p_invoice_id::text,
      'valuationPendingInvoice',false,'invoiceCostPostedAt',now()),updated_at=now()
  where company_id=p_company_id and id=p_delivery_id;
  return jsonb_build_object('journalEntries',v_entries,'breakdown',v_breakdown);
end;
$$;

notify pgrst,'reload schema';
commit;
