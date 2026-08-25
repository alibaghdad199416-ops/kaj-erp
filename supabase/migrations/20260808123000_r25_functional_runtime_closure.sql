-- R25 functional runtime closure
begin;

create or replace function public.erp_cancel_cloud_workflow_invoice(
  p_company_id uuid,p_invoice_id uuid,p_module text,p_reason text default null
) returns void language plpgsql security definer set search_path=public as $$
declare d public.erp_commercial_workflow_documents%rowtype; j jsonb; s jsonb; v_delivery uuid;
begin
  if p_module not in ('sales','purchases') then raise exception 'invalid workflow module'; end if;
  perform public.erp_require_any_cloud_permission(p_company_id,
    case when p_module='sales' then array['sales.cancel','sales.update','sales.delete'] else array['purchases.cancel','purchases.update','purchases.delete'] end);
  select * into d from public.erp_commercial_workflow_documents
   where company_id=p_company_id and id=p_invoice_id and module=p_module
     and document_type='invoice' and not is_deleted for update;
  if not found then raise exception 'workflow_invoice_not_found'; end if;
  if d.status='cancelled' then return; end if;
  if jsonb_array_length(coalesce(d.payload->'payments','[]'::jsonb))>0 then
    raise exception 'reverse_invoice_payments_first';
  end if;

  perform public.erp_v736_void_journal_id(p_company_id,d.payload->>'journalEntryId');
  for j in select value from jsonb_array_elements(coalesce(d.payload->'costJournalEntries','[]'::jsonb)) loop
    perform public.erp_v736_void_journal_id(p_company_id,j->>'journalEntryId');
  end loop;

  if p_module='sales' then
    v_delivery:=nullif(d.payload->>'logisticsDocumentId','')::uuid;
    if v_delivery is not null then
      update public.erp_inventory_cost_layers l set
        remaining_quantity=least(l.original_quantity,l.remaining_quantity+fc.quantity),
        status='active',updated_at=now(),updated_by=auth.uid()
      from public.erp_inventory_fifo_consumptions fc
      where fc.company_id=p_company_id and fc.delivery_id=v_delivery and fc.status='active' and l.id=fc.layer_id;
      update public.erp_inventory_fifo_consumptions set status='reversed',reversed_at=now()
       where company_id=p_company_id and delivery_id=v_delivery and status='active';
      update public.erp_commercial_workflow_documents set payload=payload||jsonb_build_object(
        'valuationPendingInvoice',true,'accountedByInvoiceId',null,'invoiceCostReversedAt',now()),updated_at=now()
       where company_id=p_company_id and id=v_delivery;
    end if;
    for s in select value from jsonb_array_elements(coalesce(d.payload->'valuationSnapshots','[]'::jsonb)) loop
      if s->>'itemType'='car' then
        update public.erp_cars set data=data||jsonb_build_object(
          'salePrice',public.erp_try_numeric(s->>'previousSalePrice',0),
          'sale_price',public.erp_try_numeric(s->>'previousSalePrice',0),
          'saleCurrency',s->>'previousSaleCurrency','sale_currency',s->>'previousSaleCurrency',
          'valuationUpdatedByInvoiceId',null,'updatedAt',now()),updated_at=now(),updated_by=auth.uid()
        where company_id=p_company_id and id=s->>'itemId' and not is_deleted;
      else
        update public.erp_inventory set data=data||jsonb_build_object(
          'salePrice',public.erp_try_numeric(s->>'previousSalePrice',0),
          'sale_price',public.erp_try_numeric(s->>'previousSalePrice',0),
          'saleCurrency',s->>'previousSaleCurrency','sale_currency',s->>'previousSaleCurrency',
          'valuationUpdatedByInvoiceId',null,'updatedAt',now()),updated_at=now(),updated_by=auth.uid()
        where company_id=p_company_id and id=s->>'itemId' and not is_deleted;
      end if;
    end loop;
    if d.status='approved' then
      perform public.erp_restore_sales_order_cars_after_invoice_cancel(p_company_id,d.parent_id,p_invoice_id);
    end if;
  else
    if exists(
      select 1 from public.erp_inventory_fifo_consumptions fc
      join public.erp_inventory_cost_layers l on l.id=fc.layer_id
      where l.company_id=p_company_id and l.receipt_id=nullif(d.payload->>'logisticsDocumentId','')::uuid
        and fc.status='active'
    ) then raise exception 'purchase_invoice_cost_already_consumed'; end if;
    update public.erp_inventory_cost_layers set remaining_quantity=0,status='reversed',updated_at=now(),updated_by=auth.uid()
     where company_id=p_company_id and receipt_id=nullif(d.payload->>'logisticsDocumentId','')::uuid
       and source_type='purchase_invoice' and status<>'reversed';
    for s in select value from jsonb_array_elements(coalesce(d.payload->'valuationSnapshots','[]'::jsonb)) loop
      if s->>'itemType'='car' then
        update public.erp_cars set data=data||jsonb_build_object(
          'purchasePrice',public.erp_try_numeric(s->>'previousPurchasePrice',0),
          'purchase_price',public.erp_try_numeric(s->>'previousPurchasePrice',0),
          'costCurrency',s->>'previousCostCurrency','cost_currency',s->>'previousCostCurrency',
          'valuationPendingInvoice',true,'valuationUpdatedByInvoiceId',null,'updatedAt',now()),
          updated_at=now(),updated_by=auth.uid()
        where company_id=p_company_id and id=s->>'itemId' and not is_deleted;
      else
        update public.erp_warehouse_stock set data=data||jsonb_build_object(
          'averageUnitCost',public.erp_try_numeric(s->>'previousAverageUnitCost',0),
          'valuationPendingInvoice',true,'valuationInvoiceId',null,'updatedAt',now()),
          updated_at=now(),updated_by=auth.uid()
        where company_id=p_company_id and not is_deleted
          and coalesce(data->>'productId',data->>'product_id')=s->>'itemId'
          and coalesce(data->>'warehouseId',data->>'warehouse_id')=s->>'warehouseId';
        update public.erp_inventory set data=data||jsonb_build_object(
          'purchasePrice',public.erp_try_numeric(s->>'previousPurchasePrice',0),
          'purchase_price',public.erp_try_numeric(s->>'previousPurchasePrice',0),
          'unitCost',public.erp_try_numeric(s->>'previousUnitCost',0),
          'unit_cost',public.erp_try_numeric(s->>'previousUnitCost',0),
          'costCurrency',s->>'previousCostCurrency','cost_currency',s->>'previousCostCurrency',
          'valuationPendingInvoice',true,'valuationUpdatedByInvoiceId',null,'updatedAt',now()),
          updated_at=now(),updated_by=auth.uid()
        where company_id=p_company_id and id=s->>'itemId' and not is_deleted;
        perform public.erp_inventory_refresh_product(p_company_id,s->>'itemId');
      end if;
    end loop;
    update public.erp_commercial_workflow_documents set payload=payload||jsonb_build_object(
      'valuationPendingInvoice',true,'valuedByInvoiceId',null,'valuationReversedAt',now()),updated_at=now()
     where company_id=p_company_id and id=nullif(d.payload->>'logisticsDocumentId','')::uuid;
  end if;

  update public.erp_commercial_workflow_documents set status='cancelled',
    payload=payload||jsonb_build_object('reason',p_reason,'cancelledAt',now(),
      'valuationApplied',false,'accountingReversedAt',now()),updated_at=now()
   where company_id=p_company_id and id=p_invoice_id;
  perform public.erp_commercial_audit(p_company_id,p_module,d.parent_id,d.id,d.document_number,
    'cancel_invoice',d.status,'cancelled',p_reason);
