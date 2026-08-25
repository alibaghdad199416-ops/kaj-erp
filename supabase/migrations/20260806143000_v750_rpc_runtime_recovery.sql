-- Quality Line ERP 18.9.20 / V7.5.0
-- Runtime recovery for missing cash-transfer RPC, resilient invoice approval,
-- draft invoice deletion, and reversible sales-order cleanup.
begin;

create or replace function public.erp_transfer_cloud_cash_v2(
  p_company_id uuid,
  p_from_cash_account_id text,
  p_to_cash_account_id text,
  p_source_amount numeric,
  p_target_amount numeric,
  p_exchange_rate numeric,
  p_transfer_date timestamptz,
  p_notes text default null
) returns jsonb
language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_transfer_cloud_cash(
    p_company_id,p_from_cash_account_id,p_to_cash_account_id,
    p_source_amount,p_target_amount,p_exchange_rate,p_transfer_date,p_notes
  );
  return jsonb_build_object('ok',true,'fromCashAccountId',p_from_cash_account_id,
    'toCashAccountId',p_to_cash_account_id,'sourceAmount',p_source_amount,
    'targetAmount',p_target_amount,'exchangeRate',p_exchange_rate);
end;
$$;

create or replace function public.erp_v750_approve_workflow_invoice_resilient(
  p_company_id uuid,p_invoice_id uuid,p_module text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  d public.erp_commercial_workflow_documents%rowtype;
  o_currency text; o_total numeric; v_partner_id text; v_partner_type text;
  v_partner_account text; v_lines jsonb:='[]'::jsonb; v_entry text;
  r record; ac jsonb; v_amount numeric; v_subtotal numeric; v_factor numeric:=1;
  v_error text;
begin
  if p_module not in ('sales','purchases') then raise exception 'invalid_workflow_module'; end if;
  select * into d from public.erp_commercial_workflow_documents
   where company_id=p_company_id and id=p_invoice_id and module=p_module
     and document_type='invoice' and not is_deleted for update;
  if not found then raise exception 'workflow_invoice_not_found'; end if;
  if d.status='approved' then return jsonb_build_object('ok',true,'alreadyApproved',true); end if;
  if d.status<>'draft' then raise exception 'workflow_invoice_invalid_status:%',d.status; end if;

  begin
    perform public.erp_approve_cloud_workflow_invoice(p_company_id,p_invoice_id,p_module);
    return jsonb_build_object('ok',true,'mode','full');
  exception when others then
    v_error:=sqlerrm;
  end;

  -- Safe accounting fallback: invoice currency follows the order/partner;
  -- item inventory currency never blocks customer/supplier invoicing.
  o_currency:=upper(coalesce(d.payload->>'currency',''));
  o_total:=public.erp_try_numeric(d.payload->>'totalAmount',0);
  if o_currency not in ('IQD','USD') or o_total<=0 then
    raise exception 'invoice_fallback_invalid_header:%',v_error;
  end if;

  perform public.erp_v749_prepare_order_invoice_accounts(p_company_id,p_module,d.parent_id,o_currency);
  if p_module='sales' then
    select customer_id,subtotal into v_partner_id,v_subtotal
      from public.erp_sales_orders_cloud
     where company_id=p_company_id and id=d.parent_id and status='approved'
       and not is_deleted and upper(currency)=o_currency;
    v_partner_type:='customer';
  else
    select supplier_id,subtotal into v_partner_id,v_subtotal
      from public.erp_purchase_orders_cloud
     where company_id=p_company_id and id=d.parent_id and status='approved'
       and not is_deleted and upper(currency)=o_currency;
    v_partner_type:='supplier';
  end if;
  if not found then raise exception 'invoice_order_currency_mismatch:%',v_error; end if;
  v_partner_account:=public.erp_workflow_partner_account(
    p_company_id,v_partner_type,v_partner_id,o_currency);
  v_factor:=case when coalesce(v_subtotal,0)>0 then o_total/v_subtotal else 1 end;

  if p_module='sales' then
    v_lines:=jsonb_build_array(jsonb_build_object('accountId',v_partner_account,
      'debit',o_total,'credit',0,'description','Sales invoice receivable'));
    for r in select * from public.erp_sales_order_items_cloud
      where company_id=p_company_id and order_id=d.parent_id and not is_deleted order by id
    loop
      ac:=public.erp_v736_item_accounting(p_company_id,r.item_type,r.item_id,o_currency);
      v_amount:=r.line_total*v_factor;
      v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
        'accountId',ac->>'revenueAccountId','debit',0,'credit',v_amount,
        'description','Sales revenue - '||r.description,'itemType',r.item_type,'itemId',r.item_id));
    end loop;
  else
    v_lines:=jsonb_build_array(jsonb_build_object('accountId',v_partner_account,
      'debit',0,'credit',o_total,'description','Purchase invoice payable'));
    -- Purchase fallback uses the configured inventory asset accounts in order currency
    -- only when they match; otherwise a company clearing asset receives the converted total.
    for r in select * from public.erp_purchase_order_items_cloud
      where company_id=p_company_id and order_id=d.parent_id and not is_deleted order by id
    loop
      ac:=public.erp_v736_item_accounting(p_company_id,r.item_type,r.item_id,null);
      v_amount:=r.line_total*v_factor;
      if upper(ac->>'costCurrency')=o_currency then
        v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
          'accountId',ac->>'assetAccountId','debit',v_amount,'credit',0,
          'description','Purchase inventory - '||r.description,'itemType',r.item_type,'itemId',r.item_id));
      end if;
    end loop;
    if (select coalesce(sum(public.erp_try_numeric(x->>'debit',0)),0)
          from jsonb_array_elements(v_lines) x) < o_total then
      ac:=public.erp_v736_ensure_purchase_clearing_accounts(p_company_id);
      v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
        'accountId',ac->>o_currency,'debit',o_total-(select coalesce(sum(public.erp_try_numeric(x->>'debit',0)),0) from jsonb_array_elements(v_lines) x),
        'credit',0,'description','Purchase invoice currency clearing'));
    end if;
  end if;

  v_entry:=public.erp_phase2_insert_journal_at(
    p_company_id,p_module||'_invoice',p_invoice_id::text,
    public.erp_next_document_number(p_company_id,p_module||'_invoice_journal',case when p_module='sales' then 'SIJ' else 'PIJ' end,coalesce(d.effective_at,d.created_at)),
    case when p_module='sales' then 'Sales invoice ' else 'Purchase invoice ' end||d.document_number,
    o_currency,v_lines,coalesce(d.effective_at,d.created_at));

  update public.erp_commercial_workflow_documents
     set status='approved',updated_at=now(),updated_by=auth.uid(),
         payload=payload||jsonb_build_object('journalEntryId',v_entry,'approvedAt',now(),
           'approvedBy',auth.uid(),'accountingOwner','invoice','fallbackPosting',true,
           'fullPostingError',v_error)
   where company_id=p_company_id and id=p_invoice_id;
  perform public.erp_v73_recompute_commercial_order_status(p_company_id,p_module,d.parent_id);
  return jsonb_build_object('ok',true,'mode','safe_fallback','originalError',v_error);
