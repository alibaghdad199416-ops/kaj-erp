begin;

-- R99: invoice approval must follow the operational document chain, not a stale
-- literal order-status value. R25 already allows invoice creation after approved
-- logistics even when the order projection advanced beyond "approved". R22 then
-- called the invoice-owned posting engines whose legacy order lookup still
-- required status='approved', so the same valid invoice could fail at approval.
--
-- Normalize the active order stage only inside the posting subtransaction. If
-- any posting/integrity check fails, PostgreSQL rolls that normalization back
-- together with every journal/FIFO/valuation side effect. On success the normal
-- V73 recompute immediately restores the canonical derived order status.
create or replace function public.erp_r22_approve_workflow_invoice(
  p_company_id uuid,p_invoice_id uuid,p_module text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  d public.erp_commercial_workflow_documents%rowtype;
  v_preflight jsonb;
  v_result jsonb;
  v_required_permission text;
  v_order_status text;
  e jsonb;
begin
  if p_module not in ('sales','purchases') then
    return jsonb_build_object(
      'ok',false,'stage','input','code','R22_MODULE',
      'error','invalid_workflow_module','module',p_module
    );
  end if;
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    return jsonb_build_object(
      'ok',false,'stage','authorization','code','42501',
      'error','company_membership_required'
    );
  end if;

  v_required_permission:=case
    when p_module='sales' then 'sales.approve'
    else 'purchases.approve'
  end;
  if not public.erp_cloud_user_has_permission(p_company_id,v_required_permission)
     and not public.is_company_admin(p_company_id) then
    return jsonb_build_object(
      'ok',false,'stage','authorization','code','42501',
      'error','permission_denied:'||v_required_permission
    );
  end if;

  select * into d
  from public.erp_commercial_workflow_documents
  where company_id=p_company_id
    and id=p_invoice_id
    and module=p_module
    and document_type='invoice'
    and not is_deleted
  for update;
  if not found then
    return jsonb_build_object(
      'ok',false,'stage','load','code','P7624',
      'error','workflow_invoice_not_found','invoiceId',p_invoice_id
    );
  end if;

  if d.status='approved' then
    begin
      if nullif(d.payload->>'journalEntryId','') is not null then
        perform public.erp_v762_assert_posted_journal_balanced(
          p_company_id,d.payload->>'journalEntryId','r99_'||p_module||'_invoice'
        );
      end if;
      for e in
        select value
        from jsonb_array_elements(coalesce(d.payload->'costJournalEntries','[]'::jsonb))
      loop
        if nullif(e->>'journalEntryId','') is not null then
          perform public.erp_v762_assert_posted_journal_balanced(
            p_company_id,e->>'journalEntryId','r99_'||p_module||'_cost'
          );
        end if;
      end loop;
    exception when others then
      return jsonb_build_object(
        'ok',false,'stage','integrity','code',sqlstate,'error',sqlerrm,
        'invoiceId',p_invoice_id,'status','approved'
      );
    end;
    return jsonb_build_object(
      'ok',true,'idempotent',true,'version','r99',
      'invoiceId',p_invoice_id,'status','approved'
    );
  end if;

  begin
    v_preflight:=public.erp_r22_invoice_preflight(
      p_company_id,p_invoice_id,p_module
    );
  exception when others then
    return jsonb_build_object(
      'ok',false,'stage','preflight','code',sqlstate,'error',sqlerrm,
      'details',jsonb_build_object(
        'module',p_module,'invoiceId',p_invoice_id,'orderId',d.parent_id
      )::text,
      'hint','Verify approved logistics, partner currency ledger and item definition accounts; the error identifies the exact missing contract.'
    );
  end;

  begin
    -- Lock and validate the operational order before changing any posting state.
    if p_module='sales' then
      select lower(coalesce(status,'')) into v_order_status
      from public.erp_sales_orders_cloud
      where company_id=p_company_id and id=d.parent_id and not is_deleted
      for update;
    else
      select lower(coalesce(status,'')) into v_order_status
      from public.erp_purchase_orders_cloud
      where company_id=p_company_id and id=d.parent_id and not is_deleted
      for update;
    end if;

    if v_order_status is null
       or v_order_status=''
       or v_order_status in ('draft','cancelled','canceled','reversed','deleted','void') then
      raise exception 'active_%_order_required:%',p_module,coalesce(v_order_status,'missing');
    end if;

    -- The older posting engines still select status='approved'. Keep that
    -- compatibility detail transaction-local; canonical status is recomputed
    -- after a fully verified post and automatically rolled back on exceptions.
    if v_order_status<>'approved' then
      if p_module='sales' then
        update public.erp_sales_orders_cloud
        set status='approved'
        where company_id=p_company_id and id=d.parent_id and not is_deleted;
      else
        update public.erp_purchase_orders_cloud
        set status='approved'
        where company_id=p_company_id and id=d.parent_id and not is_deleted;
      end if;
    end if;

    if p_module='sales' then
      perform public.erp_approve_cloud_workflow_invoice(
        p_company_id,p_invoice_id,'sales'
      );
      v_result:=jsonb_build_object(
        'postingMode','sales_invoice_owned_fifo',
        'acceptedOrderStage',v_order_status
      );
    else
      v_result:=public.erp_r22_post_purchase_invoice_direct(
        p_company_id,p_invoice_id
      )||jsonb_build_object('acceptedOrderStage',v_order_status);
    end if;

    select * into d
    from public.erp_commercial_workflow_documents
    where company_id=p_company_id
      and id=p_invoice_id
      and module=p_module
      and not is_deleted;
    if d.status<>'approved' then
      raise exception 'workflow_invoice_not_approved_after_post';
    end if;
    if nullif(d.payload->>'journalEntryId','') is null then
      raise exception 'posting_journal_missing';
    end if;

    perform public.erp_v762_assert_posted_journal_balanced(
      p_company_id,d.payload->>'journalEntryId','r99_'||p_module||'_invoice'
    );
    for e in
      select value
      from jsonb_array_elements(coalesce(d.payload->'costJournalEntries','[]'::jsonb))
    loop
      if nullif(e->>'journalEntryId','') is not null then
        perform public.erp_v762_assert_posted_journal_balanced(
          p_company_id,e->>'journalEntryId','r99_'||p_module||'_cost'
        );
      end if;
    end loop;

    perform public.erp_v73_recompute_commercial_order_status(
      p_company_id,p_module,d.parent_id
    );
  exception when others then
    -- This EXCEPTION block is a PostgreSQL subtransaction boundary: temporary
    -- order-stage normalization and every posting side effect above are rolled
    -- back before this diagnostic result is returned.
    return jsonb_build_object(
      'ok',false,'stage','posting','code',sqlstate,'error',sqlerrm,
      'details',jsonb_build_object(
        'module',p_module,
        'invoiceId',p_invoice_id,
        'orderId',d.parent_id,
        'originalOrderStatus',v_order_status,
        'preflight',v_preflight
      )::text,
      'hint','Posting is atomic. Verify the active order stage, approved logistics and the exact SQL error.'
    );
  end;

  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'ok',true,'version','r99','invoiceId',p_invoice_id,'status','approved',
    'journalEntryId',d.payload->>'journalEntryId','preflight',v_preflight
  );
end;
$$;

revoke all on function public.erp_r22_approve_workflow_invoice(uuid,uuid,text)
  from public,anon;
grant execute on function public.erp_r22_approve_workflow_invoice(uuid,uuid,text)
  to authenticated,service_role;

notify pgrst,'reload schema';
commit;
