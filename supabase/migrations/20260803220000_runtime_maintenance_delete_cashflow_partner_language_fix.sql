begin;

-- V6.5 runtime repair:
-- 1) Saving a maintenance draft validates line shape but does not consume or
--    reserve stock. Stock sufficiency remains enforced when the stock issue is
--    approved.
-- 2) Cash receipts, payments, transfers and their journal links are deleted in
--    one transaction, including historical camelCase/snake_case aliases.
-- 3) Journal deletion routes to the owning source whenever possible and safely
--    deletes an orphaned entry when the historical source no longer exists.
-- 4) Sales/purchase cascade deletion reverses every active logistics document,
--    invoice, payment and journal before soft deletion.

create or replace function public.erp_phase3_prepare_maintenance_lines(
  p_company_id uuid,
  p_order_id uuid,
  p_currency text,
  p_lines jsonb
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  x jsonb;
  v_product text;
  v_warehouse text;
  v_qty numeric;
  v_name text;
  v_cost numeric;
  v_price numeric;
  v_type text;
  v_stock public.erp_warehouse_stock%rowtype;
  v_cost_total numeric:=0;
  v_price_total numeric:=0;
begin
  perform public.erp_active_company_context(p_company_id);
  if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then
    raise exception 'أضف مادة أو خدمة صيانة واحدة على الأقل';
  end if;

  update public.erp_maintenance_parts
     set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid()
   where company_id=p_company_id
     and maintenance_order_id=p_order_id
     and not is_deleted;

  for x in select value from jsonb_array_elements(p_lines) loop
    v_product:=nullif(btrim(coalesce(x->>'product_id',x->>'productId','')),'');
    v_warehouse:=nullif(btrim(coalesce(x->>'warehouse_id',x->>'warehouseId','')),'');
    v_qty:=public.erp_try_numeric(x->>'quantity',0);
    v_price:=public.erp_try_numeric(coalesce(x->>'unit_price',x->>'unitPrice'),0);
    if v_product is null or v_qty<=0 or v_price<0 then
      raise exception 'بيانات بند الصيانة غير صحيحة';
    end if;

    select coalesce(
             nullif(data->>'name',''),
             nullif(data->>'nameAr',''),
             nullif(data->>'name_ar',''),
             nullif(data->>'nameEn',''),
             id
           ),
           lower(coalesce(nullif(data->>'itemType',''),nullif(data->>'item_type',''),'stock')),
           public.erp_try_numeric(
             coalesce(data->>'unitCost',data->>'purchasePrice',data->>'averageUnitCost'),
             0
           )
      into v_name,v_type,v_cost
      from public.erp_inventory
     where company_id=p_company_id and id=v_product and not is_deleted
     limit 1;
    if not found then
      raise exception 'بند الصيانة غير موجود: %',v_product;
    end if;

    if v_type='service' then
      v_warehouse:=null;
      v_cost:=0;
    else
      if v_warehouse is null then
        raise exception 'يجب اختيار مخزن لكل مادة مخزنية';
      end if;
      select * into v_stock
        from public.erp_warehouse_stock
       where company_id=p_company_id and not is_deleted
         and coalesce(data->>'warehouseId',data->>'warehouse_id')=v_warehouse
         and coalesce(data->>'productId',data->>'product_id')=v_product
       limit 1;
      if found and public.erp_try_numeric(
        coalesce(v_stock.data->>'averageUnitCost',v_stock.data->>'average_unit_cost'),0
      )>0 then
        v_cost:=public.erp_try_numeric(
          coalesce(v_stock.data->>'averageUnitCost',v_stock.data->>'average_unit_cost'),0
        );
      end if;
      -- Draft creation must not fail because the item account or live quantity
      -- is not ready yet. Both are checked by the approval/posting workflow.
    end if;

    insert into public.erp_maintenance_parts(
      company_id,maintenance_order_id,product_id,source_product_id,product_name,
      warehouse_id,source_warehouse_id,quantity,unit_cost,total_cost,line_type,
      unit_price,line_total_price
    ) values(
      p_company_id,p_order_id,public.erp_stage3_stable_uuid(v_product),v_product,
      coalesce(v_name,v_product),
      case when v_warehouse is null then null else public.erp_stage3_stable_uuid(v_warehouse) end,
      v_warehouse,v_qty::integer,coalesce(v_cost,0),coalesce(v_cost,0)*v_qty,
      v_type,v_price,v_price*v_qty
    );
    v_cost_total:=v_cost_total+coalesce(v_cost,0)*v_qty;
    v_price_total:=v_price_total+v_price*v_qty;
  end loop;

  return jsonb_build_object('costTotal',v_cost_total,'priceTotal',v_price_total);
end;
$$;

-- Draft saving must also defer the optional maintenance expense-account
-- check. The account is validated by erp_phase3_post_maintenance_issue when
-- the stock issue is approved, not while the order is merely a draft.
do $$
begin
  if to_regprocedure(
    'public.erp_create_cloud_maintenance_order(uuid,text,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz)'
  ) is not null and to_regprocedure(
    'public.erp_create_cloud_maintenance_order_pre_v65(uuid,text,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz)'
  ) is null then
    alter function public.erp_create_cloud_maintenance_order(
      uuid,text,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz
    ) rename to erp_create_cloud_maintenance_order_pre_v65;
  end if;

  if to_regprocedure(
    'public.erp_update_cloud_maintenance_draft(uuid,uuid,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz)'
  ) is not null and to_regprocedure(
    'public.erp_update_cloud_maintenance_draft_pre_v65(uuid,uuid,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz)'
  ) is null then
    alter function public.erp_update_cloud_maintenance_draft(
      uuid,uuid,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz
    ) rename to erp_update_cloud_maintenance_draft_pre_v65;
  end if;
end $$;

create or replace function public.erp_create_cloud_maintenance_order(
  p_company_id uuid,p_car_id text,p_warehouse_id text,p_pricing_type text,
  p_labor_cost numeric,p_sale_price numeric,p_currency_code text,
  p_exchange_rate numeric,p_notes text,p_parts jsonb,
  p_maintenance_expense_account_id text default null,
  p_effective_at timestamptz default now()
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare v_id uuid;
begin
  v_id:=public.erp_create_cloud_maintenance_order_pre_v65(
    p_company_id,p_car_id,p_warehouse_id,p_pricing_type,p_labor_cost,
    p_sale_price,p_currency_code,p_exchange_rate,p_notes,p_parts,
    null,p_effective_at
  );
  update public.erp_maintenance_orders
     set maintenance_expense_account_id=nullif(btrim(p_maintenance_expense_account_id),''),
         updated_at=now(),updated_by=auth.uid()
   where company_id=p_company_id and id=v_id and not is_deleted;
  return v_id;
end;
$$;

-- Compatibility overload for clients that do not send an operational date.
create or replace function public.erp_create_cloud_maintenance_order(
  p_company_id uuid,p_car_id text,p_warehouse_id text,p_pricing_type text,
  p_labor_cost numeric,p_sale_price numeric,p_currency_code text,
  p_exchange_rate numeric,p_notes text,p_parts jsonb,
  p_maintenance_expense_account_id text default null
) returns uuid
language sql
security definer
set search_path=public
as $$
  select public.erp_create_cloud_maintenance_order(
    p_company_id,p_car_id,p_warehouse_id,p_pricing_type,p_labor_cost,
    p_sale_price,p_currency_code,p_exchange_rate,p_notes,p_parts,
    p_maintenance_expense_account_id,now()
  )
$$;

create or replace function public.erp_update_cloud_maintenance_draft(
  p_company_id uuid,p_order_id uuid,p_warehouse_id text,p_pricing_type text,
  p_labor_cost numeric,p_sale_price numeric,p_currency_code text,
  p_exchange_rate numeric,p_notes text,p_parts jsonb,
  p_maintenance_expense_account_id text default null,
  p_effective_at timestamptz default null
) returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  perform public.erp_update_cloud_maintenance_draft_pre_v65(
    p_company_id,p_order_id,p_warehouse_id,p_pricing_type,p_labor_cost,
    p_sale_price,p_currency_code,p_exchange_rate,p_notes,p_parts,
    null,p_effective_at
  );
  update public.erp_maintenance_orders
     set maintenance_expense_account_id=nullif(btrim(p_maintenance_expense_account_id),''),
         updated_at=now(),updated_by=auth.uid()
   where company_id=p_company_id and id=p_order_id and not is_deleted;
end;
$$;

revoke all on function public.erp_create_cloud_maintenance_order_pre_v65(
  uuid,text,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz
) from public,anon,authenticated;
revoke all on function public.erp_update_cloud_maintenance_draft_pre_v65(
  uuid,uuid,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz
) from public,anon,authenticated;
grant execute on function public.erp_create_cloud_maintenance_order(
  uuid,text,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz
) to authenticated,service_role;
grant execute on function public.erp_create_cloud_maintenance_order(
  uuid,text,text,text,numeric,numeric,text,numeric,text,jsonb,text
) to authenticated,service_role;
grant execute on function public.erp_update_cloud_maintenance_draft(
  uuid,uuid,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz
) to authenticated,service_role;

create or replace function public.erp_v65_soft_delete_journal(
  p_company_id uuid,
  p_entry_id text,
  p_reason text default null
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare v_now timestamptz:=now();
begin
  if nullif(btrim(p_entry_id),'') is null then return; end if;
  update public.erp_journal_lines
     set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid(),
         data=data||jsonb_build_object('deleteReason',p_reason,'deletedAt',v_now)
   where company_id=p_company_id and not is_deleted
     and coalesce(data->>'entryId',data->>'entry_id',data->>'journalEntryId',data->>'journal_entry_id')=p_entry_id;
  update public.erp_journal_entries
     set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid(),
         data=data||jsonb_build_object('deleteReason',p_reason,'deletedAt',v_now)
   where company_id=p_company_id and id=p_entry_id and not is_deleted;
end;
$$;

create or replace function public.erp_delete_cloud_cash_transfer(
  p_company_id uuid,
  p_transfer_id text
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_now timestamptz:=now();
  v_transaction record;
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['accounting.delete']);
  if nullif(btrim(p_transfer_id),'') is null then
    raise exception 'مرجع التحويل مطلوب';
  end if;

  perform 1 from public.erp_cash_transfers
   where company_id=p_company_id and id=p_transfer_id and not is_deleted
   for update;
  if not found then return; end if;

  for v_transaction in
    select id,coalesce(
      nullif(data->>'journalEntryId',''),nullif(data->>'journal_entry_id',''),
      nullif(data->>'entryId',''),nullif(data->>'entry_id','')
    ) as journal_id
    from public.erp_cash_transactions
    where company_id=p_company_id and not is_deleted
      and lower(coalesce(data->>'referenceType',data->>'reference_type','')) in
          ('cash_transfer','cash transfer','تحويل نقدي','تحويل بين الصناديق')
      and coalesce(data->>'referenceId',data->>'reference_id')=p_transfer_id
    for update
  loop
    perform public.erp_v65_soft_delete_journal(
      p_company_id,v_transaction.journal_id,'حذف تحويل الصناديق'
    );
    update public.erp_cash_transactions
       set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid(),
           data=data||jsonb_build_object('deleteReason','حذف تحويل الصناديق','deletedAt',v_now)
     where company_id=p_company_id and id=v_transaction.id and not is_deleted;
  end loop;

  -- Historical transfers can contain an orphaned journal without its cash row.
  for v_transaction in
    select id from public.erp_journal_entries
     where company_id=p_company_id and not is_deleted
       and lower(coalesce(data->>'referenceType',data->>'reference_type','')) in
           ('cash_transfer','cash transfer','تحويل نقدي','تحويل بين الصناديق')
       and coalesce(data->>'referenceId',data->>'reference_id')=p_transfer_id
  loop
    perform public.erp_v65_soft_delete_journal(
      p_company_id,v_transaction.id,'حذف تحويل الصناديق'
    );
  end loop;

  update public.erp_cash_transfers
     set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid(),
         data=data||jsonb_build_object('deleteReason','حذف تحويل الصناديق','deletedAt',v_now)
   where company_id=p_company_id and id=p_transfer_id and not is_deleted;
end;
$$;

create or replace function public.erp_delete_cloud_cash_transaction(
  p_company_id uuid,
  p_transaction_id text
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_transaction public.erp_cash_transactions%rowtype;
  v_journal_id text;
  v_reference_type text;
  v_reference_id text;
  v_now timestamptz:=now();
  v_doc record;
  v_new_payments jsonb;
  v_paid numeric;
  v_total numeric;
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['accounting.delete']);
  select * into v_transaction from public.erp_cash_transactions
   where company_id=p_company_id and id=p_transaction_id and not is_deleted
   for update;
  if not found then return; end if;

  v_journal_id:=coalesce(
    nullif(v_transaction.data->>'journalEntryId',''),
    nullif(v_transaction.data->>'journal_entry_id',''),
    nullif(v_transaction.data->>'entryId',''),
    nullif(v_transaction.data->>'entry_id','')
  );
  v_reference_type:=lower(btrim(coalesce(
    nullif(v_transaction.data->>'referenceType',''),
    nullif(v_transaction.data->>'reference_type',''),
    'manual_cash_transaction'
  )));
  v_reference_id:=coalesce(
    nullif(v_transaction.data->>'referenceId',''),
    nullif(v_transaction.data->>'reference_id','')
  );

  if v_reference_type in ('cash_transfer','cash transfer','تحويل نقدي','تحويل بين الصناديق')
     and v_reference_id is not null then
    perform public.erp_delete_cloud_cash_transfer(p_company_id,v_reference_id);
    return;
  end if;

  -- Remove the payment from any workflow invoice that still references this
  -- cash transaction or its journal, then recalculate paid/remaining totals.
  for v_doc in
    select id,payload from public.erp_commercial_workflow_documents d
     where d.company_id=p_company_id and not d.is_deleted
       and d.document_type='invoice'
       and (
         d.id::text=v_reference_id
         or exists(
           select 1 from jsonb_array_elements(coalesce(d.payload->'payments','[]'::jsonb)) p
            where coalesce(p->>'cashTransactionId',p->>'cash_transaction_id')=p_transaction_id
               or (v_journal_id is not null and coalesce(p->>'journalEntryId',p->>'journal_entry_id')=v_journal_id)
         )
       )
     for update
  loop
    select coalesce(jsonb_agg(value),'[]'::jsonb) into v_new_payments
      from jsonb_array_elements(coalesce(v_doc.payload->'payments','[]'::jsonb))
     where coalesce(value->>'cashTransactionId',value->>'cash_transaction_id')<>p_transaction_id
       and (v_journal_id is null or coalesce(value->>'journalEntryId',value->>'journal_entry_id')<>v_journal_id);
    select coalesce(sum(public.erp_try_numeric(coalesce(
      value->>'amountInInvoiceCurrency',value->>'amount_in_invoice_currency',
      value->>'invoiceAmount',value->>'amount'
    ),0)),0) into v_paid
      from jsonb_array_elements(v_new_payments) value;
    v_total:=public.erp_try_numeric(coalesce(
      v_doc.payload->>'totalAmount',v_doc.payload->>'total',v_doc.payload->>'invoiceAmount'
    ),0);
    update public.erp_commercial_workflow_documents
       set payload=jsonb_set(
             jsonb_set(
               jsonb_set(
                 payload||jsonb_build_object('payments',v_new_payments,'paymentUpdatedAt',v_now),
                 '{paidAmount}',to_jsonb(v_paid),true
               ),
               '{remainingAmount}',to_jsonb(greatest(v_total-v_paid,0)),true
             ),
             '{paymentStatus}',to_jsonb(case when v_paid<=0 then 'unpaid' when v_paid>=v_total and v_total>0 then 'paid' else 'partial' end),true
           ),
           updated_at=v_now
     where company_id=p_company_id and id=v_doc.id;
  end loop;

  perform public.erp_v65_soft_delete_journal(
    p_company_id,v_journal_id,'حذف سند قبض أو صرف'
  );
  update public.erp_cash_transactions
     set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid(),
         data=data||jsonb_build_object('deleteReason','حذف سند قبض أو صرف','deletedAt',v_now)
   where company_id=p_company_id and id=p_transaction_id and not is_deleted;
end;
$$;

-- Direct deletion/reversal of workflow documents must also repair every
-- dependent payment, journal and inventory link. Draft documents are removed
-- without posting; approved documents are reversed transactionally.
create or replace function public.erp_cancel_cloud_sales_workflow_invoice(
  p_company_id uuid,
  p_invoice_id uuid,
  p_reason text default null
) returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['sales.cancel','sales.update','sales.delete']
  );
  perform public.erp_reverse_cloud_workflow_invoice_payments(
    p_company_id,p_invoice_id,coalesce(p_reason,'حذف أو عكس فاتورة البيع')
  );
  perform public.erp_cancel_cloud_workflow_invoice(
    p_company_id,p_invoice_id,'sales',coalesce(p_reason,'حذف أو عكس فاتورة البيع')
  );
end;
$$;

create or replace function public.erp_cancel_cloud_purchase_workflow_invoice(
  p_company_id uuid,
  p_invoice_id uuid,
  p_reason text default null
) returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['purchases.cancel','purchases.update','purchases.delete']
  );
  perform public.erp_reverse_cloud_workflow_invoice_payments(
    p_company_id,p_invoice_id,coalesce(p_reason,'حذف أو عكس فاتورة الشراء')
  );
  perform public.erp_cancel_cloud_workflow_invoice(
    p_company_id,p_invoice_id,'purchases',coalesce(p_reason,'حذف أو عكس فاتورة الشراء')
  );
end;
$$;

create or replace function public.erp_cancel_cloud_sales_delivery(
  p_company_id uuid,
  p_delivery_id uuid
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_doc public.erp_commercial_workflow_documents%rowtype;
  v_invoice record;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['sales.cancel','sales.update','sales.delete']
  );
  select * into v_doc
    from public.erp_commercial_workflow_documents
   where company_id=p_company_id and id=p_delivery_id and module='sales'
     and document_type='delivery' and not is_deleted
   for update;
  if not found or v_doc.status='cancelled' then return; end if;

  -- A delivery cannot remain below an active invoice. Reverse invoices first.
  for v_invoice in
    select id from public.erp_commercial_workflow_documents
     where company_id=p_company_id and parent_id=v_doc.parent_id
       and module='sales' and document_type='invoice'
       and not is_deleted and status<>'cancelled'
     order by created_at desc,id desc
  loop
    perform public.erp_cancel_cloud_sales_workflow_invoice(
      p_company_id,v_invoice.id,'حذف إذن التجهيز وعكس الفاتورة المرتبطة'
    );
  end loop;

  perform public.erp_cancel_cloud_sales_delivery_pre_fifo_1890(
    p_company_id,p_delivery_id
  );
  update public.erp_inventory_cost_layers l
     set remaining_quantity=least(l.original_quantity,l.remaining_quantity+c.quantity),
         status='active',updated_at=now(),updated_by=auth.uid()
    from public.erp_inventory_fifo_consumptions c
   where c.company_id=p_company_id and c.delivery_id=p_delivery_id
     and c.status='active' and l.id=c.layer_id;
  update public.erp_inventory_fifo_consumptions
     set status='reversed',reversed_at=now()
   where company_id=p_company_id and delivery_id=p_delivery_id and status='active';
  update public.erp_commercial_workflow_documents
     set payload=payload||jsonb_build_object('fifoReversedAt',now()),updated_at=now()
   where company_id=p_company_id and id=p_delivery_id;
end;
$$;

create or replace function public.erp_cancel_cloud_purchase_receipt(
  p_company_id uuid,
  p_receipt_id uuid
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_doc public.erp_commercial_workflow_documents%rowtype;
  v_invoice record;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['purchases.cancel','purchases.update','purchases.delete']
  );
  select * into v_doc
    from public.erp_commercial_workflow_documents
   where company_id=p_company_id and id=p_receipt_id and module='purchases'
     and document_type='receipt' and not is_deleted
   for update;
  if not found or v_doc.status='cancelled' then return; end if;

  for v_invoice in
    select id from public.erp_commercial_workflow_documents
     where company_id=p_company_id and parent_id=v_doc.parent_id
       and module='purchases' and document_type='invoice'
       and not is_deleted and status<>'cancelled'
     order by created_at desc,id desc
  loop
    perform public.erp_cancel_cloud_purchase_workflow_invoice(
      p_company_id,v_invoice.id,'حذف إشعار الاستلام وعكس الفاتورة المرتبطة'
    );
  end loop;

  if exists(
    select 1
      from public.erp_inventory_fifo_consumptions c
      join public.erp_inventory_cost_layers l on l.id=c.layer_id
     where l.company_id=p_company_id and l.receipt_id=p_receipt_id
       and c.status='active'
  ) then
    raise exception 'لا يمكن حذف إشعار الاستلام لأن جزءاً من وجباته بيع فعلياً؛ احذف أو ألغِ مستندات البيع المرتبطة أولاً';
  end if;

  perform public.erp_cancel_cloud_purchase_receipt_pre_fifo_1890(
    p_company_id,p_receipt_id
  );
  update public.erp_inventory_cost_layers
     set remaining_quantity=0,status='reversed',updated_at=now(),updated_by=auth.uid()
   where company_id=p_company_id and receipt_id=p_receipt_id and status<>'reversed';
end;
$$;

create or replace function public.erp_prepare_commercial_order_change(
  p_company_id uuid,
  p_order_id uuid,
  p_module text,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_order_status text;
  v_logistics public.erp_commercial_workflow_documents%rowtype;
  v_invoice public.erp_commercial_workflow_documents%rowtype;
  v_doc record;
  v_result jsonb;
  v_documents jsonb;
begin
  perform public.erp_active_company_context(p_company_id);
  if p_module='sales' then
    select status into v_order_status from public.erp_sales_orders_cloud
     where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  elsif p_module='purchases' then
    select status into v_order_status from public.erp_purchase_orders_cloud
     where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  else
    raise exception 'نوع سير العمل غير صالح';
  end if;
  if not found then raise exception 'الأمر غير موجود'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',id,'documentType',document_type,'documentNumber',document_number,
    'status',status,'warehouseId',warehouse_id,'payload',payload
  ) order by created_at),'[]'::jsonb)
    into v_documents
    from public.erp_commercial_workflow_documents
   where company_id=p_company_id and parent_id=p_order_id and module=p_module and not is_deleted;

  select * into v_logistics from public.erp_commercial_workflow_documents
   where company_id=p_company_id and parent_id=p_order_id and module=p_module
     and document_type=case when p_module='sales' then 'delivery' else 'receipt' end
     and not is_deleted and status<>'cancelled'
   order by created_at desc,id desc limit 1;
  select * into v_invoice from public.erp_commercial_workflow_documents
   where company_id=p_company_id and parent_id=p_order_id and module=p_module
     and document_type='invoice' and not is_deleted and status<>'cancelled'
   order by created_at desc,id desc limit 1;

  v_result:=jsonb_build_object(
    'orderStatus',v_order_status,
    'documents',v_documents,
    'logistics',case when v_logistics.id is null then null else jsonb_build_object(
      'id',v_logistics.id,'status',v_logistics.status,'warehouseId',v_logistics.warehouse_id,
      'allocations',coalesce(v_logistics.payload->'allocations','[]'::jsonb),
      'warehouseIds',coalesce(v_logistics.payload->'warehouseIds','[]'::jsonb),
      'multiWarehouse',coalesce(v_logistics.payload->'multiWarehouse','false'::jsonb),
      'notes',v_logistics.payload->>'notes') end,
    'invoice',case when v_invoice.id is null then null else jsonb_build_object(
      'id',v_invoice.id,'status',v_invoice.status) end,
    'payments',coalesce(v_invoice.payload->'payments','[]'::jsonb)
  );

  for v_doc in
    select id from public.erp_commercial_workflow_documents
     where company_id=p_company_id and parent_id=p_order_id and module=p_module
       and document_type='invoice' and not is_deleted and status<>'cancelled'
     order by created_at desc,id desc
  loop
    perform public.erp_reverse_cloud_workflow_invoice_payments(
      p_company_id,v_doc.id,coalesce(p_reason,'عكس ارتباطات الأمر')
    );
    if p_module='sales' then
      perform public.erp_cancel_cloud_sales_workflow_invoice(p_company_id,v_doc.id,p_reason);
    else
      perform public.erp_cancel_cloud_purchase_workflow_invoice(p_company_id,v_doc.id,p_reason);
    end if;
  end loop;

  for v_doc in
    select id from public.erp_commercial_workflow_documents
     where company_id=p_company_id and parent_id=p_order_id and module=p_module
       and document_type=case when p_module='sales' then 'delivery' else 'receipt' end
       and not is_deleted and status<>'cancelled'
     order by created_at desc,id desc
  loop
    if p_module='sales' then
      perform public.erp_cancel_cloud_sales_delivery(p_company_id,v_doc.id);
    else
      begin
        perform public.erp_cancel_cloud_purchase_receipt(p_company_id,v_doc.id);
      exception when others then
        raise exception 'تعذر عكس الاستلام المخزني. احذف أو ألغِ مبيعات الكميات المرتبطة بهذه الوجبة أولاً. التفاصيل: %',sqlerrm;
      end;
    end if;
  end loop;

  if v_order_status='approved' then
    if p_module='sales' then
      perform public.erp_reopen_cloud_sales_order(p_company_id,p_order_id);
    else
      perform public.erp_reopen_cloud_purchase_order(p_company_id,p_order_id);
    end if;
  elsif v_order_status<>'draft' then
    if p_module='sales' then
      update public.erp_sales_orders_cloud set status='draft',updated_at=now()
       where company_id=p_company_id and id=p_order_id;
    else
      update public.erp_purchase_orders_cloud set status='draft',updated_at=now()
       where company_id=p_company_id and id=p_order_id;
    end if;
  end if;

  return v_result;
