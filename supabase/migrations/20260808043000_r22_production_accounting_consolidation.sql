-- Quality Line ERP R22 production accounting consolidation.
-- Canonical goals:
-- 1) One diagnosable invoice approval surface for Sales and Purchases.
-- 2) Purchase invoice posts directly Supplier <-> Inventory, never via legacy
--    capitalization/clearing accounts when item/order currencies are equal.
-- 3) Cash transfers stamp immutable transaction/cashbox identity on journal
--    lines at creation time and repair historical transfer identities safely.
-- 4) One R22 PostgREST namespace for runtime health, phase-26 and cashbox APIs.
begin;

-- ---------------------------------------------------------------------------
-- Invoice preflight and direct purchase posting.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r22_invoice_preflight(
  p_company_id uuid,p_invoice_id uuid,p_module text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  d public.erp_commercial_workflow_documents%rowtype;
  v_policy jsonb;
  v_logistics_id uuid;
  v_logistics jsonb;
begin
  if p_module not in ('sales','purchases') then
    raise exception 'invalid_workflow_module:%',p_module using errcode='22023';
  end if;
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;

  select * into d from public.erp_commercial_workflow_documents
  where company_id=p_company_id and id=p_invoice_id and module=p_module
    and document_type='invoice' and not is_deleted for update;
  if not found then raise exception 'workflow_invoice_not_found' using errcode='P7624'; end if;
  if d.status not in ('draft','pending','submitted','approved') then
    raise exception 'workflow_invoice_status_invalid:%',d.status using errcode='P7628';
  end if;
  if upper(coalesce(d.payload->>'currency','')) not in ('USD','IQD') then
    raise exception 'workflow_invoice_currency_invalid:%',coalesce(d.payload->>'currency','') using errcode='P7626';
  end if;
  if public.erp_try_numeric(d.payload->>'totalAmount',0)<=0 then
    raise exception 'workflow_invoice_total_invalid' using errcode='P7627';
  end if;
  if d.parent_id is null then raise exception 'workflow_invoice_order_missing' using errcode='P7625'; end if;

  v_logistics_id:=nullif(d.payload->>'logisticsDocumentId','')::uuid;
  if v_logistics_id is null then raise exception 'workflow_invoice_logistics_missing'; end if;
  v_logistics:=public.erp_v736_assert_invoice_logistics(
    p_company_id,d.parent_id,p_module,v_logistics_id,d.payload->'allocations');

  -- V23.0.2 owns the final business policy: Sales may mix stock definition
  -- currencies while Purchase must match definition/order currency.
  v_policy:=public.erp_v767_invoice_policy_preflight(p_company_id,p_invoice_id,p_module);

  return coalesce(v_policy,'{}'::jsonb)||jsonb_build_object(
    'ok',true,'stage','preflight','version','r22',
    'invoiceStatus',d.status,'logisticsDocumentId',v_logistics_id,
    'logisticsValidated',v_logistics is not null
  );
end;
$$;

create or replace function public.erp_r22_post_purchase_invoice_direct(
  p_company_id uuid,p_invoice_id uuid
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  d public.erp_commercial_workflow_documents%rowtype;
  v_currency text;
  v_total numeric;
  v_effective timestamptz;
  v_logistics_id uuid;
  v_logistics jsonb;
  v_supplier_id text;
  v_supplier_account text;
  v_subtotal numeric;
  v_factor numeric:=1;
  r record;
  a record;
  ac jsonb;
  s public.erp_warehouse_stock%rowtype;
  v_amount numeric;
  v_total_debit numeric:=0;
  v_current_qty numeric;
  v_previous_qty numeric;
  v_previous_avg numeric;
  v_new_avg numeric;
  v_adjusted_unit_cost numeric;
  v_old_data jsonb;
  v_snapshots jsonb:='[]'::jsonb;
  v_lines jsonb:='[]'::jsonb;
  v_entry text;
  v_layer_number text;
  x jsonb;
begin
  select * into d from public.erp_commercial_workflow_documents
  where company_id=p_company_id and id=p_invoice_id and module='purchases'
    and document_type='invoice' and not is_deleted for update;
  if not found then raise exception 'workflow_invoice_not_found' using errcode='P7624'; end if;

  if d.status='approved' then
    if nullif(d.payload->>'journalEntryId','') is not null then
      perform public.erp_v762_assert_posted_journal_balanced(
        p_company_id,d.payload->>'journalEntryId','r22_purchase_invoice');
    end if;
    return jsonb_build_object('ok',true,'idempotent',true,'invoiceId',p_invoice_id,'status','approved');
  end if;
  if d.status not in ('draft','pending','submitted') then
    raise exception 'workflow_invoice_status_invalid:%',d.status using errcode='P7628';
  end if;

  v_currency:=upper(coalesce(d.payload->>'currency',''));
  v_total:=public.erp_try_numeric(d.payload->>'totalAmount',0);
  v_effective:=coalesce(d.effective_at,d.created_at,now());
  v_logistics_id:=nullif(d.payload->>'logisticsDocumentId','')::uuid;
  if v_currency not in ('USD','IQD') or v_total<=0 or v_logistics_id is null then
    raise exception 'workflow_invoice_invalid_amount_currency_or_logistics';
  end if;

  v_logistics:=public.erp_v736_assert_invoice_logistics(
    p_company_id,d.parent_id,'purchases',v_logistics_id,d.payload->'allocations');

  select supplier_id,subtotal into v_supplier_id,v_subtotal
  from public.erp_purchase_orders_cloud
  where company_id=p_company_id and id=d.parent_id and status='approved'
    and upper(currency)=v_currency and not is_deleted;
  if not found or v_supplier_id is null then raise exception 'purchase_approved_order_required'; end if;

  perform public.erp_v767_assert_partner_ledgers(p_company_id,v_supplier_id,'supplier');
  v_supplier_account:=public.erp_workflow_partner_account(
    p_company_id,'supplier',v_supplier_id,v_currency);
  perform public.erp_phase2_account_guard(p_company_id,v_supplier_account,'liability',v_currency);
  v_factor:=case when coalesce(v_subtotal,0)>0 then v_total/v_subtotal else 1 end;

  -- Quantity/state belongs to the approved receipt. Remove only any historical
  -- receipt-owned accounting so the invoice becomes the sole accounting owner.
  perform public.erp_v736_detach_legacy_purchase_receipt_accounting(
    p_company_id,v_logistics_id);

  -- A draft invoice must not carry stale partial journals. Only IDs explicitly
  -- owned by this invoice payload are retired; no unrelated historical entry is touched.
  if nullif(d.payload->>'journalEntryId','') is not null then
    perform public.erp_v736_void_journal_id(p_company_id,d.payload->>'journalEntryId');
  end if;
  for x in select value from jsonb_array_elements(coalesce(d.payload->'costJournalEntries','[]'::jsonb)) loop
    if nullif(x->>'journalEntryId','') is not null then
      perform public.erp_v736_void_journal_id(p_company_id,x->>'journalEntryId');
    end if;
  end loop;

  for r in
    select * from public.erp_purchase_order_items_cloud
    where company_id=p_company_id and order_id=d.parent_id and not is_deleted
    order by id
  loop
    ac:=public.erp_v736_item_accounting(p_company_id,r.item_type,r.item_id,null);
    if lower(coalesce(ac->>'itemKind','stock'))='service' then
      raise exception 'purchase_service_not_inventory_item:%',r.item_id;
    end if;
    if upper(coalesce(ac->>'costCurrency',''))<>v_currency then
      raise exception 'purchase_item_currency_mismatch:%:%:%',
        r.item_id,upper(coalesce(ac->>'costCurrency','')),v_currency;
    end if;
    perform public.erp_phase2_account_guard(
      p_company_id,ac->>'assetAccountId','asset',v_currency);
    perform public.erp_phase2_account_guard(
      p_company_id,ac->>'costExpenseAccountId','expense',v_currency);

    v_amount:=r.line_total*v_factor;
    v_total_debit:=v_total_debit+v_amount;
    v_adjusted_unit_cost:=case when r.quantity>0 then v_amount/r.quantity else r.unit_cost end;
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
      'accountId',ac->>'assetAccountId','debit',v_amount,'credit',0,
      'description','مخزون شراء - '||r.description,
      'itemType',r.item_type,'itemId',r.item_id,
      'quantity',r.quantity,'unitCost',v_adjusted_unit_cost,
      'r22DirectPurchase',true));
    v_old_data:=ac->'data';

    for a in
      select * from jsonb_to_recordset(d.payload->'allocations') as x(
        "itemType" text,"itemId" text,"description" text,"warehouseId" text,quantity numeric)
      where x."itemType"=r.item_type and x."itemId"=r.item_id
    loop
      if r.item_type='product' then
        s:=public.erp_inventory_ensure_stock(p_company_id,a."warehouseId",r.item_id);
        v_current_qty:=public.erp_try_numeric(s.data->>'quantity',0);
        if v_current_qty<a.quantity then
          raise exception 'purchase_invoice_quantity_exceeds_current_stock:%',r.description;
        end if;
        v_previous_qty:=v_current_qty-a.quantity;
        v_previous_avg:=public.erp_try_numeric(s.data->>'averageUnitCost',0);
        v_new_avg:=case when v_current_qty>0 then
          ((v_previous_qty*v_previous_avg)+(a.quantity*v_adjusted_unit_cost))/v_current_qty
          else v_adjusted_unit_cost end;
        v_snapshots:=v_snapshots||jsonb_build_array(jsonb_build_object(
          'itemType','product','itemId',r.item_id,'warehouseId',a."warehouseId",
          'previousAverageUnitCost',v_previous_avg,
          'previousPurchasePrice',public.erp_try_numeric(v_old_data->>'purchasePrice',0),
          'previousUnitCost',public.erp_try_numeric(v_old_data->>'unitCost',0),
          'previousCostCurrency',coalesce(v_old_data->>'costCurrency',v_old_data->>'cost_currency',v_old_data->>'currency')));
        update public.erp_warehouse_stock
        set data=data||jsonb_build_object(
              'averageUnitCost',round(v_new_avg,6),'valuationPendingInvoice',false,
              'valuationInvoiceId',p_invoice_id::text,'valuationCurrency',v_currency,
              'updatedAt',now()),
            updated_at=now(),updated_by=auth.uid()
        where id=s.id;
        v_layer_number:=(d.payload->>'logisticsDocumentNumber')||'-'||substr(md5(r.item_id||a."warehouseId"),1,6);
        insert into public.erp_inventory_cost_layers(
          company_id,item_type,item_id,warehouse_id,receipt_id,purchase_order_id,source_line_id,
          layer_number,effective_at,original_quantity,remaining_quantity,unit_cost,currency,
          asset_account_id,cost_expense_account_id,source_type
        ) values(
          p_company_id,'product',r.item_id,a."warehouseId",v_logistics_id,d.parent_id,r.id,
          v_layer_number,v_effective,a.quantity,a.quantity,v_adjusted_unit_cost,v_currency,
          ac->>'assetAccountId',ac->>'costExpenseAccountId','purchase_invoice'
        ) on conflict(company_id,receipt_id,item_type,item_id,warehouse_id) do update set
          source_line_id=excluded.source_line_id,layer_number=excluded.layer_number,
          effective_at=excluded.effective_at,original_quantity=excluded.original_quantity,
          remaining_quantity=excluded.remaining_quantity,unit_cost=excluded.unit_cost,
          currency=excluded.currency,asset_account_id=excluded.asset_account_id,
          cost_expense_account_id=excluded.cost_expense_account_id,status='active',
          source_type='purchase_invoice',updated_at=now(),updated_by=auth.uid();
      else
        v_snapshots:=v_snapshots||jsonb_build_array(jsonb_build_object(
          'itemType','car','itemId',r.item_id,'warehouseId',a."warehouseId",
          'previousPurchasePrice',public.erp_try_numeric(v_old_data->>'purchasePrice',0),
          'previousCostCurrency',coalesce(v_old_data->>'costCurrency',v_old_data->>'cost_currency',v_old_data->>'currency')));
        v_layer_number:=(d.payload->>'logisticsDocumentNumber')||'-'||substr(md5(r.item_id),1,6);
        insert into public.erp_inventory_cost_layers(
          company_id,item_type,item_id,warehouse_id,receipt_id,purchase_order_id,source_line_id,
          layer_number,effective_at,original_quantity,remaining_quantity,unit_cost,currency,
          asset_account_id,cost_expense_account_id,source_type
        ) values(
          p_company_id,'car',r.item_id,a."warehouseId",v_logistics_id,d.parent_id,r.id,
          v_layer_number,v_effective,1,1,v_adjusted_unit_cost,v_currency,
          ac->>'assetAccountId',ac->>'costExpenseAccountId','purchase_invoice'
        ) on conflict(company_id,receipt_id,item_type,item_id,warehouse_id) do update set
          source_line_id=excluded.source_line_id,layer_number=excluded.layer_number,
          effective_at=excluded.effective_at,original_quantity=1,remaining_quantity=1,
          unit_cost=excluded.unit_cost,currency=excluded.currency,
          asset_account_id=excluded.asset_account_id,cost_expense_account_id=excluded.cost_expense_account_id,
          status='active',source_type='purchase_invoice',updated_at=now(),updated_by=auth.uid();
      end if;
    end loop;

    if r.item_type='car' then
      update public.erp_cars
      set data=data||jsonb_build_object(
            'purchasePrice',v_adjusted_unit_cost,'purchase_price',v_adjusted_unit_cost,
            'costCurrency',v_currency,'cost_currency',v_currency,
            'valuationPendingInvoice',false,'valuationUpdatedByInvoiceId',p_invoice_id::text,
            'purchaseInvoiceCurrency',v_currency,'updatedAt',now()),
          updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and id=r.item_id and not is_deleted;
    else
      update public.erp_inventory
      set data=data||jsonb_build_object(
            'purchasePrice',v_adjusted_unit_cost,'purchase_price',v_adjusted_unit_cost,
            'unitCost',v_adjusted_unit_cost,'unit_cost',v_adjusted_unit_cost,
            'costCurrency',v_currency,'cost_currency',v_currency,
            'valuationPendingInvoice',false,'valuationUpdatedByInvoiceId',p_invoice_id::text,
            'purchaseInvoiceCurrency',v_currency,'updatedAt',now()),
          updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and id=r.item_id and not is_deleted;
      perform public.erp_inventory_refresh_product(p_company_id,r.item_id);
    end if;
  end loop;

  if jsonb_array_length(v_lines)=0 then raise exception 'purchase_invoice_items_missing'; end if;
  if abs(v_total_debit-v_total)>0.01 then
    raise exception 'purchase_invoice_line_total_mismatch:%:%',v_total_debit,v_total;
  end if;

  v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
    'accountId',v_supplier_account,'debit',0,'credit',v_total,
    'description','ذمة المورد - فاتورة شراء','r22DirectPurchase',true));
  v_entry:=public.erp_phase2_insert_journal_at(
    p_company_id,'purchase_invoice',p_invoice_id::text,
    public.erp_next_document_number(p_company_id,'purchase_invoice_journal','PIJ',v_effective),
    'فاتورة شراء مباشرة: المورد مقابل المخزون '||d.document_number,
    v_currency,v_lines,v_effective);
  perform public.erp_v762_assert_posted_journal_balanced(
    p_company_id,v_entry,'r22_purchase_invoice');

  update public.erp_commercial_workflow_documents
  set payload=payload||jsonb_build_object(
        'valuationPendingInvoice',false,'valuedByInvoiceId',p_invoice_id::text,
        'valuationAppliedAt',now(),'invoiceCurrency',v_currency,
        'costJournalEntries','[]'::jsonb,'r22DirectPurchasePosting',true,
        'accountingPolicy','direct_supplier_inventory'),updated_at=now()
  where company_id=p_company_id and id=v_logistics_id;

  update public.erp_commercial_workflow_documents
  set status='approved',
      payload=(payload-'costJournalEntries')||jsonb_build_object(
        'journalEntryId',v_entry,'costJournalEntries','[]'::jsonb,
        'costBreakdown','[]'::jsonb,'valuationSnapshots',v_snapshots,
        'approvedAt',now(),'approvedBy',auth.uid(),'valuationApplied',true,
        'accountingOwner','invoice','accountingPolicy','direct_supplier_inventory',
        'r22DirectPurchasePosting',true,'r22ApprovedAt',now()),
      updated_at=now(),updated_by=auth.uid()
  where company_id=p_company_id and id=p_invoice_id;

  perform public.erp_commercial_audit(
    p_company_id,'purchases',d.parent_id,d.id,d.document_number,
    'approve_invoice',d.status,'approved','R22 direct Supplier-to-Inventory invoice posting');
  perform public.erp_v73_recompute_commercial_order_status(
    p_company_id,'purchases',d.parent_id);

  return jsonb_build_object(
    'ok',true,'invoiceId',p_invoice_id,'journalEntryId',v_entry,
    'postingMode','direct_supplier_inventory','currency',v_currency,
    'totalAmount',v_total,'valuationSnapshots',jsonb_array_length(v_snapshots));
