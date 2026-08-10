-- Quality Line ERP v17.8.0
-- Cloud-first invoice approval using normalized accounting master data.

create or replace function public.erp_approve_invoice_cloud(
  p_command_id uuid,
  p_invoice_id text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cmd public.erp_financial_commands%rowtype;
  v_workflow jsonb;
  v_invoice jsonb;
  v_items jsonb;
  v_item jsonb;
  v_currency text;
  v_partner_id text;
  v_partner_type text;
  v_total numeric(20,4);
  v_cogs numeric(20,4) := 0;
  v_quantity numeric(20,4);
  v_unit_cost numeric(20,4);
  v_receivable_or_payable text;
  v_revenue text;
  v_inventory text;
  v_cogs_account text;
  v_entry_id uuid;
  v_event_id uuid;
  v_version bigint;
  v_result jsonb;
  v_now timestamptz := now();
  v_entry_number text;
  v_description text;
  v_line_no integer := 0;
  v_account public.erp_accounts%rowtype;
begin
  select * into v_cmd
  from public.erp_financial_commands
  where id = p_command_id
  for update;

  if not found then raise exception 'financial_command_not_found'; end if;
  if not public.is_active_company_member(v_cmd.organization_id) then
    raise exception 'permission_denied';
  end if;
  if v_cmd.event_type <> 'invoice_approved' then
    raise exception 'invalid_financial_command_type';
  end if;

  if v_cmd.status = 'committed' then
    return coalesce(v_cmd.result_payload,
      jsonb_build_object('commandId', v_cmd.id, 'status', 'committed', 'duplicate', true));
  end if;
  if v_cmd.status = 'aborted' then raise exception 'financial_command_aborted'; end if;

  if v_cmd.module = 'sales' then
    select aggregate, version into v_workflow, v_version
    from public.erp_sales_workflows
    where organization_id = v_cmd.organization_id
      and workflow_id = v_cmd.workflow_id
    for update;
  else
    select aggregate, version into v_workflow, v_version
    from public.erp_purchase_workflows
    where organization_id = v_cmd.organization_id
      and workflow_id = v_cmd.workflow_id
    for update;
  end if;

  if v_workflow is null then raise exception 'workflow_not_found'; end if;
  if v_cmd.expected_version is not null and v_version <> v_cmd.expected_version then
    raise exception 'record_conflict';
  end if;

  v_invoice := v_workflow -> 'invoice';
  v_items := coalesce(v_workflow -> 'items', '[]'::jsonb);
  if v_invoice is null then raise exception 'invoice_snapshot_missing'; end if;
  if coalesce(v_invoice->>'id','') <> p_invoice_id then raise exception 'invoice_mismatch'; end if;
  if coalesce(v_invoice->>'status','') <> 'draft' then raise exception 'invoice_not_draft'; end if;

  v_currency := coalesce(v_invoice->>'currency','USD');
  v_total := coalesce((v_invoice->>'total')::numeric, 0);
  if v_total <= 0 then raise exception 'invalid_invoice_total'; end if;

  if v_cmd.module = 'sales' then
    v_partner_type := 'customer';
    v_partner_id := v_invoice->>'customerId';
    select case when v_currency = 'IQD' then iqd_account_id else usd_account_id end
      into v_receivable_or_payable
    from public.erp_partner_accounts
    where organization_id = v_cmd.organization_id
      and partner_type = 'customer'
      and partner_id = v_partner_id
      and is_active;

    select account_id into v_revenue from public.erp_accounts
      where organization_id = v_cmd.organization_id and code = '4100-' || v_currency and is_active;
    select account_id into v_inventory from public.erp_accounts
      where organization_id = v_cmd.organization_id and code = '1300-' || v_currency and is_active;
    select account_id into v_cogs_account from public.erp_accounts
      where organization_id = v_cmd.organization_id and code = '5100-' || v_currency and is_active;

    for v_item in select value from jsonb_array_elements(v_items) loop
      v_quantity := coalesce((v_item->>'quantity')::numeric, 0);
      select unit_cost into v_unit_cost
      from public.erp_item_costs
      where organization_id = v_cmd.organization_id
        and item_type = v_item->>'itemType'
        and item_id = v_item->>'itemId'
        and is_active;
      if v_unit_cost is null then raise exception 'item_cost_missing:%', v_item->>'itemId'; end if;
      v_cogs := v_cogs + (v_unit_cost * v_quantity);
    end loop;
  else
    v_partner_type := 'supplier';
    v_partner_id := v_invoice->>'supplierId';
    select case when v_currency = 'IQD' then iqd_account_id else usd_account_id end
      into v_receivable_or_payable
    from public.erp_partner_accounts
    where organization_id = v_cmd.organization_id
      and partner_type = 'supplier'
      and partner_id = v_partner_id
      and is_active;

    select account_id into v_inventory from public.erp_accounts
      where organization_id = v_cmd.organization_id and code = '1300-' || v_currency and is_active;
  end if;

  if v_receivable_or_payable is null then raise exception 'partner_account_missing'; end if;
  if v_inventory is null then raise exception 'inventory_account_missing'; end if;
  if v_cmd.module = 'sales' and v_revenue is null then raise exception 'revenue_account_missing'; end if;
  if v_cmd.module = 'sales' and v_cogs > 0 and v_cogs_account is null then raise exception 'cogs_account_missing'; end if;

  insert into public.erp_financial_events(
    organization_id,module,workflow_id,event_type,idempotency_key,payload,created_by
  ) values (
    v_cmd.organization_id,v_cmd.module,v_cmd.workflow_id,v_cmd.event_type,
    v_cmd.idempotency_key,
    jsonb_build_object('invoiceId', p_invoice_id, 'total', v_total, 'currency', v_currency, 'cogs', v_cogs),
    auth.uid()
  ) returning id into v_event_id;

  v_entry_number := case when v_cmd.module = 'sales' then 'CLD-SINV-' else 'CLD-PINV-' end || upper(substr(v_cmd.id::text,1,8));
  v_description := case when v_cmd.module = 'sales' then 'اعتماد فاتورة بيع سحابي' else 'اعتماد فاتورة شراء سحابي' end;

  insert into public.erp_cloud_journal_entries(
    organization_id, financial_event_id, module, workflow_id, source_entry_id,
    entry_number, entry_date, description, currency, reference_type, reference_id,
    total_debit, total_credit, status, posted_by
  ) values (
    v_cmd.organization_id, v_event_id, v_cmd.module, v_cmd.workflow_id,
    'cloud-invoice:' || v_cmd.id::text, v_entry_number, v_now, v_description,
    v_currency, case when v_cmd.module='sales' then 'sales_invoice_v2' else 'purchase_invoice_v2' end,
    p_invoice_id,
    v_total + case when v_cmd.module='sales' then v_cogs else 0 end,
    v_total + case when v_cmd.module='sales' then v_cogs else 0 end,
    'posted', auth.uid()
  ) returning id into v_entry_id;

  if v_cmd.module = 'sales' then
    select * into v_account from public.erp_accounts where organization_id=v_cmd.organization_id and account_id=v_receivable_or_payable;
    v_line_no := v_line_no + 1;
    insert into public.erp_cloud_journal_lines(organization_id,entry_id,source_line_id,line_number,account_id,account_code,account_name,debit,credit,description)
    values(v_cmd.organization_id,v_entry_id,v_cmd.id::text||':1',v_line_no,v_account.account_id,v_account.code,v_account.name,v_total,0,'ذمة العميل');

    select * into v_account from public.erp_accounts where organization_id=v_cmd.organization_id and account_id=v_revenue;
    v_line_no := v_line_no + 1;
    insert into public.erp_cloud_journal_lines(organization_id,entry_id,source_line_id,line_number,account_id,account_code,account_name,debit,credit,description)
    values(v_cmd.organization_id,v_entry_id,v_cmd.id::text||':2',v_line_no,v_account.account_id,v_account.code,v_account.name,0,v_total,'إيراد البيع');

    if v_cogs > 0 then
      select * into v_account from public.erp_accounts where organization_id=v_cmd.organization_id and account_id=v_cogs_account;
      v_line_no := v_line_no + 1;
      insert into public.erp_cloud_journal_lines(organization_id,entry_id,source_line_id,line_number,account_id,account_code,account_name,debit,credit,description)
      values(v_cmd.organization_id,v_entry_id,v_cmd.id::text||':3',v_line_no,v_account.account_id,v_account.code,v_account.name,v_cogs,0,'تكلفة البضاعة المباعة');

      select * into v_account from public.erp_accounts where organization_id=v_cmd.organization_id and account_id=v_inventory;
      v_line_no := v_line_no + 1;
      insert into public.erp_cloud_journal_lines(organization_id,entry_id,source_line_id,line_number,account_id,account_code,account_name,debit,credit,description)
      values(v_cmd.organization_id,v_entry_id,v_cmd.id::text||':4',v_line_no,v_account.account_id,v_account.code,v_account.name,0,v_cogs,'تخفيض المخزون');
    end if;
  else
    select * into v_account from public.erp_accounts where organization_id=v_cmd.organization_id and account_id=v_inventory;
    v_line_no := v_line_no + 1;
    insert into public.erp_cloud_journal_lines(organization_id,entry_id,source_line_id,line_number,account_id,account_code,account_name,debit,credit,description)
    values(v_cmd.organization_id,v_entry_id,v_cmd.id::text||':1',v_line_no,v_account.account_id,v_account.code,v_account.name,v_total,0,'إثبات المخزون');

    select * into v_account from public.erp_accounts where organization_id=v_cmd.organization_id and account_id=v_receivable_or_payable;
    v_line_no := v_line_no + 1;
    insert into public.erp_cloud_journal_lines(organization_id,entry_id,source_line_id,line_number,account_id,account_code,account_name,debit,credit,description)
    values(v_cmd.organization_id,v_entry_id,v_cmd.id::text||':2',v_line_no,v_account.account_id,v_account.code,v_account.name,0,v_total,'ذمة المجهز');
  end if;

  v_invoice := jsonb_set(v_invoice, '{status}', '"approved"'::jsonb, true);
  v_invoice := jsonb_set(v_invoice, '{journalEntryId}', to_jsonb(v_entry_id::text), true);
  v_invoice := jsonb_set(v_invoice, '{approvedAt}', to_jsonb(v_now::text), true);
  v_workflow := jsonb_set(v_workflow, '{invoice}', v_invoice, true);
  v_workflow := v_workflow || jsonb_build_object('lastFinancialEvent', jsonb_build_object(
    'eventType','invoice_approved','invoiceId',p_invoice_id,'journalEntryId',v_entry_id,'total',v_total,'cogs',v_cogs));

  if v_cmd.module = 'sales' then
    update public.erp_sales_workflows set aggregate=v_workflow,version=version+1,updated_at=v_now,updated_by=auth.uid()
      where organization_id=v_cmd.organization_id and workflow_id=v_cmd.workflow_id returning version into v_version;
  else
    update public.erp_purchase_workflows set aggregate=v_workflow,version=version+1,updated_at=v_now,updated_by=auth.uid()
      where organization_id=v_cmd.organization_id and workflow_id=v_cmd.workflow_id returning version into v_version;
  end if;

  v_result := jsonb_build_object(
    'commandId',v_cmd.id,'status','committed','duplicate',false,
    'journalEntryId',v_entry_id,'entryNumber',v_entry_number,
    'total',v_total,'costOfGoodsSold',v_cogs,'version',v_version
  );

  update public.erp_financial_commands
    set status='committed',result_payload=v_result,committed_at=v_now,error_message=null
    where id=v_cmd.id;

  return v_result;
exception
  when unique_violation then
    select result_payload into v_result from public.erp_financial_commands where id=p_command_id;
    return coalesce(v_result, jsonb_build_object('commandId',p_command_id,'status','committed','duplicate',true));
end;
$$;

grant execute on function public.erp_approve_invoice_cloud(uuid,text) to authenticated;