end;
$$;

create or replace function public.erp_delete_cloud_sales_order(
  p_company_id uuid,
  p_order_id uuid
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_snapshot jsonb;
  v_number text;
  v_batch uuid:=gen_random_uuid();
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['sales.delete']);
  select order_number into v_number from public.erp_sales_orders_cloud
   where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found then return; end if;

  perform set_config('qualityline.deletion_batch_id',v_batch::text,true);
  perform set_config('qualityline.deletion_root_table','erp_sales_orders_cloud',true);
  perform set_config('qualityline.deletion_root_id',p_order_id::text,true);
  perform set_config('qualityline.deletion_reason','حذف أمر البيع وعكس كل الارتباطات',true);

  v_snapshot:=public.erp_prepare_commercial_order_change(
    p_company_id,p_order_id,'sales','حذف أمر البيع وعكس كل الارتباطات'
  );
  perform public.erp_commercial_audit(
    p_company_id,'sales',p_order_id,null,v_number,'delete_order_cascade',
    v_snapshot->>'orderStatus','deleted','حذف مترابط كامل'
  );
  update public.erp_commercial_workflow_documents
     set is_deleted=true,deleted_at=now(),updated_at=now()
   where company_id=p_company_id and parent_id=p_order_id and module='sales' and not is_deleted;
  update public.erp_sales_order_items_cloud set is_deleted=true
   where company_id=p_company_id and order_id=p_order_id and not is_deleted;
  update public.erp_sales_orders_cloud
     set is_deleted=true,deleted_at=now(),updated_at=now()
   where company_id=p_company_id and id=p_order_id and not is_deleted;
  update public.erp_universal_recycle_bin
     set relation_context=relation_context||jsonb_build_object(
       'commercialModule','sales','commercialSnapshot',v_snapshot
     )
   where company_id=p_company_id and deletion_batch_id=v_batch;