end;
$$;

-- Delivery is the operational handoff for a vehicle. Refresh canonical state
-- immediately so the UI sees pending_sale before invoice approval.
create or replace function public.erp_phase2_approve_sales_delivery(p_company_id uuid,p_delivery_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_order uuid; r record;
begin
  perform public.erp_approve_cloud_sales_delivery(p_company_id,p_delivery_id);
  select parent_id into v_order from public.erp_commercial_workflow_documents
   where company_id=p_company_id and id=p_delivery_id and module='sales' and document_type='delivery' and not is_deleted;
  if v_order is not null then
    for r in select distinct item_id from public.erp_sales_order_items_cloud
      where company_id=p_company_id and order_id=v_order and item_type='car' and not is_deleted
    loop
      perform public.erp_v732_refresh_car_state(p_company_id,r.item_id,null);
    end loop;
  end if;
end $$;

-- An approved delivery may advance the order summary beyond literal 'approved'.
-- Invoice creation is based on the immutable approved logistics document, not a stale order status string.
create or replace function public.erp_create_cloud_sales_workflow_invoice(p_company_id uuid,p_order_id uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid:=gen_random_uuid(); o public.erp_sales_orders_cloud%rowtype; l jsonb; v_number text;
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['sales.create','sales.update','sales.approve']);
  select * into o from public.erp_sales_orders_cloud where company_id=p_company_id and id=p_order_id and not is_deleted
    and lower(coalesce(status,'')) not in ('draft','cancelled','canceled','reversed','deleted','void') for update;
  if not found then raise exception 'active_approved_sales_order_required'; end if;
  l:=public.erp_v736_active_logistics(p_company_id,p_order_id,'sales');
  if nullif(l->>'id','') is null then raise exception 'approved_sales_delivery_required'; end if;
  if exists(select 1 from public.erp_commercial_workflow_documents where company_id=p_company_id and parent_id=p_order_id and module='sales' and document_type='invoice' and not is_deleted and status<>'cancelled') then
    raise exception 'active_sales_invoice_exists';
  end if;
  v_number:=public.erp_next_document_number(p_company_id,'sales_invoice','SI',coalesce(o.effective_at,o.created_at));
  insert into public.erp_commercial_workflow_documents(id,company_id,module,document_type,parent_id,document_number,payload,effective_at)
  values(v_id,p_company_id,'sales','invoice',p_order_id,v_number,jsonb_build_object(
    'currency',o.currency,'totalAmount',o.total,'paidAmount',0,'remainingAmount',o.total,
    'paymentStatus','unpaid','payments','[]'::jsonb,'createdBy',auth.uid(),
    'logisticsDocumentId',l->>'id','logisticsDocumentNumber',l->>'number',
    'allocations',l->'allocations','warehouseIds',l->'warehouseIds','accountingOwner','invoice'),coalesce(o.effective_at,o.created_at));
  perform public.erp_commercial_audit(p_company_id,'sales',p_order_id,v_id,v_number,'create_invoice',null,'draft','approved delivery is authoritative');
  return v_id;
end $$;

-- Sold vehicles are maintenance assets even after they leave warehouse inventory.
create or replace function public.erp_r9_list_cloud_maintenance_eligible_cars(p_company_id uuid)
returns setof jsonb language sql stable security definer set search_path=public as $$
  with sold as (
    select distinct on (i.item_id)
      i.item_id car_id,o.customer_id,d.id invoice_id,
      row_number() over(partition by i.item_id order by coalesce(d.effective_at,d.updated_at,d.created_at) desc,d.id desc)::int sale_sequence
    from public.erp_sales_order_items_cloud i
    join public.erp_sales_orders_cloud o on o.company_id=i.company_id and o.id=i.order_id and not o.is_deleted
    join public.erp_commercial_workflow_documents d on d.company_id=i.company_id and d.parent_id=i.order_id
      and d.module='sales' and d.document_type='invoice' and d.status='approved' and not d.is_deleted
    where i.company_id=p_company_id and i.item_type='car' and not i.is_deleted
    order by i.item_id,coalesce(d.effective_at,d.updated_at,d.created_at) desc,d.id desc
  )
  select public.erp_r9_filter_result_json(p_company_id,'maintenance',jsonb_build_object(
    'carId',c.id,'displayName',concat_ws(' • ',concat_ws(' ',c.data->>'brand',c.data->>'model',c.data->>'year'),nullif(c.data->>'chassis',''),nullif(c.data->>'plateNumber',''),nullif(c.data->>'carNumber','')),
    'customerId',s.customer_id,'customerName',coalesce(cu.data->>'name',concat_ws(' ',cu.data->>'firstName',cu.data->>'lastName'),s.customer_id::text),
    'saleSequence',s.sale_sequence,'salesInvoiceId',s.invoice_id
  ),'maintenance.view')
  from sold s join public.erp_cars c on c.company_id=p_company_id and c.id=s.car_id and not c.is_deleted
  left join public.erp_customers cu on cu.company_id=p_company_id and cu.id=s.customer_id::text and not cu.is_deleted
  where public.is_active_company_member(p_company_id)
$$;

-- Cashbox save has one canonical ledger field. The selected current account wins
-- and is persisted to both legacy spellings; duplicate active bindings are rejected.
create or replace function public.erp_r9_save_cloud_cash_account(p_company_id uuid,p_account jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare v_old jsonb; v_guarded jsonb; v_id text:=coalesce(p_account->>'id',''); v_ledger text;
begin
  select data into v_old from public.erp_cash_accounts where company_id=p_company_id and id=v_id and not is_deleted;
  if v_old is null then
    perform public.erp_r9_require_field_edit(p_company_id,'cashbox','name','accounting.create');
  elsif not public.erp_cloud_user_has_permission(p_company_id,'accounting.update') then
    raise exception 'permission_denied:accounting.update' using errcode='42501';
  end if;
  v_guarded:=public.erp_r24_guard_cash_account_payload(p_company_id,coalesce(v_old,'{}'::jsonb),p_account);
  v_ledger:=nullif(btrim(coalesce(v_guarded->>'accountId',v_guarded->>'account_id','')),'');
  if v_ledger is not null then
    if exists(select 1 from public.erp_cash_accounts x where x.company_id=p_company_id and x.id<>v_id and not x.is_deleted and public.erp_r23_cashbox_ledger_account_id(x.data)=v_ledger) then
      raise exception 'cashbox_ledger_account_already_bound:%',v_ledger using errcode='23505';
    end if;
    v_guarded:=v_guarded||jsonb_build_object('accountId',v_ledger,'account_id',v_ledger);
  end if;
  perform public.erp_save_cloud_cash_account(p_company_id,v_guarded);
end $$;

grant execute on function public.erp_phase2_approve_sales_delivery(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_create_cloud_sales_workflow_invoice(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r9_list_cloud_maintenance_eligible_cars(uuid) to authenticated,service_role;
grant execute on function public.erp_r9_save_cloud_cash_account(uuid,jsonb) to authenticated,service_role;
notify pgrst,'reload schema';

commit;