end;
$$;

create or replace function public.erp_delete_cloud_sales_order_v4(
  p_company_id uuid,p_order_id uuid
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare r jsonb;
begin
  -- Draft invoices must never lock logistics/order deletion.
  update public.erp_commercial_workflow_documents
     set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid(),
         payload=payload||jsonb_build_object('deleteReason','Order cascade draft cleanup')
   where company_id=p_company_id and parent_id=p_order_id and module='sales'
     and document_type='invoice' and status='draft' and not is_deleted;
  begin
    r:=public.erp_delete_cloud_sales_order_v3(p_company_id,p_order_id);
  exception when others then
    r:=public.erp_delete_cloud_sales_order_v2(p_company_id,p_order_id)
       ||jsonb_build_object('v3FallbackError',sqlerrm);
  end;
  return coalesce(r,'{}'::jsonb)||jsonb_build_object('ok',true,'version','v4');
end;
$$;

create or replace function public.erp_manage_commercial_order_component_v2(
  p_company_id uuid,p_module text,p_order_id uuid,p_component_type text,
  p_component_id uuid,p_action text,p_reason text default null
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare d public.erp_commercial_workflow_documents%rowtype; v_result jsonb;
begin
  if p_module not in ('sales','purchases') then raise exception 'invalid_workflow_module'; end if;
  if p_component_type='order' and p_action='delete' and p_module='sales' then
    return public.erp_delete_cloud_sales_order_v4(p_company_id,p_order_id);
  end if;
  if p_component_type='invoice' then
    select * into d from public.erp_commercial_workflow_documents
     where company_id=p_company_id and id=p_component_id and parent_id=p_order_id
       and module=p_module and document_type='invoice' and not is_deleted for update;
    if not found then raise exception 'workflow_component_not_found'; end if;
    if p_action='approve' then
      return public.erp_v750_approve_workflow_invoice_resilient(p_company_id,p_component_id,p_module);
    elsif p_action='delete' then
      if d.status='draft' then
        update public.erp_commercial_workflow_documents
           set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid(),
               payload=payload||jsonb_build_object('deleteReason',coalesce(nullif(btrim(p_reason),''),'Draft invoice deleted'))
         where company_id=p_company_id and id=p_component_id;
        perform public.erp_v73_recompute_commercial_order_status(p_company_id,p_module,p_order_id);
        return jsonb_build_object('ok',true,'componentType','invoice','action','delete','draftDeleted',true);
      end if;
    end if;
  end if;
  return public.erp_manage_commercial_order_component(
    p_company_id,p_module,p_order_id,p_component_type,p_component_id,p_action,p_reason);
end;
$$;

revoke all on function public.erp_transfer_cloud_cash_v2(uuid,text,text,numeric,numeric,numeric,timestamptz,text) from public,anon;
revoke all on function public.erp_v750_approve_workflow_invoice_resilient(uuid,uuid,text) from public,anon;
revoke all on function public.erp_delete_cloud_sales_order_v4(uuid,uuid) from public,anon;
revoke all on function public.erp_manage_commercial_order_component_v2(uuid,text,uuid,text,uuid,text,text) from public,anon;
grant execute on function public.erp_transfer_cloud_cash_v2(uuid,text,text,numeric,numeric,numeric,timestamptz,text) to authenticated,service_role;
grant execute on function public.erp_v750_approve_workflow_invoice_resilient(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.erp_delete_cloud_sales_order_v4(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_manage_commercial_order_component_v2(uuid,text,uuid,text,uuid,text,text) to authenticated,service_role;
notify pgrst,'reload schema';
commit;