end;
$$;

create or replace function public.erp_delete_cloud_purchase_order(
  p_company_id uuid,
  p_order_id uuid
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_snapshot jsonb;
  v_number text;
  v_batch uuid:=gen_random_uuid();
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['purchases.delete']);
  select order_number into v_number from public.erp_purchase_orders_cloud
   where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found then return; end if;

  perform set_config('qualityline.deletion_batch_id',v_batch::text,true);
  perform set_config('qualityline.deletion_root_table','erp_purchase_orders_cloud',true);
  perform set_config('qualityline.deletion_root_id',p_order_id::text,true);
  perform set_config('qualityline.deletion_reason','حذف أمر الشراء وعكس كل الارتباطات',true);

  v_snapshot:=public.erp_prepare_commercial_order_change(
    p_company_id,p_order_id,'purchases','حذف أمر الشراء وعكس كل الارتباطات'
  );
  perform public.erp_commercial_audit(
    p_company_id,'purchases',p_order_id,null,v_number,'delete_order_cascade',
    v_snapshot->>'orderStatus','deleted','حذف مترابط كامل'
  );
  update public.erp_commercial_workflow_documents
     set is_deleted=true,deleted_at=now(),updated_at=now()
   where company_id=p_company_id and parent_id=p_order_id and module='purchases' and not is_deleted;
  update public.erp_purchase_order_items_cloud set is_deleted=true
   where company_id=p_company_id and order_id=p_order_id and not is_deleted;
  update public.erp_purchase_orders_cloud
     set is_deleted=true,deleted_at=now(),updated_at=now()
   where company_id=p_company_id and id=p_order_id and not is_deleted;
  update public.erp_universal_recycle_bin
     set relation_context=relation_context||jsonb_build_object(
       'commercialModule','purchases','commercialSnapshot',v_snapshot
     )
   where company_id=p_company_id and deletion_batch_id=v_batch;
