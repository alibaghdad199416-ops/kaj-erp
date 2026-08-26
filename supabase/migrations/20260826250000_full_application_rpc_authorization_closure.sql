begin;

-- Independent full-application audit finding:
-- V7.6.2 exposed SECURITY DEFINER workflow helpers to authenticated callers,
-- but several entry points trusted the caller-supplied company id and invoice
-- id without enforcing authentication, tenant membership, or the action-level
-- permission at the RPC boundary. Downstream functions are not a substitute
-- for the boundary because the helpers themselves read/lock tenant rows and
-- can return existence/integrity information before delegation.
--
-- Forward-only, data-preserving remediation. Public RPC signatures are kept
-- unchanged so existing Flutter callers remain compatible.

create or replace function public.erp_v762_assert_posted_journal_balanced(
  p_company_id uuid,p_entry_id text,p_context text
) returns void
language plpgsql security definer set search_path=public as $$
declare v_debit numeric; v_credit numeric; v_count integer;
begin
  if auth.uid() is null
     or not public.is_active_company_member(p_company_id)
     or (not public.erp_cloud_user_has_permission(p_company_id,'accounting.post')
         and not public.is_company_admin(p_company_id)) then
    raise exception 'accounting_permission_required' using errcode='42501';
  end if;
  if nullif(btrim(coalesce(p_entry_id,'')),'') is null then
    raise exception using errcode='P7621',message='posting_journal_missing',detail=p_context;
  end if;
  select count(*),coalesce(sum(public.erp_try_numeric(data->>'debit',0)),0),
         coalesce(sum(public.erp_try_numeric(data->>'credit',0)),0)
    into v_count,v_debit,v_credit
    from public.erp_journal_lines
   where company_id=p_company_id and data->>'entryId'=p_entry_id and not is_deleted;
  if v_count<2 then
    raise exception using errcode='P7622',message='posting_journal_lines_missing',detail=p_context||':'||p_entry_id;
  end if;
  if abs(v_debit-v_credit)>0.01 or v_debit<=0 then
    raise exception using errcode='P7623',message='posting_journal_unbalanced',
      detail=jsonb_build_object('context',p_context,'journalEntryId',p_entry_id,'debit',v_debit,'credit',v_credit)::text;
  end if;
end;$$;

