begin;

-- R95.3: granular sales/purchase payment authorization closure.
-- Payment amount/currency/cashbox/accounting logic remains owned by V757/V762.
-- This migration changes only authorization boundaries and direct engine
-- exposure so exact workflow payment permissions cannot be bypassed.

do $r95_3_patch$
declare
  v_definition text;
  v_old_guard text := $old_guard$
  perform public.erp_require_any_cloud_permission(
    p_company_id,case when p_module='purchases' then array['cashbox.payment'] else array['cashbox.receipt'] end);
$old_guard$;
  v_new_guard text := $new_guard$
  if p_module='sales' then
    if not public.erp_r95_user_can_perform_action(
      p_company_id,
      'sales.actions.restrict',
      'sales.payment',
      array['cashbox.receipt']
    ) then
      raise exception 'permission_denied:sales.payment' using errcode='42501';
    end if;
  elsif p_module='purchases' then
    if not public.erp_r95_user_can_perform_action(
      p_company_id,
      'purchases.actions.restrict',
      'purchases.payment',
      array['cashbox.payment']
    ) then
      raise exception 'permission_denied:purchases.payment' using errcode='42501';
    end if;
  else
    perform public.erp_require_any_cloud_permission(
      p_company_id,array['cashbox.receipt']
    );
  end if;
$new_guard$;
  v_at integer;
  v_after text;
begin
  select pg_get_functiondef(
    'public.erp_execute_secure_linked_payment_v1(uuid,text,uuid,uuid,text,text,jsonb)'::regprocedure
  ) into v_definition;
  if v_definition is null then
    raise exception 'r95_3_secure_payment_engine_missing';
  end if;

  v_at:=strpos(v_definition,v_old_guard);
  if v_at=0 then
    raise exception 'r95_3_secure_payment_guard_signature_changed';
  end if;
  v_after:=substr(v_definition,v_at+length(v_old_guard));
  if strpos(v_after,v_old_guard)>0 then
    raise exception 'r95_3_secure_payment_guard_ambiguous';
  end if;

  execute replace(v_definition,v_old_guard,v_new_guard);
end;
$r95_3_patch$;