end;
$$;

create or replace function public.erp_r22_approve_workflow_invoice(
  p_company_id uuid,p_invoice_id uuid,p_module text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  d public.erp_commercial_workflow_documents%rowtype;
  v_preflight jsonb;
  v_result jsonb;
  v_required_permission text;
  e jsonb;
begin
  if p_module not in ('sales','purchases') then
    return jsonb_build_object('ok',false,'stage','input','code','R22_MODULE','error','invalid_workflow_module','module',p_module);
  end if;
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    return jsonb_build_object('ok',false,'stage','authorization','code','42501','error','company_membership_required');
  end if;
  v_required_permission:=case when p_module='sales' then 'sales.approve' else 'purchases.approve' end;
  if not public.erp_cloud_user_has_permission(p_company_id,v_required_permission)
     and not public.is_company_admin(p_company_id) then
    return jsonb_build_object('ok',false,'stage','authorization','code','42501','error','permission_denied:'||v_required_permission);
  end if;

  select * into d from public.erp_commercial_workflow_documents
  where company_id=p_company_id and id=p_invoice_id and module=p_module
    and document_type='invoice' and not is_deleted for update;
  if not found then
    return jsonb_build_object('ok',false,'stage','load','code','P7624','error','workflow_invoice_not_found','invoiceId',p_invoice_id);
  end if;

  if d.status='approved' then
    begin
      if nullif(d.payload->>'journalEntryId','') is not null then
        perform public.erp_v762_assert_posted_journal_balanced(
          p_company_id,d.payload->>'journalEntryId','r22_'||p_module||'_invoice');
      end if;
      for e in select value from jsonb_array_elements(coalesce(d.payload->'costJournalEntries','[]'::jsonb)) loop
        if nullif(e->>'journalEntryId','') is not null then
          perform public.erp_v762_assert_posted_journal_balanced(
            p_company_id,e->>'journalEntryId','r22_'||p_module||'_cost');
        end if;
      end loop;
    exception when others then
      return jsonb_build_object('ok',false,'stage','integrity','code',sqlstate,'error',sqlerrm,
        'invoiceId',p_invoice_id,'status','approved');
    end;
    return jsonb_build_object('ok',true,'idempotent',true,'version','r22','invoiceId',p_invoice_id,'status','approved');
  end if;

  begin
    v_preflight:=public.erp_r22_invoice_preflight(p_company_id,p_invoice_id,p_module);
  exception when others then
    return jsonb_build_object(
      'ok',false,'stage','preflight','code',sqlstate,'error',sqlerrm,
      'details',jsonb_build_object('module',p_module,'invoiceId',p_invoice_id,'orderId',d.parent_id)::text,
      'hint','Verify approved logistics, partner currency ledger and item definition accounts; the error identifies the exact missing contract.'
    );
  end;

  begin
    if p_module='sales' then
      -- Sales uses the proven invoice-owned revenue/FIFO engine directly.
      -- No R14->V762->V760->V750 fallback chain is traversed.
      perform public.erp_approve_cloud_workflow_invoice(p_company_id,p_invoice_id,'sales');
      v_result:=jsonb_build_object('postingMode','sales_invoice_owned_fifo');
    else
      v_result:=public.erp_r22_post_purchase_invoice_direct(p_company_id,p_invoice_id);
    end if;
  exception when others then
    return jsonb_build_object(
      'ok',false,'stage','posting','code',sqlstate,'error',sqlerrm,
      'details',jsonb_build_object('module',p_module,'invoiceId',p_invoice_id,'orderId',d.parent_id,'preflight',v_preflight)::text,
      'hint','Posting is atomic. No partial invoice journal is accepted; inspect the exact SQL error and source document.'
    );
  end;

  select * into d from public.erp_commercial_workflow_documents
  where company_id=p_company_id and id=p_invoice_id and module=p_module and not is_deleted;
  if d.status<>'approved' then
    return jsonb_build_object('ok',false,'stage','verify','code','R22_NOT_APPROVED','error','workflow_invoice_not_approved_after_post');
  end if;

  begin
    if nullif(d.payload->>'journalEntryId','') is null then
      raise exception 'posting_journal_missing';
    end if;
    perform public.erp_v762_assert_posted_journal_balanced(
      p_company_id,d.payload->>'journalEntryId','r22_'||p_module||'_invoice');
    for e in select value from jsonb_array_elements(coalesce(d.payload->'costJournalEntries','[]'::jsonb)) loop
      if nullif(e->>'journalEntryId','') is not null then
        perform public.erp_v762_assert_posted_journal_balanced(
          p_company_id,e->>'journalEntryId','r22_'||p_module||'_cost');
      end if;
    end loop;
  exception when others then
    return jsonb_build_object('ok',false,'stage','integrity','code',sqlstate,'error',sqlerrm,'invoiceId',p_invoice_id);
  end;

  perform public.erp_v73_recompute_commercial_order_status(p_company_id,p_module,d.parent_id);
  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'ok',true,'version','r22','invoiceId',p_invoice_id,'status','approved',
    'journalEntryId',d.payload->>'journalEntryId','preflight',v_preflight);
