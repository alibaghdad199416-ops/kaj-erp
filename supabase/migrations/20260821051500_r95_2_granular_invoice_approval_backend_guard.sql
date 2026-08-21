begin;

-- R95.2: granular invoice-posting authorization closure.
-- Keep the proven accounting engines intact while making every callable
-- approval route use the same restricted-action contract as Flutter/R95.
--
-- The V742 posting engine is patched at migration time only at its historical
-- broad-permission guard. The patch fails closed if the exact guard cannot be
-- found, so accounting/FIFO/valuation logic is never silently rewritten.

do $r95_2_patch$
declare
  v_definition text;
  v_old_guard text := $old_guard$
  perform public.erp_require_any_cloud_permission(p_company_id,
    case when p_module='sales' then array['sales.approve','sales.update'] else array['purchases.approve','purchases.update'] end);
$old_guard$;
  v_new_guard text := $new_guard$
  if p_module='sales' then
    if not public.erp_r95_user_can_perform_action(
      p_company_id,
      'sales.actions.restrict',
      'sales.invoice.approve',
      array['sales.approve','sales.update']
    ) then
      raise exception 'permission_denied:sales.invoice.approve' using errcode='42501';
    end if;
  else
    if not public.erp_r95_user_can_perform_action(
      p_company_id,
      'purchases.actions.restrict',
      'purchases.invoice.approve',
      array['purchases.approve','purchases.update']
    ) then
      raise exception 'permission_denied:purchases.invoice.approve' using errcode='42501';
    end if;
  end if;
$new_guard$;
  v_at integer;
  v_after text;
begin
  select pg_get_functiondef(
    'public.erp_approve_cloud_workflow_invoice(uuid,uuid,text)'::regprocedure
  ) into v_definition;

  if v_definition is null then
    raise exception 'r95_2_invoice_posting_engine_missing';
  end if;

  v_at:=strpos(v_definition,v_old_guard);
  if v_at=0 then
    raise exception 'r95_2_invoice_posting_guard_signature_changed';
  end if;

  v_after:=substr(v_definition,v_at+length(v_old_guard));
  if strpos(v_after,v_old_guard)>0 then
    raise exception 'r95_2_invoice_posting_guard_ambiguous';
  end if;

  execute replace(v_definition,v_old_guard,v_new_guard);
end;
$r95_2_patch$;

-- R22 is the current browser approval surface. Unrestricted tenants retain the
-- historical broad approval requirement; restricted tenants require the exact
-- invoice-post permission.
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

  v_required_permission:=case
    when p_module='sales' then 'sales.invoice.approve'
    else 'purchases.invoice.approve'
  end;
  if not public.erp_r95_user_can_perform_action(
    p_company_id,
    case
      when p_module='sales' then 'sales.actions.restrict'
      else 'purchases.actions.restrict'
    end,
    v_required_permission,
    case
      when p_module='sales' then array['sales.approve']
      else array['purchases.approve']
    end
  ) then
    return jsonb_build_object(
      'ok',false,'stage','authorization','code','42501',
      'error','permission_denied:'||v_required_permission
    );
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

-- Older component endpoints still converge through V760. Guard V760 before it
-- enters V750, because V750 deliberately catches posting errors and may use a
-- safe accounting fallback. Authorization failures must never become fallback.
create or replace function public.erp_v760_approve_workflow_invoice(
  p_company_id uuid,p_invoice_id uuid,p_module text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare r jsonb;
begin
  if p_module not in ('sales','purchases') then
    raise exception 'invalid_workflow_module' using errcode='22023';
  end if;

  if p_module='sales' then
    if not public.erp_r95_user_can_perform_action(
      p_company_id,
      'sales.actions.restrict',
      'sales.invoice.approve',
      array['sales.approve','sales.update']
    ) then
      raise exception 'permission_denied:sales.invoice.approve' using errcode='42501';
    end if;
  else
    if not public.erp_r95_user_can_perform_action(
      p_company_id,
      'purchases.actions.restrict',
      'purchases.invoice.approve',
      array['purchases.approve','purchases.update']
    ) then
      raise exception 'permission_denied:purchases.invoice.approve' using errcode='42501';
    end if;
  end if;

  r:=public.erp_v750_approve_workflow_invoice_resilient(
    p_company_id,p_invoice_id,p_module
  );
  if p_module='purchases' then
    r:=coalesce(r,'{}'::jsonb)||jsonb_build_object(
      'noCapitalization',
      public.erp_v760_normalize_purchase_invoice_posting(p_company_id,p_invoice_id)
    );
  end if;
  return r;
end;
$$;

-- V750 is an internal resilient engine, not a browser authorization surface.
-- SECURITY DEFINER owners and service_role keep internal compatibility.
revoke all on function public.erp_v750_approve_workflow_invoice_resilient(uuid,uuid,text)
  from public,anon,authenticated;
grant execute on function public.erp_v750_approve_workflow_invoice_resilient(uuid,uuid,text)
  to service_role;

-- Reassert the intended public surfaces.
revoke all on function public.erp_r22_approve_workflow_invoice(uuid,uuid,text)
  from public,anon;
grant execute on function public.erp_r22_approve_workflow_invoice(uuid,uuid,text)
  to authenticated,service_role;

revoke all on function public.erp_v760_approve_workflow_invoice(uuid,uuid,text)
  from public,anon;
grant execute on function public.erp_v760_approve_workflow_invoice(uuid,uuid,text)
  to authenticated,service_role;

notify pgrst,'reload schema';
commit;