create or replace function public.erp_v762_approve_workflow_invoice(
  p_company_id uuid,p_invoice_id uuid,p_module text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare d public.erp_commercial_workflow_documents%rowtype; r jsonb; e jsonb; v_permission text;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  v_permission:=case p_module when 'sales' then 'sales.approve' when 'purchases' then 'purchases.approve' else null end;
  if v_permission is null then
    raise exception using errcode='P7620',message='invalid_workflow_module',detail=coalesce(p_module,'null');
  end if;
  if not public.erp_cloud_user_has_permission(p_company_id,v_permission)
     and not public.is_company_admin(p_company_id) then
    raise exception 'permission_denied' using errcode='42501';
  end if;
  select * into d from public.erp_commercial_workflow_documents
   where company_id=p_company_id and id=p_invoice_id and module=p_module
     and document_type='invoice' and not is_deleted for update;
  if not found then raise exception using errcode='P7624',message='workflow_invoice_not_found'; end if;
  if d.parent_id is null then raise exception using errcode='P7625',message='workflow_invoice_order_missing'; end if;
  if upper(coalesce(d.payload->>'currency','')) not in ('IQD','USD') then
    raise exception using errcode='P7626',message='workflow_invoice_currency_invalid',detail=coalesce(d.payload->>'currency','null');
  end if;
  if public.erp_try_numeric(d.payload->>'totalAmount',0)<=0 then
    raise exception using errcode='P7627',message='workflow_invoice_total_invalid';
  end if;
  if d.status='approved' then
    if nullif(d.payload->>'journalEntryId','') is not null then
      perform public.erp_v762_assert_posted_journal_balanced(p_company_id,d.payload->>'journalEntryId',p_module||'_invoice');
    end if;
    return jsonb_build_object('ok',true,'idempotent',true,'invoiceId',p_invoice_id,'status','approved');
  end if;
  if d.status not in ('draft','pending','submitted') then
    raise exception using errcode='P7628',message='workflow_invoice_status_invalid',detail=d.status;
  end if;
  begin
    r:=public.erp_v760_approve_workflow_invoice(p_company_id,p_invoice_id,p_module);
  exception when others then
    raise exception using errcode=sqlstate,message='workflow_invoice_approval_failed',
      detail=jsonb_build_object('module',p_module,'invoiceId',p_invoice_id,'orderId',d.parent_id,
        'documentNumber',d.document_number,'status',d.status,'databaseMessage',sqlerrm,'sqlState',sqlstate)::text;
  end;
  select * into d from public.erp_commercial_workflow_documents
   where company_id=p_company_id and id=p_invoice_id and not is_deleted;
  if d.status<>'approved' then raise exception using errcode='P7629',message='workflow_invoice_not_approved_after_post'; end if;
  if nullif(d.payload->>'journalEntryId','') is not null then
    perform public.erp_v762_assert_posted_journal_balanced(p_company_id,d.payload->>'journalEntryId',p_module||'_invoice');
  end if;
  for e in select value from jsonb_array_elements(coalesce(d.payload->'costJournalEntries','[]'::jsonb)) loop
    if nullif(e->>'journalEntryId','') is not null then
      perform public.erp_v762_assert_posted_journal_balanced(p_company_id,e->>'journalEntryId',p_module||'_cost');
    end if;
  end loop;
  perform public.erp_v73_recompute_commercial_order_status(p_company_id,p_module,d.parent_id);
  return coalesce(r,'{}'::jsonb)||jsonb_build_object('ok',true,'integrityVerified',true,'invoiceId',p_invoice_id);
end;$$;

create or replace function public.erp_v762_apply_workflow_payment(
  p_company_id uuid,p_invoice_id uuid,p_module text,p_payments jsonb
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare d public.erp_commercial_workflow_documents%rowtype; r jsonb; v_total numeric; v_paid numeric; v_remaining numeric;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if p_module not in ('sales','purchases') then
    raise exception using errcode='P7633',message='invalid_workflow_module',detail=coalesce(p_module,'null');
  end if;
  if not public.erp_cloud_user_has_permission(p_company_id,'cashbox.payment')
     and not public.is_company_admin(p_company_id) then
    raise exception 'permission_denied' using errcode='42501';
  end if;
  select * into d from public.erp_commercial_workflow_documents
   where company_id=p_company_id and id=p_invoice_id and module=p_module
     and document_type='invoice' and not is_deleted for update;
  if not found then raise exception using errcode='P7630',message='payment_invoice_not_found'; end if;
  if d.status<>'approved' then raise exception using errcode='P7631',message='payment_requires_approved_invoice',detail=d.status; end if;
  if nullif(d.payload->>'journalEntryId','') is null then
    raise exception using errcode='P7632',message='payment_requires_posted_invoice';
  end if;
  perform public.erp_v762_assert_posted_journal_balanced(p_company_id,d.payload->>'journalEntryId',p_module||'_payment_preflight');
  v_total:=public.erp_try_numeric(d.payload->>'totalAmount',0);
  v_paid:=public.erp_try_numeric(d.payload->>'paidAmount',0);
  v_remaining:=greatest(0,public.erp_try_numeric(d.payload->>'remainingAmount',v_total-v_paid));
  if v_remaining<=0.001 then return jsonb_build_object('ok',true,'idempotent',true,'paymentStatus','paid'); end if;
  begin
    r:=public.erp_apply_cloud_workflow_invoice_payment_batch(p_company_id,p_invoice_id,p_module,p_payments);
  exception when others then
    raise exception using errcode=sqlstate,message='workflow_payment_failed',
      detail=jsonb_build_object('module',p_module,'invoiceId',p_invoice_id,'remainingAmount',v_remaining,
        'databaseMessage',sqlerrm,'sqlState',sqlstate)::text;
  end;
  select * into d from public.erp_commercial_workflow_documents where company_id=p_company_id and id=p_invoice_id;
  perform public.erp_v73_recompute_commercial_order_status(p_company_id,p_module,d.parent_id);
  return jsonb_build_object('ok',true,'results',coalesce(r,'[]'::jsonb),
    'paidAmount',public.erp_try_numeric(d.payload->>'paidAmount',0),
    'remainingAmount',public.erp_try_numeric(d.payload->>'remainingAmount',0),
    'paymentStatus',coalesce(d.payload->>'paymentStatus','unpaid'));
end;$$;

create or replace function public.erp_v762_assert_maintenance_payment_ready(p_company_id uuid,p_order_id uuid)
returns public.erp_maintenance_orders
language plpgsql security definer set search_path=public as $$
declare o public.erp_maintenance_orders%rowtype;
begin
  if auth.uid() is null
     or not public.is_active_company_member(p_company_id)
     or (not public.erp_cloud_user_has_permission(p_company_id,'maintenance.view')
         and not public.is_company_admin(p_company_id)) then
    raise exception 'maintenance_permission_required' using errcode='42501';
  end if;
  select * into o from public.erp_maintenance_orders where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found then raise exception using errcode='P7640',message='maintenance_order_not_found'; end if;
  if o.pricing_type<>'paid' then raise exception using errcode='P7641',message='maintenance_payment_not_allowed_for_free_order'; end if;
  if o.workflow_stage not in ('invoice_approved','partially_paid','paid','completed') or o.invoice_journal_entry_id is null then
    raise exception using errcode='P7642',message='maintenance_approved_invoice_required',detail=coalesce(o.workflow_stage,'null');
  end if;
  perform public.erp_v762_assert_posted_journal_balanced(p_company_id,o.invoice_journal_entry_id,'maintenance_invoice');
  return o;
end;$$;

notify pgrst,'reload schema';
commit;