end;
$$;

create or replace function public.erp_r22_approve_sales_invoice(
  p_company_id uuid,p_invoice_id uuid
) returns jsonb language sql security definer set search_path=public as $$
  select public.erp_r22_approve_workflow_invoice($1,$2,'sales')
$$;
create or replace function public.erp_r22_approve_purchase_invoice(
  p_company_id uuid,p_invoice_id uuid
) returns jsonb language sql security definer set search_path=public as $$
  select public.erp_r22_approve_workflow_invoice($1,$2,'purchases')
$$;

-- Compatibility: already-cached R14 clients and older component actions converge
-- to the same R22 approval contract immediately after this migration is pushed.
create or replace function public.erp_r14_approve_sales_invoice(
  p_company_id uuid,p_invoice_id uuid
) returns jsonb language sql security definer set search_path=public as $$
  select public.erp_r22_approve_sales_invoice($1,$2)
$$;
create or replace function public.erp_r14_approve_purchase_invoice(
  p_company_id uuid,p_invoice_id uuid
) returns jsonb language sql security definer set search_path=public as $$
  select public.erp_r22_approve_purchase_invoice($1,$2)
$$;
create or replace function public.erp_v762_approve_workflow_invoice(
  p_company_id uuid,p_invoice_id uuid,p_module text
) returns jsonb language sql security definer set search_path=public as $$
  select public.erp_r22_approve_workflow_invoice($1,$2,$3)
$$;

create or replace function public.erp_approve_cloud_sales_workflow_invoice(
  p_company_id uuid,p_invoice_id uuid
) returns void language plpgsql security definer set search_path=public as $$
declare v jsonb;
begin
  v:=public.erp_r22_approve_sales_invoice(p_company_id,p_invoice_id);
  if coalesce((v->>'ok')::boolean,false) is not true then
    raise exception 'r22_sales_invoice_approval_failed:%',v::text;
  end if;
end;
$$;
create or replace function public.erp_approve_cloud_purchase_workflow_invoice(
  p_company_id uuid,p_invoice_id uuid
) returns void language plpgsql security definer set search_path=public as $$
declare v jsonb;
begin
  v:=public.erp_r22_approve_purchase_invoice(p_company_id,p_invoice_id);
  if coalesce((v->>'ok')::boolean,false) is not true then
    raise exception 'r22_purchase_invoice_approval_failed:%',v::text;
  end if;
end;
$$;

create or replace function public.erp_manage_commercial_order_component_v3(
  p_company_id uuid,p_module text,p_order_id uuid,p_component_type text,
  p_component_id uuid,p_action text,p_reason text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_module text:=lower(btrim(coalesce(p_module,'')));
  v_type text:=lower(btrim(coalesce(p_component_type,'')));
  v_action text:=lower(btrim(coalesce(p_action,'')));
  v_result jsonb;
begin
  if p_company_id is null then return jsonb_build_object('ok',false,'code','company_required','error','A company context is required.'); end if;
  if p_order_id is null then return jsonb_build_object('ok',false,'code','order_required','error','A commercial order is required.'); end if;
  if p_component_id is null then return jsonb_build_object('ok',false,'code','component_required','error','A workflow component is required.'); end if;
  if v_module not in ('sales','purchases') then return jsonb_build_object('ok',false,'code','invalid_workflow_module','error','Unsupported workflow module.'); end if;
  if v_type not in ('order','delivery','receipt','invoice','payment') then return jsonb_build_object('ok',false,'code','invalid_component_type','error','Unsupported workflow component.'); end if;
  if v_action not in ('approve','delete','cancel','reverse','reopen') then return jsonb_build_object('ok',false,'code','invalid_component_action','error','Unsupported workflow action.'); end if;
  if v_type='invoice' and v_action='approve' then
    v_result:=public.erp_r22_approve_workflow_invoice(p_company_id,p_component_id,v_module);
  else
    v_result:=public.erp_manage_commercial_order_component_v2(
      p_company_id,v_module,p_order_id,v_type,p_component_id,v_action,p_reason);
  end if;
  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'module',v_module,'orderId',p_order_id,'componentType',v_type,
    'componentId',p_component_id,'action',v_action);
exception when others then
  return jsonb_build_object('ok',false,'code',sqlstate,'error',sqlerrm,
    'details',jsonb_build_object('module',v_module,'orderId',p_order_id,
      'componentType',v_type,'componentId',p_component_id,'action',v_action)::text);
end;
$$;

