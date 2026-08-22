begin;

create or replace function public.erp_v736_post_sales_invoice_costs(
  p_company_id uuid,p_invoice_id uuid,p_order_id uuid,p_delivery_id uuid,p_effective_at timestamptz
) returns jsonb language plpgsql security definer set search_path=public as $$
declare d record; c record; e record; v_old text; v_currency text;
  v_lines_by_currency jsonb:='{}'; v_lines jsonb; v_entries jsonb:='[]';
  v_breakdown jsonb:='[]'; v_entry text; v_delivery_ids uuid[];
begin
  select array_agg(id order by effective_at,created_at,id) into v_delivery_ids
  from public.erp_commercial_workflow_documents where company_id=p_company_id and parent_id=p_order_id
    and module='sales' and document_type='delivery' and status='approved' and not is_deleted;
  if coalesce(array_length(v_delivery_ids,1),0)=0 or not (p_delivery_id=any(v_delivery_ids)) then
    raise exception 'approved_sales_delivery_required';
  end if;
  for d in select id,payload from public.erp_commercial_workflow_documents
    where company_id=p_company_id and id=any(v_delivery_ids) for update
  loop
    v_old:=nullif(coalesce(d.payload->>'fifoCostJournalEntryId',d.payload->>'costJournalEntryId'),'');
    perform public.erp_v736_void_journal_id(p_company_id,v_old);
    perform public.erp_phase2_void_reference_journals(p_company_id,'sales_inventory_fifo',d.id::text);
  end loop;
  if not exists(select 1 from public.erp_inventory_fifo_consumptions where company_id=p_company_id
    and delivery_id=any(v_delivery_ids) and sales_order_id=p_order_id and status='active') then
    raise exception 'sales_delivery_fifo_valuation_required';
  end if;
  for c in select fc.*,layer.currency,layer.asset_account_id,layer.cost_expense_account_id,layer.layer_number
    from public.erp_inventory_fifo_consumptions fc join public.erp_inventory_cost_layers layer on layer.id=fc.layer_id
    where fc.company_id=p_company_id and fc.delivery_id=any(v_delivery_ids)
      and fc.sales_order_id=p_order_id and fc.status='active'
    order by layer.currency,layer.effective_at,layer.created_at,fc.delivery_id
  loop
    v_currency:=upper(c.currency);
    v_lines:=coalesce(v_lines_by_currency->v_currency,'[]')||jsonb_build_array(
      jsonb_build_object('accountId',c.cost_expense_account_id,'debit',c.total_cost,'credit',0,
        'description','تكلفة بيع حسب الفاتورة','itemType',c.item_type,'itemId',c.item_id,
        'warehouseId',c.warehouse_id,'deliveryId',c.delivery_id,'layerId',c.layer_id,
        'layerNumber',c.layer_number,'quantity',c.quantity,'unitCost',c.unit_cost),
      jsonb_build_object('accountId',c.asset_account_id,'debit',0,'credit',c.total_cost,
        'description','إخراج كلفة المخزون حسب الفاتورة','itemType',c.item_type,'itemId',c.item_id,
        'warehouseId',c.warehouse_id,'deliveryId',c.delivery_id,'layerId',c.layer_id,
        'layerNumber',c.layer_number,'quantity',c.quantity,'unitCost',c.unit_cost));
    v_lines_by_currency:=jsonb_set(v_lines_by_currency,array[v_currency],v_lines,true);
    v_breakdown:=v_breakdown||jsonb_build_array(jsonb_build_object('currency',v_currency,
      'deliveryId',c.delivery_id,'itemType',c.item_type,'itemId',c.item_id,'warehouseId',c.warehouse_id,
      'layerId',c.layer_id,'layerNumber',c.layer_number,'quantity',c.quantity,
      'unitCost',c.unit_cost,'totalCost',c.total_cost));
  end loop;
  for e in select key,value from jsonb_each(v_lines_by_currency) loop
    v_entry:=public.erp_phase2_insert_journal_at(p_company_id,'sales_invoice_cost_'||lower(e.key),p_invoice_id::text,
      public.erp_next_document_number(p_company_id,'sales_cost_journal_'||lower(e.key),'SIC-'||e.key,p_effective_at),
      'قيد كلفة فاتورة البيع حسب عملة المخزون',e.key,e.value,p_effective_at);
    update public.erp_inventory_fifo_consumptions fc set journal_entry_id=v_entry
    from public.erp_inventory_cost_layers layer where fc.company_id=p_company_id
      and fc.delivery_id=any(v_delivery_ids) and fc.sales_order_id=p_order_id and fc.status='active'
      and layer.id=fc.layer_id and upper(layer.currency)=upper(e.key);
    v_entries:=v_entries||jsonb_build_array(jsonb_build_object('currency',e.key,'journalEntryId',v_entry));
  end loop;
  update public.erp_commercial_workflow_documents set payload=(payload-'costJournalEntryId'-'fifoCostJournalEntryId')||
    jsonb_build_object('accountingOwner','invoice','accountedByInvoiceId',p_invoice_id::text,
      'valuationPendingInvoice',false,'invoiceCostPostedAt',now()),updated_at=now()
    where company_id=p_company_id and id=any(v_delivery_ids);
  update public.erp_commercial_workflow_documents set payload=payload||jsonb_build_object(
    'logisticsDocumentIds',to_jsonb(v_delivery_ids)) where company_id=p_company_id and id=p_invoice_id;
  return jsonb_build_object('journalEntries',v_entries,'breakdown',v_breakdown,
    'logisticsDocumentIds',to_jsonb(v_delivery_ids));
end $$;

revoke all on function public.erp_v736_post_sales_invoice_costs(uuid,uuid,uuid,uuid,timestamptz)
  from public,anon,authenticated;
grant execute on function public.erp_v736_post_sales_invoice_costs(uuid,uuid,uuid,uuid,timestamptz)
  to service_role;

commit;