-- V762 is the stable payment integrity surface used by current and compatibility
-- RPCs. Authorize before invoice locking, journal verification or payment work.
create or replace function public.erp_v762_apply_workflow_payment(
  p_company_id uuid,p_invoice_id uuid,p_module text,p_payments jsonb
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  d public.erp_commercial_workflow_documents%rowtype;
  r jsonb;
  v_total numeric;
  v_paid numeric;
  v_remaining numeric;
begin
  if p_module not in ('sales','purchases') then
    raise exception using errcode='P7630',message='invalid_workflow_module';
  end if;

  if p_module='sales' then
    if not public.erp_r95_user_can_perform_action(
      p_company_id,
      'sales.actions.restrict',
      'sales.payment',
      array['cashbox.receipt']
    ) then
      raise exception 'permission_denied:sales.payment' using errcode='42501';
    end if;
  else
    if not public.erp_r95_user_can_perform_action(
      p_company_id,
      'purchases.actions.restrict',
      'purchases.payment',
      array['cashbox.payment']
    ) then
      raise exception 'permission_denied:purchases.payment' using errcode='42501';
    end if;
  end if;

  select * into d from public.erp_commercial_workflow_documents
   where company_id=p_company_id and id=p_invoice_id and module=p_module
     and document_type='invoice' and not is_deleted for update;
  if not found then
    raise exception using errcode='P7630',message='payment_invoice_not_found';
  end if;
  if d.status<>'approved' then
    raise exception using errcode='P7631',message='payment_requires_approved_invoice',detail=d.status;
  end if;
  if nullif(d.payload->>'journalEntryId','') is null then
    raise exception using errcode='P7632',message='payment_requires_posted_invoice';
  end if;
  perform public.erp_v762_assert_posted_journal_balanced(
    p_company_id,d.payload->>'journalEntryId',p_module||'_payment_preflight'
  );
  v_total:=public.erp_try_numeric(d.payload->>'totalAmount',0);
  v_paid:=public.erp_try_numeric(d.payload->>'paidAmount',0);
  v_remaining:=greatest(
    0,
    public.erp_try_numeric(d.payload->>'remainingAmount',v_total-v_paid)
  );
  if v_remaining<=0.001 then
    return jsonb_build_object('ok',true,'idempotent',true,'paymentStatus','paid');
  end if;
  begin
    r:=public.erp_apply_cloud_workflow_invoice_payment_batch(
      p_company_id,p_invoice_id,p_module,p_payments
    );
  exception when others then
    raise exception using errcode=sqlstate,message='workflow_payment_failed',
      detail=jsonb_build_object(
        'module',p_module,'invoiceId',p_invoice_id,
        'remainingAmount',v_remaining,'databaseMessage',sqlerrm,'sqlState',sqlstate
      )::text;
  end;
  select * into d from public.erp_commercial_workflow_documents
   where company_id=p_company_id and id=p_invoice_id;
  perform public.erp_v73_recompute_commercial_order_status(
    p_company_id,p_module,d.parent_id
  );
  return jsonb_build_object(
    'ok',true,'results',coalesce(r,'[]'::jsonb),
    'paidAmount',public.erp_try_numeric(d.payload->>'paidAmount',0),
    'remainingAmount',public.erp_try_numeric(d.payload->>'remainingAmount',0),
    'paymentStatus',coalesce(d.payload->>'paymentStatus','unpaid')
  );
end;
$$;

-- V2300 remains the date-validation entry point, but also records the same
-- action boundary explicitly before it delegates to V762.
create or replace function public.erp_v2300_pay_cloud_workflow_invoice_batch(
  p_company_id uuid,p_invoice_id uuid,p_module text,p_payments jsonb
) returns jsonb
language plpgsql security definer set search_path=public as $$
begin
  if lower(p_module) not in ('sales','purchases') then
    raise exception 'invalid_workflow_module';
  end if;
  if lower(p_module)='sales' then
    if not public.erp_r95_user_can_perform_action(
      p_company_id,
      'sales.actions.restrict',
      'sales.payment',
      array['cashbox.receipt']
    ) then
      raise exception 'permission_denied:sales.payment' using errcode='42501';
    end if;
  else
    if not public.erp_r95_user_can_perform_action(
      p_company_id,
      'purchases.actions.restrict',
      'purchases.payment',
      array['cashbox.payment']
    ) then
      raise exception 'permission_denied:purchases.payment' using errcode='42501';
    end if;
  end if;
  perform public.erp_v2300_validate_payment_dates(
    p_company_id,lower(p_module),p_payments
  );
  return public.erp_v762_apply_workflow_payment(
    p_company_id,p_invoice_id,lower(p_module),p_payments
  );
end;
$$;

-- Raw payment engines are implementation details. Keeping them callable from
-- authenticated clients would bypass the canonical V762/V2300 action boundary.
revoke all on function public.erp_execute_secure_linked_payment_v1(
  uuid,text,uuid,uuid,text,text,jsonb
) from public,anon,authenticated;
grant execute on function public.erp_execute_secure_linked_payment_v1(
  uuid,text,uuid,uuid,text,text,jsonb
) to service_role;

revoke all on function public.erp_apply_cloud_workflow_invoice_payment_batch(
  uuid,uuid,text,jsonb
) from public,anon,authenticated;
grant execute on function public.erp_apply_cloud_workflow_invoice_payment_batch(
  uuid,uuid,text,jsonb
) to service_role;

revoke all on function public.erp_v762_apply_workflow_payment(uuid,uuid,text,jsonb)
  from public,anon;
grant execute on function public.erp_v762_apply_workflow_payment(uuid,uuid,text,jsonb)
  to authenticated,service_role;

revoke all on function public.erp_v2300_pay_cloud_workflow_invoice_batch(uuid,uuid,text,jsonb)
  from public,anon;
grant execute on function public.erp_v2300_pay_cloud_workflow_invoice_batch(uuid,uuid,text,jsonb)
  to authenticated,service_role;

notify pgrst,'reload schema';
commit;