-- ---------------------------------------------------------------------------
-- Cash transfer identity and historical reconciliation.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r22_bind_cash_transaction_exact(
  p_company_id uuid,p_transaction_id text,p_cash_account_id text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_tx public.erp_cash_transactions%rowtype;
  v_cash public.erp_cash_accounts%rowtype;
  v_entry public.erp_journal_entries%rowtype;
  v_ledger record;
  v_amount numeric;
  v_type text;
  v_line_id text;
  v_count integer:=0;
begin
  select * into v_tx from public.erp_cash_transactions
  where company_id=p_company_id and id=p_transaction_id and not is_deleted for update;
  if not found then
    perform public.erp_r16_record_reconciliation_issue(
      p_company_id,'r22_cash_transaction_missing','cash_transaction',p_transaction_id,
      jsonb_build_object('cashAccountId',p_cash_account_id));
    return jsonb_build_object('ok',false,'code','cash_transaction_missing','transactionId',p_transaction_id);
  end if;
  if coalesce(v_tx.data->>'cashAccountId',v_tx.data->>'cash_account_id') is distinct from p_cash_account_id then
    perform public.erp_r16_record_reconciliation_issue(
      p_company_id,'r22_cash_transaction_cashbox_mismatch','cash_transaction',p_transaction_id,
      jsonb_build_object('expectedCashAccountId',p_cash_account_id,'actualCashAccountId',coalesce(v_tx.data->>'cashAccountId',v_tx.data->>'cash_account_id')));
    return jsonb_build_object('ok',false,'code','cash_transaction_cashbox_mismatch','transactionId',p_transaction_id);
  end if;
  select * into v_cash from public.erp_cash_accounts
  where company_id=p_company_id and id=p_cash_account_id and not is_deleted;
  if not found then return jsonb_build_object('ok',false,'code','cashbox_missing','cashAccountId',p_cash_account_id); end if;
  select account_id,code,name,currency into v_ledger from public.erp_accounts
  where organization_id=p_company_id
    and account_id=coalesce(v_cash.data->>'accountId',v_cash.data->>'account_id') and is_active;
  if v_ledger.account_id is null then return jsonb_build_object('ok',false,'code','cashbox_ledger_missing','cashAccountId',p_cash_account_id); end if;
  select * into v_entry from public.erp_journal_entries
  where company_id=p_company_id and id=coalesce(v_tx.data->>'journalEntryId',v_tx.data->>'journal_entry_id') and not is_deleted;
  if not found then
    perform public.erp_r16_record_reconciliation_issue(
      p_company_id,'cash_journal_missing','cash_transaction',p_transaction_id,
      jsonb_build_object('cashAccountId',p_cash_account_id,'journalEntryId',coalesce(v_tx.data->>'journalEntryId',v_tx.data->>'journal_entry_id')));
    return jsonb_build_object('ok',false,'code','cash_journal_missing','transactionId',p_transaction_id);
  end if;
  v_amount:=abs(public.erp_try_numeric(v_tx.data->>'amount',0));
  v_type:=lower(coalesce(v_tx.data->>'type',''));

  -- Strong identity first. Historical transfers without identity are allowed to
  -- match only inside this exact transaction's journal, currency and direction.
  select count(*)::integer,min(jl.id) into v_count,v_line_id
  from public.erp_journal_lines jl
  where jl.company_id=p_company_id and not jl.is_deleted
    and jl.data->>'entryId'=v_entry.id
    and jl.data->>'cashTransactionId'=p_transaction_id
    and public.erp_r16_cash_line_matches(jl.data,v_type,v_amount);
  if v_count=0 then
    select count(*)::integer,min(jl.id) into v_count,v_line_id
    from public.erp_journal_lines jl
    where jl.company_id=p_company_id and not jl.is_deleted
      and jl.data->>'entryId'=v_entry.id
      and upper(coalesce(nullif(jl.data->>'currency',''),v_entry.data->>'currency',''))=
          upper(coalesce(v_tx.data->>'currency',''))
      and public.erp_r16_cash_line_matches(jl.data,v_type,v_amount);
  end if;
  if v_count<>1 then
    perform public.erp_r16_record_reconciliation_issue(
      p_company_id,case when v_count=0 then 'r22_cash_identity_unresolved' else 'r22_cash_identity_ambiguous' end,
      'cash_transaction',p_transaction_id,
      jsonb_build_object('cashAccountId',p_cash_account_id,'journalEntryId',v_entry.id,'candidateCount',v_count,'amount',v_amount,'type',v_type));
    return jsonb_build_object('ok',false,'code',case when v_count=0 then 'cash_identity_unresolved' else 'cash_identity_ambiguous' end,
      'transactionId',p_transaction_id,'candidateCount',v_count);
  end if;

  update public.erp_journal_lines
  set data=data||jsonb_build_object(
        'accountId',v_ledger.account_id,'accountCode',v_ledger.code,'accountName',v_ledger.name,
        'currency',upper(v_ledger.currency),'cashTransactionId',p_transaction_id,
        'cashAccountId',p_cash_account_id,'r22CanonicalCashBinding',true),
      updated_at=now(),updated_by=auth.uid()
  where company_id=p_company_id and id=v_line_id;
  update public.erp_cash_transactions
  set data=data||jsonb_build_object(
        'cashLedgerAccountId',v_ledger.account_id,'r22CanonicalCashBinding',true),
      updated_at=now(),updated_by=auth.uid()
  where company_id=p_company_id and id=p_transaction_id;
  perform public.erp_r16_resolve_reconciliation_issues(p_company_id,'cash_transaction',p_transaction_id);
  return jsonb_build_object('ok',true,'transactionId',p_transaction_id,'cashAccountId',p_cash_account_id,
    'journalEntryId',v_entry.id,'journalLineId',v_line_id,'ledgerAccountId',v_ledger.account_id);
end;
$$;

create or replace function public.erp_r22_repair_cash_transfer(
  p_company_id uuid,p_transfer_id text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_transfer public.erp_cash_transfers%rowtype;
  v_from text;
  v_to text;
  v_out_id text;
  v_in_id text;
  v_out_count integer;
  v_in_count integer;
  v_out jsonb;
  v_in jsonb;
begin
  select * into v_transfer from public.erp_cash_transfers
  where company_id=p_company_id and id=p_transfer_id and not is_deleted;
  if not found then return jsonb_build_object('ok',false,'code','cash_transfer_missing','transferId',p_transfer_id); end if;
  v_from:=coalesce(v_transfer.data->>'fromAccountId',v_transfer.data->>'from_account_id');
  v_to:=coalesce(v_transfer.data->>'toAccountId',v_transfer.data->>'to_account_id');
  select count(*)::integer,min(id) into v_out_count,v_out_id
  from public.erp_cash_transactions
  where company_id=p_company_id and not is_deleted
    and lower(coalesce(data->>'referenceType',data->>'reference_type',''))='cash_transfer'
    and coalesce(data->>'referenceId',data->>'reference_id')=p_transfer_id
    and coalesce(data->>'cashAccountId',data->>'cash_account_id')=v_from
    and lower(coalesce(data->>'type','')) in ('payment','expense','out','cash_out','supplier_payment','transfer_out');
  select count(*)::integer,min(id) into v_in_count,v_in_id
  from public.erp_cash_transactions
  where company_id=p_company_id and not is_deleted
    and lower(coalesce(data->>'referenceType',data->>'reference_type',''))='cash_transfer'
    and coalesce(data->>'referenceId',data->>'reference_id')=p_transfer_id
    and coalesce(data->>'cashAccountId',data->>'cash_account_id')=v_to
    and lower(coalesce(data->>'type','')) in ('receipt','income','in','cash_in','customer_receipt','transfer_in');
  if v_out_count<>1 or v_in_count<>1 then
    perform public.erp_r16_record_reconciliation_issue(
      p_company_id,'r22_cash_transfer_pair_invalid','cash_transfer',p_transfer_id,
      jsonb_build_object('fromCashAccountId',v_from,'toCashAccountId',v_to,'outTransactionCount',v_out_count,'inTransactionCount',v_in_count));
    return jsonb_build_object('ok',false,'code','cash_transfer_pair_invalid','transferId',p_transfer_id,
      'outTransactionCount',v_out_count,'inTransactionCount',v_in_count);
  end if;
  v_out:=public.erp_r22_bind_cash_transaction_exact(p_company_id,v_out_id,v_from);
  v_in:=public.erp_r22_bind_cash_transaction_exact(p_company_id,v_in_id,v_to);
  if coalesce((v_out->>'ok')::boolean,false) and coalesce((v_in->>'ok')::boolean,false) then
    perform public.erp_r16_resolve_reconciliation_issues(p_company_id,'cash_transfer',p_transfer_id);
  end if;
  return jsonb_build_object('ok',coalesce((v_out->>'ok')::boolean,false) and coalesce((v_in->>'ok')::boolean,false),
    'transferId',p_transfer_id,'source',v_out,'target',v_in);
end;
$$;

create or replace function public.erp_r22_transfer_cloud_cash(
  p_company_id uuid,p_from_cash_account_id text,p_to_cash_account_id text,
  p_source_amount numeric,p_target_amount numeric,p_exchange_rate numeric(38,20),
  p_transfer_date timestamptz,p_notes text default null
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  f public.erp_cash_accounts%rowtype;
  t public.erp_cash_accounts%rowtype;
  fc text; tc text; fl text; tl text;
  source_clearing text; target_clearing text;
  transfer_id text:=gen_random_uuid()::text;
  tx_out text:=gen_random_uuid()::text;
  tx_in text:=gen_random_uuid()::text;
  j_source text:=gen_random_uuid()::text;
  j_target text:=gen_random_uuid()::text;
  voucher text; out_voucher text; in_voucher text;
  source_entry_number text; target_entry_number text;
  available numeric; tolerance numeric; linked text;
  v_source_rebind jsonb; v_target_rebind jsonb;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  perform public.erp_r9_require_field_edit(p_company_id,'cashbox','transferFrom','accounting.update');
  perform public.erp_r9_require_field_edit(p_company_id,'cashbox','transferTo',null);
  perform public.erp_r9_require_field_edit(p_company_id,'cashbox','amount',null);
  perform public.erp_r9_require_field_edit(p_company_id,'cashbox','exchangeRate',null);
  perform public.erp_r9_require_field_edit(p_company_id,'cashbox','operationalDate',null);
  if p_notes is not null then perform public.erp_r9_require_field_edit(p_company_id,'cashbox','notes',null); end if;
  if p_transfer_date is null then raise exception 'transfer_date_required'; end if;
  perform public.erp_validate_operational_date(p_company_id,'accounting',p_transfer_date);
  if p_from_cash_account_id is null or p_to_cash_account_id is null
     or p_from_cash_account_id=p_to_cash_account_id
     or coalesce(p_source_amount,0)<=0 or coalesce(p_target_amount,0)<=0
     or coalesce(p_exchange_rate,0)<=0 then raise exception 'invalid_cash_transfer'; end if;

  select * into f from public.erp_cash_accounts
  where company_id=p_company_id and id=p_from_cash_account_id and not is_deleted for update;
  select * into t from public.erp_cash_accounts
  where company_id=p_company_id and id=p_to_cash_account_id and not is_deleted for update;
  if f.id is null or t.id is null then raise exception 'cashbox_not_found'; end if;
  if not public.erp_try_boolean(coalesce(f.data->>'isActive',f.data->>'is_active'),'true')
     or not public.erp_try_boolean(coalesce(t.data->>'isActive',t.data->>'is_active'),'true') then
    raise exception 'cashbox_inactive';
  end if;
  fc:=upper(coalesce(f.data->>'currency',''));
  tc:=upper(coalesce(t.data->>'currency',''));
  fl:=nullif(coalesce(f.data->>'accountId',f.data->>'account_id'),'');
  tl:=nullif(coalesce(t.data->>'accountId',t.data->>'account_id'),'');
  if fc not in ('IQD','USD') or tc not in ('IQD','USD') then raise exception 'cashbox_currency_invalid'; end if;
  if fl is null or tl is null then raise exception 'cashbox_ledger_required'; end if;
  perform public.erp_phase2_account_guard(p_company_id,fl,'asset',fc);
  perform public.erp_phase2_account_guard(p_company_id,tl,'asset',tc);

  tolerance:=greatest(0.01,abs(p_target_amount)*0.00001);
  if fc=tc then
    if abs(p_exchange_rate-1)>0.000001 or abs(p_source_amount-p_target_amount)>tolerance then
      raise exception 'same_currency_transfer_requires_rate_one';
    end if;
  else
    if abs(p_target_amount-(p_source_amount*p_exchange_rate))>tolerance then
      raise exception 'cash_amount_exchange_rate_mismatch';
    end if;
    linked:=public.erp_resolve_linked_cash_account(p_company_id,p_from_cash_account_id,tc);
    if linked is distinct from p_to_cash_account_id then raise exception 'cashboxes_not_linked_for_fx'; end if;
    source_clearing:=public.erp_ensure_fx_clearing_account(p_company_id,fc);
    target_clearing:=public.erp_ensure_fx_clearing_account(p_company_id,tc);
  end if;

  select balance into available from public.erp_cloud_cash_account_balances(p_company_id)
  where cash_account_id=p_from_cash_account_id;
  if coalesce(available,0)<p_source_amount then raise exception 'source_cashbox_balance_insufficient'; end if;

  voucher:=public.erp_next_document_number(p_company_id,'cash_transfer','CT',p_transfer_date);
  out_voucher:=public.erp_next_document_number(p_company_id,'cash_payment','CP',p_transfer_date);
  in_voucher:=public.erp_next_document_number(p_company_id,'cash_receipt','CR',p_transfer_date);
  source_entry_number:=public.erp_next_document_number(p_company_id,'journal_entry','JE',p_transfer_date);
  if fc<>tc then target_entry_number:=public.erp_next_document_number(p_company_id,'journal_entry','JE',p_transfer_date); end if;

  insert into public.erp_cash_transfers(company_id,id,data,created_by,updated_by)
  values(p_company_id,transfer_id,jsonb_build_object(
    'id',transfer_id,'transferNumber',voucher,'fromAccountId',p_from_cash_account_id,'toAccountId',p_to_cash_account_id,
    'sourceAmount',p_source_amount,'sourceCurrency',fc,'targetAmount',p_target_amount,'targetCurrency',tc,
    'exchangeRate',p_exchange_rate,'transferDate',p_transfer_date,'notes',p_notes,'status','posted',
    'sourceTransactionId',tx_out,'targetTransactionId',tx_in,'sourceJournalId',j_source,
    'targetJournalId',case when fc=tc then null else j_target end,
    'runtimeVersion','r22','canonicalIdentity',true),auth.uid(),auth.uid());

  insert into public.erp_cash_transactions(company_id,id,data,created_by,updated_by) values
  (p_company_id,tx_out,jsonb_build_object(
    'id',tx_out,'voucherNumber',out_voucher,'type','payment','category','cash_transfer',
    'amount',p_source_amount,'currency',fc,'transactionDate',p_transfer_date,
    'referenceType','cash_transfer','referenceId',transfer_id,'cashAccountId',p_from_cash_account_id,
    'cashLedgerAccountId',fl,'counterAccountId',case when fc=tc then tl else source_clearing end,
    'journalEntryId',j_source,'notes',p_notes,'r22CanonicalCashBinding',true),auth.uid(),auth.uid()),
  (p_company_id,tx_in,jsonb_build_object(
    'id',tx_in,'voucherNumber',in_voucher,'type','receipt','category','cash_transfer',
    'amount',p_target_amount,'currency',tc,'transactionDate',p_transfer_date,
    'referenceType','cash_transfer','referenceId',transfer_id,'cashAccountId',p_to_cash_account_id,
    'cashLedgerAccountId',tl,'counterAccountId',case when fc=tc then fl else target_clearing end,
    'journalEntryId',case when fc=tc then j_source else j_target end,'notes',p_notes,
    'r22CanonicalCashBinding',true),auth.uid(),auth.uid());

  insert into public.erp_journal_entries(company_id,id,data,created_by,updated_by)
  values(p_company_id,j_source,jsonb_build_object(
    'id',j_source,'entryNumber',source_entry_number,'entryDate',p_transfer_date,
    'description','Cashbox transfer','currency',fc,
    'referenceType',case when fc=tc then 'cash_transfer' else 'cash_transfer_source' end,
    'referenceId',transfer_id,'cashTransactionIds',jsonb_build_array(tx_out,case when fc=tc then tx_in else null end),
    'totalDebit',p_source_amount,'totalCredit',p_source_amount,'status','posted','createdAt',now(),
    'r22CanonicalCashTransfer',true),auth.uid(),auth.uid());

  insert into public.erp_journal_lines(company_id,id,data,created_by,updated_by) values
  (p_company_id,gen_random_uuid()::text,jsonb_build_object(
    'entryId',j_source,'accountId',case when fc=tc then tl else source_clearing end,'currency',fc,
    'referenceType',case when fc=tc then 'cash_transfer' else 'cash_transfer_source' end,'referenceId',transfer_id,
    'cashTransactionId',case when fc=tc then tx_in else null end,'cashAccountId',case when fc=tc then p_to_cash_account_id else null end,
    'debit',p_source_amount,'credit',0,'description',coalesce(p_notes,'Cashbox transfer'),
    'r22CanonicalCashBinding',fc=tc),auth.uid(),auth.uid()),
  (p_company_id,gen_random_uuid()::text,jsonb_build_object(
    'entryId',j_source,'accountId',fl,'currency',fc,
    'referenceType',case when fc=tc then 'cash_transfer' else 'cash_transfer_source' end,'referenceId',transfer_id,
    'cashTransactionId',tx_out,'cashAccountId',p_from_cash_account_id,
    'debit',0,'credit',p_source_amount,'description',coalesce(p_notes,'Cashbox transfer'),
    'r22CanonicalCashBinding',true),auth.uid(),auth.uid());

  if fc<>tc then
    insert into public.erp_journal_entries(company_id,id,data,created_by,updated_by)
    values(p_company_id,j_target,jsonb_build_object(
      'id',j_target,'entryNumber',target_entry_number,'entryDate',p_transfer_date,
      'description','FX cashbox transfer receipt','currency',tc,
      'referenceType','cash_transfer_target','referenceId',transfer_id,
      'cashTransactionIds',jsonb_build_array(tx_in),
      'totalDebit',p_target_amount,'totalCredit',p_target_amount,'status','posted','createdAt',now(),
      'r22CanonicalCashTransfer',true),auth.uid(),auth.uid());
    insert into public.erp_journal_lines(company_id,id,data,created_by,updated_by) values
    (p_company_id,gen_random_uuid()::text,jsonb_build_object(
      'entryId',j_target,'accountId',tl,'currency',tc,'referenceType','cash_transfer_target','referenceId',transfer_id,
      'cashTransactionId',tx_in,'cashAccountId',p_to_cash_account_id,
      'debit',p_target_amount,'credit',0,'description',coalesce(p_notes,'FX cashbox receipt'),
      'r22CanonicalCashBinding',true),auth.uid(),auth.uid()),
    (p_company_id,gen_random_uuid()::text,jsonb_build_object(
      'entryId',j_target,'accountId',target_clearing,'currency',tc,'referenceType','cash_transfer_target','referenceId',transfer_id,
      'debit',0,'credit',p_target_amount,'description',coalesce(p_notes,'FX cashbox receipt')),
      auth.uid(),auth.uid());
  end if;

  perform public.erp_v762_assert_posted_journal_balanced(p_company_id,j_source,'r22_cash_transfer_source');
  if fc<>tc then perform public.erp_v762_assert_posted_journal_balanced(p_company_id,j_target,'r22_cash_transfer_target'); end if;
  v_source_rebind:=public.erp_r15_rebind_cashbox_journals_internal(p_company_id,p_from_cash_account_id);
  v_target_rebind:=public.erp_r15_rebind_cashbox_journals_internal(p_company_id,p_to_cash_account_id);

  return jsonb_build_object(
    'ok',true,'version','r22','transferId',transfer_id,'transferNumber',voucher,
    'sourceTransactionId',tx_out,'targetTransactionId',tx_in,
    'sourceJournalId',j_source,'targetJournalId',case when fc=tc then null else j_target end,
    'sourceReconciliation',v_source_rebind,'targetReconciliation',v_target_rebind);
end;
$$;

-- R22 cash namespace. The browser no longer depends on R9 cache exposure.
create or replace function public.erp_r22_list_cloud_ledger_accounts(p_company_id uuid)
returns setof jsonb language sql stable security definer set search_path=public as $$
  select * from public.erp_r9_list_cloud_ledger_accounts($1)
$$;
create or replace function public.erp_r22_save_cloud_cash_account(p_company_id uuid,p_account jsonb)
returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_r15_save_cloud_cash_account(p_company_id,p_account);
  perform public.erp_r15_rebind_cashbox_journals_internal(p_company_id,p_account->>'id');
end;
$$;
create or replace function public.erp_r22_post_cloud_cash_transaction(
  p_company_id uuid,p_transaction jsonb,p_replace boolean default false
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_r15_post_cloud_cash_transaction(p_company_id,p_transaction,p_replace);
  if nullif(coalesce(p_transaction->>'cashAccountId',p_transaction->>'cash_account_id'),'') is not null then
    perform public.erp_r15_rebind_cashbox_journals_internal(
      p_company_id,coalesce(p_transaction->>'cashAccountId',p_transaction->>'cash_account_id'));
  end if;
end;
$$;
create or replace function public.erp_r22_cloud_cash_account_balances(p_company_id uuid)
returns table(cash_account_id text,balance numeric)
language sql stable security definer set search_path=public as $$
  select * from public.erp_r9_cloud_cash_account_balances($1)
$$;
create or replace function public.erp_r22_cloud_cash_ledger_reconciliation(p_company_id uuid)
returns table(cash_account_id text,cash_account_name text,currency text,
  subledger_balance numeric,ledger_balance numeric,difference numeric)
language sql stable security definer set search_path=public as $$
  select * from public.erp_r9_cloud_cash_ledger_reconciliation($1)
$$;
create or replace function public.erp_r22_cloud_cash_currency_summary(p_company_id uuid,p_currency text)
returns jsonb language sql stable security definer set search_path=public as $$
  select public.erp_r9_cloud_cash_currency_summary($1,$2)
$$;

-- Compatibility for R9/R15 callers: all future transfers use the canonical R22
-- implementation even before the new Firebase bundle reaches every browser.
create or replace function public.erp_r9_transfer_cloud_cash(
  p_company_id uuid,p_from_cash_account_id text,p_to_cash_account_id text,
  p_source_amount numeric,p_target_amount numeric,p_exchange_rate numeric(38,20),
  p_transfer_date timestamptz,p_notes text default null
) returns void language plpgsql security definer set search_path=public as $$
declare v jsonb;
begin
  v:=public.erp_r22_transfer_cloud_cash(
    p_company_id,p_from_cash_account_id,p_to_cash_account_id,p_source_amount,
    p_target_amount,p_exchange_rate,p_transfer_date,p_notes);
  if coalesce((v->>'ok')::boolean,false) is not true then raise exception 'r22_cash_transfer_failed:%',v::text; end if;
end;
$$;
create or replace function public.erp_r15_transfer_cloud_cash(
  p_company_id uuid,p_from_cash_account_id text,p_to_cash_account_id text,
  p_source_amount numeric,p_target_amount numeric,p_exchange_rate numeric(38,20),
  p_transfer_date timestamptz,p_notes text default null
) returns void language sql security definer set search_path=public as $$
  select public.erp_r9_transfer_cloud_cash($1,$2,$3,$4,$5,$6,$7,$8)
$$;

-- Historical purchase-accounting consolidation.  Approved legacy invoices are
-- re-posted from their source order to the current Supplier <-> Inventory policy.
-- Valuation/FIFO is not replayed here: those are source-owned historical facts;
-- only the derived accounting entries are replaced.  Ambiguous/mixed-currency
-- historical cases fail closed and remain visible to canonical reconciliation.
create or replace function public.erp_r22_normalize_legacy_purchase_invoice(
  p_company_id uuid,p_invoice_id uuid
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  d public.erp_commercial_workflow_documents%rowtype;
  v_currency text;
  v_total numeric;
  v_effective timestamptz;
  v_supplier_id text;
  v_supplier_account text;
  v_subtotal numeric;
  v_factor numeric:=1;
  v_lines jsonb:='[]'::jsonb;
  v_total_debit numeric:=0;
  v_amount numeric;
  v_entry text;
  v_old_ids text[]:=array[]::text[];
  v_old_id text;
  v_temp_period uuid;
  v_needs_override boolean:=false;
  r record;
  ac jsonb;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if not public.is_company_admin(p_company_id) then
    raise exception 'company_admin_required' using errcode='42501';
  end if;

  select * into d from public.erp_commercial_workflow_documents
  where company_id=p_company_id and id=p_invoice_id and module='purchases'
    and document_type='invoice' and status='approved' and not is_deleted for update;
  if not found then raise exception 'approved_purchase_invoice_not_found'; end if;

  if not exists(
    select 1 from public.erp_r15_legacy_capitalized_purchase_invoices(p_company_id) x
    where x=p_invoice_id
  ) then
    return jsonb_build_object('ok',true,'invoiceId',p_invoice_id,'alreadyCanonical',true,'version','r22');
  end if;

  v_currency:=upper(coalesce(d.payload->>'currency',''));
  v_total:=public.erp_try_numeric(d.payload->>'totalAmount',0);
  v_effective:=coalesce(d.effective_at,d.created_at,now());
  select supplier_id,subtotal into v_supplier_id,v_subtotal
  from public.erp_purchase_orders_cloud
  where company_id=p_company_id and id=d.parent_id and not is_deleted;
  if not found or v_supplier_id is null or v_currency not in ('USD','IQD') or v_total<=0 then
    raise exception 'legacy_purchase_invoice_source_invalid';
  end if;

  perform public.erp_v767_assert_partner_ledgers(p_company_id,v_supplier_id,'supplier');
  v_supplier_account:=public.erp_workflow_partner_account(
    p_company_id,'supplier',v_supplier_id,v_currency);
  perform public.erp_phase2_account_guard(p_company_id,v_supplier_account,'liability',v_currency);
  v_factor:=case when coalesce(v_subtotal,0)>0 then v_total/v_subtotal else 1 end;

  for r in
    select * from public.erp_purchase_order_items_cloud
    where company_id=p_company_id and order_id=d.parent_id and not is_deleted
    order by id
  loop
    ac:=public.erp_v736_item_accounting(p_company_id,r.item_type,r.item_id,null);
    if lower(coalesce(ac->>'itemKind','stock'))='service' then
      raise exception 'legacy_purchase_service_not_inventory_item:%',r.item_id;
    end if;
    if upper(coalesce(ac->>'costCurrency',''))<>v_currency then
      raise exception 'legacy_purchase_currency_ambiguous:%:%:%',
        r.item_id,upper(coalesce(ac->>'costCurrency','')),v_currency;
    end if;
    perform public.erp_phase2_account_guard(
      p_company_id,ac->>'assetAccountId','asset',v_currency);
    v_amount:=r.line_total*v_factor;
    v_total_debit:=v_total_debit+v_amount;
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
      'accountId',ac->>'assetAccountId','debit',v_amount,'credit',0,
      'description','تسوية تاريخية - مخزون شراء - '||r.description,
      'itemType',r.item_type,'itemId',r.item_id,
      'r22HistoricalCanonicalRepost',true));
  end loop;

  if jsonb_array_length(v_lines)=0 then raise exception 'legacy_purchase_invoice_items_missing'; end if;
  if abs(v_total_debit-v_total)>0.01 then
    raise exception 'legacy_purchase_invoice_line_total_mismatch:%:%',v_total_debit,v_total;
  end if;
  v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
    'accountId',v_supplier_account,'debit',0,'credit',v_total,
    'description','تسوية تاريخية - ذمة المورد - فاتورة شراء',
    'r22HistoricalCanonicalRepost',true));

  select coalesce(array_agg(je.id order by je.created_at,je.id),array[]::text[])
    into v_old_ids
  from public.erp_journal_entries je
  where je.company_id=p_company_id and not je.is_deleted
    and je.data->>'referenceId'=p_invoice_id::text
    and lower(coalesce(je.data->>'referenceType','')) like 'purchase_invoice%';

  v_needs_override:=exists(select 1 from public.erp_operational_periods
      where company_id=p_company_id and not is_deleted and module in ('all','purchase','purchases'))
    and not exists(select 1 from public.erp_operational_periods
      where company_id=p_company_id and not is_deleted and status='open'
        and module in ('all','purchase','purchases') and v_effective between starts_at and ends_at);
  if v_needs_override then
    v_temp_period:=gen_random_uuid();
    insert into public.erp_operational_periods(
      id,company_id,module,period_name,starts_at,ends_at,status,notes,created_by,updated_by
    ) values(
      v_temp_period,p_company_id,'all','R22-TECHNICAL-RECONCILIATION-'||p_invoice_id::text,
      v_effective-interval '1 minute',v_effective+interval '1 minute','open',
      'Transaction-local period for canonical historical purchase accounting rebuild',
      auth.uid(),auth.uid()
    );
  end if;

  begin
    foreach v_old_id in array v_old_ids loop
      perform public.erp_v736_void_journal_id(p_company_id,v_old_id);
    end loop;
    v_entry:=public.erp_phase2_insert_journal_at(
      p_company_id,'purchase_invoice',p_invoice_id::text,
      public.erp_next_document_number(p_company_id,'purchase_invoice_journal','PIJ',v_effective),
      'R22 إعادة بناء قيد فاتورة شراء: المورد مقابل المخزون '||d.document_number,
      v_currency,v_lines,v_effective);
    perform public.erp_v762_assert_posted_journal_balanced(
      p_company_id,v_entry,'r22_historical_purchase_invoice');
  exception when others then
    if v_temp_period is not null then
      delete from public.erp_operational_periods where id=v_temp_period;
    end if;
    raise;
  end;
  if v_temp_period is not null then
    delete from public.erp_operational_periods where id=v_temp_period;
  end if;

  update public.erp_journal_entries
  set data=data||jsonb_build_object(
      'r22CanonicalReconciliation',true,
      'reconciledFromLegacyCapitalization',true,
      'accountingPolicy','direct_supplier_inventory',
      'r22ReconciledAt',now()),updated_at=now(),updated_by=auth.uid()
  where company_id=p_company_id and id=v_entry and not is_deleted;

  update public.erp_commercial_workflow_documents
  set payload=(payload-'costJournalEntries')||jsonb_build_object(
      'journalEntryId',v_entry,'costJournalEntries','[]'::jsonb,
      'r15CanonicalReconciliation',true,'r22CanonicalReconciliation',true,
      'r22ReconciledAt',now(),'accountingOwner','invoice',
      'accountingPolicy','direct_supplier_inventory',
      'r22HistoricalCanonicalRepost',true,
      'r22RetiredJournalIds',to_jsonb(v_old_ids)),updated_at=now(),updated_by=auth.uid()
  where company_id=p_company_id and id=p_invoice_id;

  perform public.erp_commercial_audit(
    p_company_id,'purchases',d.parent_id,d.id,d.document_number,
    'reconcile_invoice_accounting','approved','approved',
    'R22 rebuilt legacy purchase accounting from source: Supplier-to-Inventory; valuation/FIFO preserved');

  return jsonb_build_object(
    'ok',true,'invoiceId',p_invoice_id,'normalized',true,'version','r22',
    'journalEntryId',v_entry,'retiredJournalCount',coalesce(array_length(v_old_ids,1),0),
    'temporaryPeriodUsed',v_needs_override,'postingMode','direct_supplier_inventory');
end;
$$;

-- R15/R16 reconciliation callers are retained for compatibility but converge
-- to the R22 direct historical accounting rebuild instead of V7.6.0 clearing/FX
-- normalization.
create or replace function public.erp_r15_normalize_legacy_purchase_invoice(
  p_company_id uuid,p_invoice_id uuid
) returns jsonb
language sql security definer set search_path=public as $$
  select public.erp_r22_normalize_legacy_purchase_invoice($1,$2)
$$;

create or replace function public.erp_r22_cash_health(p_company_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare
  v_diff bigint:=0;
  v_open bigint:=0;
  v_bad_pairs bigint:=0;
begin
  select count(*) into v_diff from public.erp_cloud_cash_ledger_reconciliation(p_company_id)
  where abs(coalesce(difference,0))>0.01;
  select count(*) into v_open from public.erp_canonical_reconciliation_issues
  where company_id=p_company_id and resolved_at is null
    and (entity_type in ('cash_transaction','cash_transfer') or issue_type like '%cash%');
  select count(*) into v_bad_pairs from public.erp_cash_transfers t
  where t.company_id=p_company_id and not t.is_deleted and (
    (select count(*) from public.erp_cash_transactions ct
      where ct.company_id=t.company_id and not ct.is_deleted
        and lower(coalesce(ct.data->>'referenceType',ct.data->>'reference_type',''))='cash_transfer'
        and coalesce(ct.data->>'referenceId',ct.data->>'reference_id')=t.id)<>2
  );
  return jsonb_build_object('ok',v_diff=0 and v_open=0 and v_bad_pairs=0,
    'cashboxLedgerMismatchCount',v_diff,'openCashReconciliationIssueCount',v_open,
    'invalidCashTransferPairCount',v_bad_pairs,'checkedAt',timezone('utc',now()));
end;
$$;

create or replace function public.erp_r22_reconcile_company_state(p_company_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_pre_health jsonb;
  v_base jsonb:=jsonb_build_object('ok',true,'skipped',true,'reason','canonical_non_cash_state_already_clean');
  v_cash record;
  v_transfer record;
  v_cashbox_results jsonb:='[]'::jsonb;
  v_results jsonb:='[]'::jsonb;
  v_failures integer:=0;
  v_result jsonb;
  v_needs_base boolean:=false;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if not public.is_company_admin(p_company_id) then
    raise exception 'company_admin_required' using errcode='42501';
  end if;

  -- Do not rebuild the whole company on every administrator login.  The full
  -- R16 pass is needed only while non-cash canonical contamination exists.
  v_pre_health:=public.erp_r16_current_state_health(p_company_id);
  v_needs_base:=
       public.erp_try_numeric(v_pre_health->>'persistentDeletionConflictCount',0)>0
    or public.erp_try_numeric(v_pre_health->>'resurrectedMasterCount',0)>0
    or public.erp_try_numeric(v_pre_health->>'activeLegacyCapitalizationAccountCount',0)>0
    or public.erp_try_numeric(v_pre_health->>'historicalCapitalizationLineCount',0)>0
    or public.erp_try_numeric(v_pre_health->>'legacyCapitalizedPurchaseInvoiceCount',0)>0;
  if v_needs_base then
    -- R16 -> R15 historical purchase normalization resolves at runtime to the
    -- R22 direct historical repost defined above.
    v_base:=public.erp_r16_reconcile_company_state(p_company_id);
  end if;

  -- Rebind only cashboxes whose current cash ledger does not reconcile.  This
  -- closes historical ledger-link changes without scanning every clean box.
  for v_cash in
    select distinct r.cash_account_id id
    from public.erp_cloud_cash_ledger_reconciliation(p_company_id) r
    where abs(coalesce(r.difference,0))>0.01
    order by r.cash_account_id
  loop
    begin
      v_result:=public.erp_r15_rebind_cashbox_journals_internal(p_company_id,v_cash.id);
      v_cashbox_results:=v_cashbox_results||jsonb_build_array(v_result);
    exception when others then
      v_failures:=v_failures+1;
      v_cashbox_results:=v_cashbox_results||jsonb_build_array(jsonb_build_object(
        'ok',false,'cashAccountId',v_cash.id,'code',sqlstate,'error',sqlerrm));
    end;
  end loop;

  -- Exact transfer repair is incremental.  Once both cash transactions have
  -- an R22 canonical binding, later logins do not revisit that transfer unless
  -- a still-open transfer reconciliation issue explicitly requires it.
  for v_transfer in
    select distinct t.id
    from public.erp_cash_transfers t
    where t.company_id=p_company_id and not t.is_deleted
      and (
        exists(
          select 1 from public.erp_cash_transactions ct
          where ct.company_id=t.company_id and not ct.is_deleted
            and lower(coalesce(ct.data->>'referenceType',ct.data->>'reference_type',''))='cash_transfer'
            and coalesce(ct.data->>'referenceId',ct.data->>'reference_id')=t.id
            and not public.erp_try_boolean(ct.data->>'r22CanonicalCashBinding','false')
        )
        or exists(
          select 1 from public.erp_canonical_reconciliation_issues i
          where i.company_id=t.company_id and i.resolved_at is null
            and i.entity_type='cash_transfer' and i.entity_id=t.id
        )
      )
    order by t.id
  loop
    begin
      v_result:=public.erp_r22_repair_cash_transfer(p_company_id,v_transfer.id);
      v_results:=v_results||jsonb_build_array(v_result);
      if coalesce((v_result->>'ok')::boolean,false) is not true then
        v_failures:=v_failures+1;
      end if;
    exception when others then
      v_failures:=v_failures+1;
      v_results:=v_results||jsonb_build_array(jsonb_build_object(
        'ok',false,'transferId',v_transfer.id,'code',sqlstate,'error',sqlerrm));
    end;
  end loop;

  return jsonb_build_object(
    'ok',coalesce((public.erp_r22_cash_health(p_company_id)->>'ok')::boolean,false)
      and coalesce((public.erp_r16_current_state_health(p_company_id)->>'ok')::boolean,false),
    'version','r22','fullCanonicalPassExecuted',v_needs_base,'base',v_base,
    'repairFailures',v_failures,'cashboxRepairs',v_cashbox_results,
    'cashTransfers',v_results,'cashHealth',public.erp_r22_cash_health(p_company_id),
    'health',public.erp_r16_current_state_health(p_company_id),
    'currentStateHealth',public.erp_r16_current_state_health(p_company_id));
end;
$$;

-- Phase-26 and runtime-contract facades live in the same R22 namespace so a
-- fresh schema reload exposes one coherent browser contract.
create or replace function public.erp_r22_phase26_cloud_command(
  p_area text,p_action text,p_payload jsonb default '{}'::jsonb
) returns jsonb language sql security definer set search_path=public as $$
  select public.erp_r14_phase26_cloud_command($1,$2,$3)
$$;

create or replace function public.erp_r22_runtime_contract_probe(p_company_id uuid)
returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'ok',auth.uid() is not null and public.is_active_company_member(p_company_id),
    'r22Phase26',to_regprocedure('public.erp_r22_phase26_cloud_command(text,text,jsonb)') is not null,
    'r22SalesApprove',to_regprocedure('public.erp_r22_approve_sales_invoice(uuid,uuid)') is not null,
    'r22PurchaseApprove',to_regprocedure('public.erp_r22_approve_purchase_invoice(uuid,uuid)') is not null,
    'r22DirectPurchase',to_regprocedure('public.erp_r22_post_purchase_invoice_direct(uuid,uuid)') is not null,
    'r22HistoricalPurchaseRebuild',to_regprocedure('public.erp_r22_normalize_legacy_purchase_invoice(uuid,uuid)') is not null,
    'r22CashTransfer',to_regprocedure('public.erp_r22_transfer_cloud_cash(uuid,text,text,numeric,numeric,numeric,timestamptz,text)') is not null,
    'r22CashReconciliation',to_regprocedure('public.erp_r22_cloud_cash_ledger_reconciliation(uuid)') is not null,
    'r22StateReconcile',to_regprocedure('public.erp_r22_reconcile_company_state(uuid)') is not null,
    'r15MasterList',to_regprocedure('public.erp_r15_list_cloud_master_records(uuid,text)') is not null,
    'r15MasterGet',to_regprocedure('public.erp_r15_get_cloud_master_record(uuid,text,text)') is not null,
    'r15MasterUpsert',to_regprocedure('public.erp_r15_upsert_cloud_master_record(uuid,text,text,jsonb,bigint)') is not null,
    'r15MasterDelete',to_regprocedure('public.erp_r15_soft_delete_cloud_master_record(uuid,text,text,bigint)') is not null,
    'masterContractsOk',jsonb_array_length(public.erp_r14_master_contract_issues())=0,
    'masterContractIssues',public.erp_r14_master_contract_issues(),
    'persistentDeletionRegistry',to_regclass('public.erp_canonical_deletion_tombstones') is not null,
    'identitySafeCashReconciliation',to_regprocedure('public.erp_r22_bind_cash_transaction_exact(uuid,text,text)') is not null,
    'cashHealth',public.erp_r22_cash_health(p_company_id),
    'currentStateHealth',public.erp_r16_current_state_health(p_company_id),
    'canonicalStateVersion',22,
    'checkedAt',timezone('utc',now())
  )
$$;

-- Accounting write namespace: the current browser uses one R22 PostgREST
-- surface for the general ledger, expenses and fixed assets as well.  The
-- mature R9 field-permission guards remain the implementation behind it.
create or replace function public.erp_r22_save_cloud_ledger_account(
  p_company_id uuid,p_account jsonb,p_require_existing boolean default false
) returns void language sql security definer set search_path=public as $$
  select public.erp_r9_save_cloud_ledger_account($1,$2,$3)
$$;
create or replace function public.erp_r22_post_cloud_manual_journal(
  p_company_id uuid,p_entry jsonb,p_lines jsonb
) returns void language sql security definer set search_path=public as $$
  select public.erp_r9_post_cloud_manual_journal($1,$2,$3)
$$;
create or replace function public.erp_r22_update_cloud_manual_journal(
  p_company_id uuid,p_entry jsonb,p_lines jsonb
) returns void language sql security definer set search_path=public as $$
  select public.erp_r9_update_cloud_manual_journal($1,$2,$3)
$$;
create or replace function public.erp_r22_post_cloud_expense(
  p_company_id uuid,p_expense jsonb
) returns jsonb language sql security definer set search_path=public as $$
  select public.erp_r9_post_cloud_expense($1,$2)
$$;
create or replace function public.erp_r22_save_fixed_asset(
  p_company_id uuid,p_asset jsonb
) returns uuid language sql security definer set search_path=public as $$
  select public.erp_r9_save_fixed_asset($1,$2)
$$;
create or replace function public.erp_r22_post_fixed_asset_depreciation_at(
  p_company_id uuid,p_asset_id uuid,p_effective_at timestamptz default now()
) returns uuid language sql security definer set search_path=public as $$
  select public.erp_r9_post_fixed_asset_depreciation_at($1,$2,$3)
$$;

-- Accounting read namespace: the current browser no longer depends on R9
-- PostgREST exposure for the accounting dashboard/reports.
create or replace function public.erp_r22_list_journal_lines(p_company_id uuid,p_entry_id text)
returns setof jsonb language sql stable security definer set search_path=public as $$
  select * from public.erp_r9_list_journal_lines($1,$2)
$$;
create or replace function public.erp_r22_cloud_account_statement(
  p_company_id uuid,p_account_id text,p_from_date timestamptz,p_to_date timestamptz
) returns setof jsonb language sql stable security definer set search_path=public as $$
  select * from public.erp_r9_cloud_account_statement($1,$2,$3,$4)
$$;
create or replace function public.erp_r22_cloud_account_balance_before(
  p_company_id uuid,p_account_id text,p_before_date timestamptz
) returns numeric language sql stable security definer set search_path=public as $$
  select public.erp_r9_cloud_account_balance_before($1,$2,$3)
$$;
create or replace function public.erp_r22_cloud_receivables_payables(p_company_id uuid)
returns jsonb language sql stable security definer set search_path=public as $$
  select public.erp_r9_cloud_receivables_payables($1)
$$;
create or replace function public.erp_r22_cloud_partner_subledger_details_v2(
  p_company_id uuid,p_kind text
) returns setof jsonb language sql stable security definer set search_path=public as $$
  select * from public.erp_r9_cloud_partner_subledger_details_v2($1,$2)
$$;
create or replace function public.erp_r22_cloud_partner_subledger_documents(
  p_company_id uuid,p_kind text,p_party_id text,p_currency text
) returns setof jsonb language sql stable security definer set search_path=public as $$
  select * from public.erp_r9_cloud_partner_subledger_documents($1,$2,$3,$4)
$$;
create or replace function public.erp_r22_cloud_trial_balance(p_company_id uuid,p_currency text)
returns jsonb language sql stable security definer set search_path=public as $$
  select public.erp_r9_cloud_trial_balance($1,$2)
$$;
create or replace function public.erp_r22_cloud_detailed_accounting_report(
  p_company_id uuid,p_report_type text,p_currency text default 'ALL',
  p_branch_id text default null,p_cost_center_id text default null,
  p_from_date timestamptz default null,p_to_date timestamptz default null
) returns setof jsonb language sql stable security definer set search_path=public as $$
  select * from public.erp_r9_cloud_detailed_accounting_report($1,$2,$3,$4,$5,$6,$7)
$$;
create or replace function public.erp_r22_cloud_cash_flow_hierarchy(
  p_company_id uuid,p_currency text default 'ALL',p_branch_id text default null,
  p_cost_center_id text default null,p_from_date timestamptz default null,
  p_to_date timestamptz default null
) returns setof jsonb language sql stable security definer set search_path=public as $$
  select * from public.erp_r9_cloud_cash_flow_hierarchy($1,$2,$3,$4,$5,$6)
$$;
create or replace function public.erp_r22_cloud_expense_total(p_company_id uuid)
returns numeric language sql stable security definer set search_path=public as $$
  select public.erp_r9_cloud_expense_total($1)
$$;
create or replace function public.erp_r22_list_fixed_assets(p_company_id uuid)
returns setof jsonb language sql stable security definer set search_path=public as $$
  select * from public.erp_r9_list_fixed_assets($1)
$$;

-- ---------------------------------------------------------------------------
-- Privileges and schema cache.
-- ---------------------------------------------------------------------------
revoke all on function public.erp_r22_invoice_preflight(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.erp_r22_post_purchase_invoice_direct(uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_r22_approve_workflow_invoice(uuid,uuid,text) from public,anon;
revoke all on function public.erp_r22_approve_sales_invoice(uuid,uuid) from public,anon;
revoke all on function public.erp_r22_approve_purchase_invoice(uuid,uuid) from public,anon;
revoke all on function public.erp_r22_bind_cash_transaction_exact(uuid,text,text) from public,anon,authenticated;
revoke all on function public.erp_r22_repair_cash_transfer(uuid,text) from public,anon,authenticated;
revoke all on function public.erp_r22_transfer_cloud_cash(uuid,text,text,numeric,numeric,numeric,timestamptz,text) from public,anon;
revoke all on function public.erp_r22_list_cloud_ledger_accounts(uuid) from public,anon;
revoke all on function public.erp_r22_save_cloud_cash_account(uuid,jsonb) from public,anon;
revoke all on function public.erp_r22_post_cloud_cash_transaction(uuid,jsonb,boolean) from public,anon;
revoke all on function public.erp_r22_cloud_cash_account_balances(uuid) from public,anon;
revoke all on function public.erp_r22_cloud_cash_ledger_reconciliation(uuid) from public,anon;
revoke all on function public.erp_r22_cloud_cash_currency_summary(uuid,text) from public,anon;
revoke all on function public.erp_r22_cash_health(uuid) from public,anon;
revoke all on function public.erp_r22_reconcile_company_state(uuid) from public,anon;
revoke all on function public.erp_r22_phase26_cloud_command(text,text,jsonb) from public,anon;
revoke all on function public.erp_r22_runtime_contract_probe(uuid) from public,anon;
revoke all on function public.erp_r22_normalize_legacy_purchase_invoice(uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_r22_save_cloud_ledger_account(uuid,jsonb,boolean) from public,anon;
revoke all on function public.erp_r22_post_cloud_manual_journal(uuid,jsonb,jsonb) from public,anon;
revoke all on function public.erp_r22_update_cloud_manual_journal(uuid,jsonb,jsonb) from public,anon;
revoke all on function public.erp_r22_post_cloud_expense(uuid,jsonb) from public,anon;
revoke all on function public.erp_r22_save_fixed_asset(uuid,jsonb) from public,anon;
revoke all on function public.erp_r22_post_fixed_asset_depreciation_at(uuid,uuid,timestamptz) from public,anon;
revoke all on function public.erp_r22_list_journal_lines(uuid,text) from public,anon;
revoke all on function public.erp_r22_cloud_account_statement(uuid,text,timestamptz,timestamptz) from public,anon;
revoke all on function public.erp_r22_cloud_account_balance_before(uuid,text,timestamptz) from public,anon;
revoke all on function public.erp_r22_cloud_receivables_payables(uuid) from public,anon;
revoke all on function public.erp_r22_cloud_partner_subledger_details_v2(uuid,text) from public,anon;
revoke all on function public.erp_r22_cloud_partner_subledger_documents(uuid,text,text,text) from public,anon;
revoke all on function public.erp_r22_cloud_trial_balance(uuid,text) from public,anon;
revoke all on function public.erp_r22_cloud_detailed_accounting_report(uuid,text,text,text,text,timestamptz,timestamptz) from public,anon;
revoke all on function public.erp_r22_cloud_cash_flow_hierarchy(uuid,text,text,text,timestamptz,timestamptz) from public,anon;
revoke all on function public.erp_r22_cloud_expense_total(uuid) from public,anon;
revoke all on function public.erp_r22_list_fixed_assets(uuid) from public,anon;

grant execute on function public.erp_r22_invoice_preflight(uuid,uuid,text) to service_role;
grant execute on function public.erp_r22_post_purchase_invoice_direct(uuid,uuid) to service_role;
grant execute on function public.erp_r22_approve_workflow_invoice(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.erp_r22_approve_sales_invoice(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r22_approve_purchase_invoice(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r22_bind_cash_transaction_exact(uuid,text,text) to service_role;
grant execute on function public.erp_r22_repair_cash_transfer(uuid,text) to service_role;
grant execute on function public.erp_r22_transfer_cloud_cash(uuid,text,text,numeric,numeric,numeric,timestamptz,text) to authenticated,service_role;
grant execute on function public.erp_r22_list_cloud_ledger_accounts(uuid) to authenticated,service_role;
grant execute on function public.erp_r22_save_cloud_cash_account(uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_r22_post_cloud_cash_transaction(uuid,jsonb,boolean) to authenticated,service_role;
grant execute on function public.erp_r22_cloud_cash_account_balances(uuid) to authenticated,service_role;
grant execute on function public.erp_r22_cloud_cash_ledger_reconciliation(uuid) to authenticated,service_role;
grant execute on function public.erp_r22_cloud_cash_currency_summary(uuid,text) to authenticated,service_role;
grant execute on function public.erp_r22_cash_health(uuid) to authenticated,service_role;
grant execute on function public.erp_r22_reconcile_company_state(uuid) to authenticated,service_role;
grant execute on function public.erp_r22_phase26_cloud_command(text,text,jsonb) to authenticated,service_role;
grant execute on function public.erp_r22_runtime_contract_probe(uuid) to authenticated,service_role;
grant execute on function public.erp_r22_normalize_legacy_purchase_invoice(uuid,uuid) to service_role;
grant execute on function public.erp_r22_save_cloud_ledger_account(uuid,jsonb,boolean) to authenticated,service_role;
grant execute on function public.erp_r22_post_cloud_manual_journal(uuid,jsonb,jsonb) to authenticated,service_role;
grant execute on function public.erp_r22_update_cloud_manual_journal(uuid,jsonb,jsonb) to authenticated,service_role;
grant execute on function public.erp_r22_post_cloud_expense(uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_r22_save_fixed_asset(uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_r22_post_fixed_asset_depreciation_at(uuid,uuid,timestamptz) to authenticated,service_role;
grant execute on function public.erp_r22_list_journal_lines(uuid,text) to authenticated,service_role;
grant execute on function public.erp_r22_cloud_account_statement(uuid,text,timestamptz,timestamptz) to authenticated,service_role;
grant execute on function public.erp_r22_cloud_account_balance_before(uuid,text,timestamptz) to authenticated,service_role;
grant execute on function public.erp_r22_cloud_receivables_payables(uuid) to authenticated,service_role;
grant execute on function public.erp_r22_cloud_partner_subledger_details_v2(uuid,text) to authenticated,service_role;
grant execute on function public.erp_r22_cloud_partner_subledger_documents(uuid,text,text,text) to authenticated,service_role;
grant execute on function public.erp_r22_cloud_trial_balance(uuid,text) to authenticated,service_role;
grant execute on function public.erp_r22_cloud_detailed_accounting_report(uuid,text,text,text,text,timestamptz,timestamptz) to authenticated,service_role;
grant execute on function public.erp_r22_cloud_cash_flow_hierarchy(uuid,text,text,text,timestamptz,timestamptz) to authenticated,service_role;
grant execute on function public.erp_r22_cloud_expense_total(uuid) to authenticated,service_role;
grant execute on function public.erp_r22_list_fixed_assets(uuid) to authenticated,service_role;

-- Compatibility functions are deliberately re-granted after replacement.
grant execute on function public.erp_r14_approve_sales_invoice(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r14_approve_purchase_invoice(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_v762_approve_workflow_invoice(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.erp_approve_cloud_sales_workflow_invoice(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_approve_cloud_purchase_workflow_invoice(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_manage_commercial_order_component_v3(uuid,text,uuid,text,uuid,text,text) to authenticated,service_role;
grant execute on function public.erp_r9_transfer_cloud_cash(uuid,text,text,numeric,numeric,numeric,timestamptz,text) to authenticated,service_role;
grant execute on function public.erp_r15_transfer_cloud_cash(uuid,text,text,numeric,numeric,numeric,timestamptz,text) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