end;
$$;

create or replace function public.erp_delete_cloud_accounting_entry(
  p_company_id uuid,
  p_entry_id text
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_entry public.erp_journal_entries%rowtype;
  v_ref text;
  v_reference_id text;
  v_order_id text;
  v_reference_uuid uuid;
  v_order_uuid uuid;
  v_source_id text;
  v_doc record;
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['accounting.delete']);
  select * into v_entry from public.erp_journal_entries
   where company_id=p_company_id and id=p_entry_id and not is_deleted for update;
  if not found then return; end if;

  -- A cash row is the authoritative owner of receipt/payment journals.
  select id into v_source_id from public.erp_cash_transactions
   where company_id=p_company_id and not is_deleted
     and coalesce(data->>'journalEntryId',data->>'journal_entry_id',data->>'entryId',data->>'entry_id')=p_entry_id
   limit 1;
  if found then
    perform public.erp_delete_cloud_cash_transaction(p_company_id,v_source_id);
    return;
  end if;

  v_ref:=lower(btrim(coalesce(
    nullif(v_entry.data->>'referenceType',''),
    nullif(v_entry.data->>'reference_type',''),
    'manual'
  )));
  v_reference_id:=coalesce(
    nullif(v_entry.data->>'referenceId',''),nullif(v_entry.data->>'reference_id',''),
    nullif(v_entry.data->>'maintenanceOrderId',''),nullif(v_entry.data->>'maintenance_order_id',''),
    nullif(v_entry.data->>'cashTransactionId',''),nullif(v_entry.data->>'cash_transaction_id','')
  );
  v_order_id:=coalesce(
    nullif(v_entry.data->>'orderId',''),nullif(v_entry.data->>'order_id','')
  );

  if v_ref in ('manual','manual_journal','manual journal','قيد يدوي','') then
    perform public.erp_v65_soft_delete_journal(p_company_id,p_entry_id,'حذف قيد يدوي');
    return;
  end if;
  if v_ref='expense' and v_reference_id is not null then
    perform public.erp_delete_cloud_expense(p_company_id,v_reference_id);
    return;
  end if;
  if v_ref in ('manual_cash_transaction','cash_transaction','cash receipt','cash payment','receipt','payment','سند قبض','سند صرف')
     and v_reference_id is not null then
    perform public.erp_delete_cloud_cash_transaction(p_company_id,v_reference_id);
    return;
  end if;
  if v_ref in ('cash_transfer','cash transfer','تحويل نقدي','تحويل بين الصناديق')
     and v_reference_id is not null then
    perform public.erp_delete_cloud_cash_transfer(p_company_id,v_reference_id);
    return;
  end if;

  begin v_reference_uuid:=v_reference_id::uuid;
  exception when invalid_text_representation then v_reference_uuid:=null; end;
  begin v_order_uuid:=v_order_id::uuid;
  exception when invalid_text_representation then v_order_uuid:=null; end;

  if v_reference_uuid is not null and (
    v_ref like 'maintenance%' or exists(
      select 1 from public.erp_maintenance_orders
       where company_id=p_company_id and id=v_reference_uuid and not is_deleted
    )
  ) then
    perform public.erp_delete_cloud_maintenance_order(
      p_company_id,v_reference_uuid,'حذف من القيد المحاسبي المرتبط'
    );
    return;
  end if;

  if v_reference_uuid is not null then
    select module,parent_id into v_doc from public.erp_commercial_workflow_documents
     where company_id=p_company_id and id=v_reference_uuid and not is_deleted limit 1;
    if found and v_doc.module='sales' then
      perform public.erp_delete_cloud_sales_order(p_company_id,v_doc.parent_id); return;
    elsif found and v_doc.module='purchases' then
      perform public.erp_delete_cloud_purchase_order(p_company_id,v_doc.parent_id); return;
    end if;
  end if;

  if coalesce(v_order_uuid,v_reference_uuid) is not null and exists(
    select 1 from public.erp_sales_orders_cloud
     where company_id=p_company_id and id=coalesce(v_order_uuid,v_reference_uuid) and not is_deleted
  ) then
    perform public.erp_delete_cloud_sales_order(p_company_id,coalesce(v_order_uuid,v_reference_uuid));
    return;
  end if;
  if coalesce(v_order_uuid,v_reference_uuid) is not null and exists(
    select 1 from public.erp_purchase_orders_cloud
     where company_id=p_company_id and id=coalesce(v_order_uuid,v_reference_uuid) and not is_deleted
  ) then
    perform public.erp_delete_cloud_purchase_order(p_company_id,coalesce(v_order_uuid,v_reference_uuid));
    return;
  end if;

  if v_reference_id is not null and exists(
    select 1 from public.erp_sales where company_id=p_company_id and id=v_reference_id and not is_deleted
  ) then
    perform public.erp_delete_cloud_sale(p_company_id,v_reference_id); return;
  end if;
  if v_reference_id is not null and exists(
    select 1 from public.erp_purchases where company_id=p_company_id and id=v_reference_id and not is_deleted
  ) then
    perform public.erp_delete_cloud_purchase(p_company_id,v_reference_id); return;
  end if;

  -- Historical generated entries can outlive a removed source. Do not trap the
  -- administrator behind an undeletable orphan; delete the balanced journal.
  perform public.erp_v65_soft_delete_journal(
    p_company_id,p_entry_id,'حذف قيد يتيم بعد تعذر العثور على المستند المصدر'
  );
end;
$$;

revoke all on function public.erp_v65_soft_delete_journal(uuid,text,text) from public,anon;
grant execute on function public.erp_v65_soft_delete_journal(uuid,text,text) to authenticated,service_role;
grant execute on function public.erp_phase3_prepare_maintenance_lines(uuid,uuid,text,jsonb) to authenticated,service_role;
grant execute on function public.erp_delete_cloud_cash_transaction(uuid,text) to authenticated,service_role;
grant execute on function public.erp_delete_cloud_cash_transfer(uuid,text) to authenticated,service_role;
grant execute on function public.erp_delete_cloud_accounting_entry(uuid,text) to authenticated,service_role;
grant execute on function public.erp_prepare_commercial_order_change(uuid,uuid,text,text) to authenticated,service_role;
grant execute on function public.erp_delete_cloud_sales_order(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_delete_cloud_purchase_order(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_cancel_cloud_sales_workflow_invoice(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.erp_cancel_cloud_purchase_workflow_invoice(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.erp_cancel_cloud_sales_delivery(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_cancel_cloud_purchase_receipt(uuid,uuid) to authenticated,service_role;

commit;
