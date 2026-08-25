-- Quality Line ERP v17.10.0 P11
-- PostgreSQL-authoritative payment journal posting and invoice settlement.

create or replace function public.erp_post_payment_cloud(
  p_command_id uuid,
  p_invoice_id text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cmd public.erp_financial_commands%rowtype;
  v_plan public.erp_payment_settlement_plans%rowtype;
  v_workflow jsonb;
  v_invoice jsonb;
  v_partner_id text;
  v_partner_account_id text;
  v_cash_account_id text;
  v_fx_account_id text;
  v_event_id uuid;
  v_entry_id uuid;
  v_entry_number text;
  v_description text;
  v_now timestamptz := now();
  v_account public.erp_accounts%rowtype;
  v_line jsonb;
  v_line_no integer := 0;
  v_total_debit numeric(20,4) := 0;
  v_total_credit numeric(20,4) := 0;
  v_result jsonb;
  v_version bigint;
  v_paid numeric(20,4);
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;

  select * into v_cmd
  from public.erp_financial_commands
  where id = p_command_id
  for update;
  if not found then raise exception 'financial_command_not_found'; end if;
  if not public.erp_is_active_member(v_cmd.organization_id) then raise exception 'permission_denied'; end if;
  if v_cmd.status = 'aborted' then raise exception 'financial_command_aborted'; end if;
  if v_cmd.event_type <> 'invoice_payment_posted' then raise exception 'invalid_financial_command_type'; end if;
  if v_cmd.status = 'committed' then
    return coalesce(v_cmd.result_payload, jsonb_build_object('commandId',v_cmd.id,'status','committed','duplicate',true));
  end if;

  select * into v_plan
  from public.erp_payment_settlement_plans
  where command_id = p_command_id
  for update;
  if not found then raise exception 'payment_settlement_plan_missing'; end if;
  if v_plan.invoice_id <> p_invoice_id then raise exception 'invoice_identity_mismatch'; end if;

  if v_cmd.module = 'sales' then
    select aggregate into v_workflow from public.erp_sales_workflows
      where organization_id=v_cmd.organization_id and workflow_id=v_cmd.workflow_id for update;
  else
    select aggregate into v_workflow from public.erp_purchase_workflows
      where organization_id=v_cmd.organization_id and workflow_id=v_cmd.workflow_id for update;
  end if;
  if v_workflow is null then raise exception 'cloud_workflow_not_found'; end if;

  v_invoice := v_workflow->'invoice';
  if v_invoice is null or v_invoice->>'id' is distinct from p_invoice_id then raise exception 'invoice_not_found'; end if;
  if v_invoice->>'status' <> 'approved' then raise exception 'invoice_not_approved'; end if;

  v_partner_id := case when v_cmd.module='sales'
    then coalesce(v_invoice->>'customerId', v_workflow#>>'{order,customerId}')
    else coalesce(v_invoice->>'supplierId', v_workflow#>>'{order,supplierId}') end;

  select case when v_plan.invoice_currency='USD' then usd_account_id else iqd_account_id end
    into v_partner_account_id
  from public.erp_partner_accounts
  where organization_id=v_cmd.organization_id
    and partner_type=case when v_cmd.module='sales' then 'customer' else 'supplier' end
    and partner_id=v_partner_id and is_active;
  if v_partner_account_id is null then raise exception 'partner_account_missing'; end if;

  v_cash_account_id := v_plan.journal_plan->0->>'accountId';
  if v_cmd.module='purchases' then
    select value->>'accountId' into v_cash_account_id
      from jsonb_array_elements(v_plan.journal_plan)
      where value->>'role'='cash' limit 1;
  end if;
  if v_cash_account_id is null then raise exception 'cash_account_missing'; end if;
  if not exists(select 1 from public.erp_accounts where organization_id=v_cmd.organization_id and account_id=v_cash_account_id and is_active) then
    raise exception 'cash_account_missing';
  end if;

  insert into public.erp_financial_events(
    organization_id,module,workflow_id,event_type,idempotency_key,payload,created_by
  ) values (
    v_cmd.organization_id,v_cmd.module,v_cmd.workflow_id,v_cmd.event_type,v_cmd.idempotency_key,
    jsonb_build_object('invoiceId',p_invoice_id,'planId',v_plan.id,'cashAmount',v_plan.cash_amount,
      'appliedInvoiceAmount',v_plan.applied_invoice_amount,'exchangeDifference',v_plan.exchange_difference),
    auth.uid()
  ) returning id into v_event_id;

  v_entry_number := case when v_cmd.module='sales' then 'CLD-RCV-' else 'CLD-PAY-' end || upper(substr(v_cmd.id::text,1,8));
  v_description := case when v_cmd.module='sales' then 'قبض دفعة فاتورة بيع سحابي' else 'صرف دفعة فاتورة شراء سحابي' end;

  select coalesce(sum((value->>'debit')::numeric),0), coalesce(sum((value->>'credit')::numeric),0)
    into v_total_debit,v_total_credit
  from jsonb_array_elements(v_plan.journal_plan);
  if abs(v_total_debit-v_total_credit)>0.01 then raise exception 'unbalanced_cloud_journal'; end if;

  insert into public.erp_cloud_journal_entries(
    organization_id,financial_event_id,module,workflow_id,source_entry_id,entry_number,entry_date,
    description,currency,reference_type,reference_id,total_debit,total_credit,status,posted_by
  ) values (
    v_cmd.organization_id,v_event_id,v_cmd.module,v_cmd.workflow_id,'cloud-payment:'||v_cmd.id::text,
    v_entry_number,v_now,v_description,v_plan.invoice_currency,
    case when v_cmd.module='sales' then 'sales_invoice_payment' else 'purchase_invoice_payment' end,
    v_cmd.id::text,v_total_debit,v_total_credit,'posted',auth.uid()
  ) returning id into v_entry_id;

  for v_line in select value from jsonb_array_elements(v_plan.journal_plan) loop
    v_line_no := v_line_no + 1;
    if v_line->>'role' in ('receivable','payable') then
      select * into v_account from public.erp_accounts
       where organization_id=v_cmd.organization_id and account_id=v_partner_account_id;
    elsif v_line->>'role'='cash' then
      select * into v_account from public.erp_accounts
       where organization_id=v_cmd.organization_id and account_id=v_cash_account_id;
    elsif v_line->>'role'='fx_loss' then
      select * into v_account from public.erp_accounts
       where organization_id=v_cmd.organization_id and code='7190-'||v_plan.invoice_currency and is_active;
    elsif v_line->>'role'='fx_gain' then
      select * into v_account from public.erp_accounts
       where organization_id=v_cmd.organization_id and code='4190-'||v_plan.invoice_currency and is_active;
    else
      raise exception 'unsupported_payment_journal_role';
    end if;
    if v_account.account_id is null then raise exception 'payment_journal_account_missing:%',v_line->>'role'; end if;

    insert into public.erp_cloud_journal_lines(
      organization_id,entry_id,source_line_id,line_number,account_id,account_code,account_name,
      debit,credit,description
    ) values (
      v_cmd.organization_id,v_entry_id,v_cmd.id::text||':'||v_line_no,v_line_no,
      v_account.account_id,v_account.code,v_account.name,
      coalesce((v_line->>'debit')::numeric,0),coalesce((v_line->>'credit')::numeric,0),
      case v_line->>'role'
        when 'cash' then 'الصندوق'
        when 'receivable' then 'تسديد ذمة العميل'
        when 'payable' then 'تسديد ذمة المجهز'
        when 'fx_loss' then 'خسارة فرق صرف'
        when 'fx_gain' then 'ربح فرق صرف'
      end
    );
  end loop;

  v_paid := coalesce(nullif(v_invoice->>'paidAmount','')::numeric,0)+v_plan.applied_invoice_amount;
  v_invoice := jsonb_set(v_invoice,'{paidAmount}',to_jsonb(v_paid),true);
  v_invoice := jsonb_set(v_invoice,'{remainingAmount}',to_jsonb(v_plan.next_remaining),true);
  v_invoice := jsonb_set(v_invoice,'{paymentStatus}',to_jsonb(v_plan.next_payment_status),true);
  v_workflow := jsonb_set(v_workflow,'{invoice}',v_invoice,true);
  v_workflow := v_workflow || jsonb_build_object('lastFinancialEvent',jsonb_build_object(
    'eventType','invoice_payment_posted','invoiceId',p_invoice_id,'paymentId',v_cmd.id,
    'journalEntryId',v_entry_id,'remainingAmount',v_plan.next_remaining));

  if v_cmd.module='sales' then
    update public.erp_sales_workflows set aggregate=v_workflow,version=version+1,updated_at=v_now,updated_by=auth.uid()
      where organization_id=v_cmd.organization_id and workflow_id=v_cmd.workflow_id returning version into v_version;
  else
    update public.erp_purchase_workflows set aggregate=v_workflow,version=version+1,updated_at=v_now,updated_by=auth.uid()
      where organization_id=v_cmd.organization_id and workflow_id=v_cmd.workflow_id returning version into v_version;
  end if;

  v_result := jsonb_build_object(
    'commandId',v_cmd.id,'status','committed','duplicate',false,'journalEntryId',v_entry_id,
    'entryNumber',v_entry_number,'appliedInvoiceAmount',v_plan.applied_invoice_amount,
    'exchangeDifference',v_plan.exchange_difference,'nextRemaining',v_plan.next_remaining,
    'paymentStatus',v_plan.next_payment_status,'version',v_version
  );
  update public.erp_financial_commands set status='committed',result_payload=v_result,committed_at=v_now,error_message=null
    where id=v_cmd.id;
  return v_result;
exception
  when unique_violation then
    select result_payload into v_result from public.erp_financial_commands where id=p_command_id;
    return coalesce(v_result,jsonb_build_object('commandId',p_command_id,'status','committed','duplicate',true));
end;
$$;

grant execute on function public.erp_post_payment_cloud(uuid,text) to authenticated;
