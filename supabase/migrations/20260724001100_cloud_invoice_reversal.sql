-- Quality Line ERP v17.11.0 P12
-- PostgreSQL-authoritative invoice and payment journal reversal.

create or replace function public.erp_reverse_invoice_cloud(
  p_organization_id uuid,
  p_module text,
  p_invoice_id text,
  p_reason text default 'invoice reversal'
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_workflow_id text;
  v_event_id uuid;
  v_entry public.erp_cloud_journal_entries%rowtype;
  v_reversal_id uuid;
  v_reversal_ids jsonb := '[]'::jsonb;
  v_now timestamptz := now();
  v_table text;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if not public.erp_is_active_member(p_organization_id) then raise exception 'permission_denied'; end if;
  if p_module not in ('sales','purchases') then raise exception 'invalid_module'; end if;

  if p_module = 'sales' then
    select workflow_id into v_workflow_id
    from public.erp_sales_workflows
    where organization_id = p_organization_id
      and aggregate#>>'{invoice,id}' = p_invoice_id
    for update;
  else
    select workflow_id into v_workflow_id
    from public.erp_purchase_workflows
    where organization_id = p_organization_id
      and aggregate#>>'{invoice,id}' = p_invoice_id
    for update;
  end if;
  if v_workflow_id is null then raise exception 'cloud_workflow_not_found'; end if;

  insert into public.erp_financial_events(
    organization_id,module,workflow_id,event_type,idempotency_key,payload,created_by
  ) values (
    p_organization_id,p_module,v_workflow_id,'invoice_reversed',
    p_module||':invoice-reversal:'||p_invoice_id,
    jsonb_build_object('invoiceId',p_invoice_id,'reason',p_reason),auth.uid()
  ) on conflict (organization_id,idempotency_key) do update
    set payload=excluded.payload
  returning id into v_event_id;

  for v_entry in
    select * from public.erp_cloud_journal_entries
    where organization_id=p_organization_id
      and module=p_module
      and workflow_id=v_workflow_id
      and status='posted'
      and reference_type not like '%reversal%'
    order by entry_date,id
    for update
  loop
    select id into v_reversal_id
    from public.erp_cloud_journal_entries
    where organization_id=p_organization_id
      and source_entry_id='REV:'||v_entry.id::text;

    if v_reversal_id is null then
      insert into public.erp_cloud_journal_entries(
        organization_id,financial_event_id,module,workflow_id,source_entry_id,
        entry_number,entry_date,description,currency,reference_type,reference_id,
        total_debit,total_credit,status,posted_by,posted_at
      ) values (
        p_organization_id,v_event_id,p_module,v_workflow_id,'REV:'||v_entry.id::text,
        'REV-'||v_entry.entry_number,v_now,p_reason||' - '||v_entry.description,
        v_entry.currency,coalesce(v_entry.reference_type,'journal')||'_reversal',
        v_entry.reference_id,v_entry.total_credit,v_entry.total_debit,'posted',auth.uid(),v_now
      ) returning id into v_reversal_id;

      insert into public.erp_cloud_journal_lines(
        organization_id,entry_id,source_line_id,line_number,account_id,account_code,
        account_name,debit,credit,description,metadata
      )
      select p_organization_id,v_reversal_id,'REV:'||l.id::text,l.line_number,
        l.account_id,l.account_code,l.account_name,l.credit,l.debit,
        p_reason||coalesce(' - '||l.description,''),
        l.metadata||jsonb_build_object('reversesEntryId',v_entry.id)
      from public.erp_cloud_journal_lines l
      where l.entry_id=v_entry.id;

      update public.erp_cloud_journal_entries set status='reversed'
      where id=v_entry.id;
    end if;
    v_reversal_ids := v_reversal_ids || jsonb_build_array(v_reversal_id);
  end loop;

  if p_module='sales' then
    update public.erp_sales_workflows
    set aggregate=jsonb_set(jsonb_set(aggregate,'{invoice,status}','"cancelled"'::jsonb,true),
      '{invoice,cancellationReason}',to_jsonb(p_reason),true),
      version=version+1,updated_at=v_now,updated_by=auth.uid()
    where organization_id=p_organization_id and workflow_id=v_workflow_id;
  else
    update public.erp_purchase_workflows
    set aggregate=jsonb_set(jsonb_set(aggregate,'{invoice,status}','"cancelled"'::jsonb,true),
      '{invoice,cancellationReason}',to_jsonb(p_reason),true),
      version=version+1,updated_at=v_now,updated_by=auth.uid()
    where organization_id=p_organization_id and workflow_id=v_workflow_id;
  end if;

  return jsonb_build_object('workflowId',v_workflow_id,'journalEntryIds',v_reversal_ids,'duplicate',false);
end;
$$;

grant execute on function public.erp_reverse_invoice_cloud(uuid,text,text,text) to authenticated;
