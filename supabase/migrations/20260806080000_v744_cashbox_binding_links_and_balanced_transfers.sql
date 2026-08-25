begin;

-- V7.4.4: persist cashbox ledger bindings, define reciprocal cross-currency
-- links, and post every transfer as balanced journal-backed cash movements.
create table if not exists public.erp_cash_account_links(
  company_id uuid not null references public.companies(id) on delete cascade,
  source_cash_account_id text not null,
  target_cash_account_id text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  updated_by uuid,
  primary key(company_id,source_cash_account_id),
  check(source_cash_account_id<>target_cash_account_id)
);
alter table public.erp_cash_account_links enable row level security;
drop policy if exists erp_cash_account_links_member on public.erp_cash_account_links;
create policy erp_cash_account_links_member on public.erp_cash_account_links
for all to authenticated using(public.is_active_company_member(company_id))
with check(public.is_active_company_member(company_id));

create or replace function public.erp_save_cloud_cash_account(
  p_company_id uuid,p_account jsonb
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_id text:=btrim(coalesce(p_account->>'id',''));
  v_name text:=btrim(coalesce(p_account->>'name',''));
  v_ledger text:=btrim(coalesce(p_account->>'account_id',p_account->>'accountId',''));
  v_currency text:=upper(coalesce(nullif(btrim(p_account->>'currency'),''),'USD'));
  v_linked text:=nullif(btrim(coalesce(p_account->>'linked_cash_account_id',p_account->>'linkedCashAccountId','')),'');
  v_ledger_currency text; v_ledger_type text; v_link_currency text;
  v_active boolean:=public.erp_try_boolean(coalesce(p_account->>'is_active',p_account->>'isActive'),'true');
  v_opening numeric:=public.erp_try_numeric(coalesce(p_account->>'opening_balance',p_account->>'openingBalance'),0);
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  if v_id='' or v_name='' or v_ledger='' then raise exception 'cashbox_data_incomplete'; end if;
  if v_currency not in ('USD','IQD') or v_opening<0 then raise exception 'invalid_cashbox_currency_or_opening'; end if;
  select upper(currency),account_type into v_ledger_currency,v_ledger_type
  from public.erp_accounts where organization_id=p_company_id and account_id=v_ledger and is_active;
  if v_ledger_currency is null or v_ledger_type<>'asset' or v_ledger_currency not in (v_currency,'MULTI') then
    raise exception 'invalid_cashbox_ledger_binding';
  end if;
  if exists(select 1 from public.erp_cash_accounts ca where ca.company_id=p_company_id and ca.id<>v_id
    and not ca.is_deleted and public.erp_try_boolean(coalesce(ca.data->>'isActive',ca.data->>'is_active'),'true')
    and coalesce(ca.data->>'accountId',ca.data->>'account_id')=v_ledger) then
    raise exception 'ledger_already_linked_to_active_cashbox';
  end if;
  if v_linked is not null then
    select upper(coalesce(data->>'currency','')) into v_link_currency from public.erp_cash_accounts
    where company_id=p_company_id and id=v_linked and not is_deleted
      and public.erp_try_boolean(coalesce(data->>'isActive',data->>'is_active'),'true');
    if v_link_currency is null or v_link_currency=v_currency then raise exception 'linked_cashbox_must_use_other_currency'; end if;
  end if;
  insert into public.erp_cash_accounts(company_id,id,data,created_by,updated_by)
  values(p_company_id,v_id,jsonb_build_object(
    'id',v_id,'name',v_name,'type',coalesce(nullif(p_account->>'type',''),'cash'),
    'currency',v_currency,'openingBalance',v_opening,'opening_balance',v_opening,
    'isActive',v_active,'is_active',v_active,'accountId',v_ledger,'account_id',v_ledger,
    'linkedCashAccountId',v_linked,'linked_cash_account_id',v_linked,
    'createdAt',coalesce(p_account->'created_at',p_account->'createdAt',to_jsonb(now())),
    'updatedAt',to_jsonb(now()),'schemaVersion',3),auth.uid(),auth.uid())
  on conflict(company_id,id) do update set data=excluded.data,is_deleted=false,deleted_at=null,
    updated_at=now(),updated_by=auth.uid();
  delete from public.erp_cash_account_links where company_id=p_company_id and source_cash_account_id=v_id;
  if v_linked is not null then
    insert into public.erp_cash_account_links(company_id,source_cash_account_id,target_cash_account_id,created_by,updated_by)
    values(p_company_id,v_id,v_linked,auth.uid(),auth.uid())
    on conflict(company_id,source_cash_account_id) do update set target_cash_account_id=excluded.target_cash_account_id,
      updated_at=now(),updated_by=auth.uid();
  end if;
end $$;

create or replace function public.erp_resolve_linked_cash_account(p_company_id uuid,p_source_cash_account_id text,p_target_currency text)
returns text language sql security definer set search_path=public stable as $$
  select l.target_cash_account_id from public.erp_cash_account_links l
  join public.erp_cash_accounts ca on ca.company_id=l.company_id and ca.id=l.target_cash_account_id and not ca.is_deleted
  where l.company_id=p_company_id and l.source_cash_account_id=p_source_cash_account_id
    and upper(coalesce(ca.data->>'currency',''))=upper(p_target_currency)
    and public.erp_try_boolean(coalesce(ca.data->>'isActive',ca.data->>'is_active'),'true') limit 1
$$;

-- Restore balanced journal posting. Same-currency transfer is direct; cross-
-- currency transfer uses a neutral MULTI clearing account, never a difference
-- or gain/loss account. Each cash subledger movement has its own balanced entry.
create or replace function public.erp_transfer_cloud_cash(
  p_company_id uuid,p_from_cash_account_id text,p_to_cash_account_id text,
  p_source_amount numeric,p_target_amount numeric,p_exchange_rate numeric,
  p_transfer_date timestamptz,p_notes text default null
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_from public.erp_cash_accounts%rowtype; v_to public.erp_cash_accounts%rowtype;
  v_from_currency text; v_to_currency text; v_from_ledger text; v_to_ledger text;
  v_counter_from text; v_counter_to text; v_clearing text:='system-fx-clearing';
  v_transfer text:=gen_random_uuid()::text; v_number text; v_balance numeric;
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['cashbox.transfer','accounting.update']);
  if p_from_cash_account_id=p_to_cash_account_id or p_source_amount<=0 or p_target_amount<=0 or p_exchange_rate<=0 then raise exception 'invalid_cash_transfer'; end if;
  select * into v_from from public.erp_cash_accounts where company_id=p_company_id and id=p_from_cash_account_id and not is_deleted for update;
  select * into v_to from public.erp_cash_accounts where company_id=p_company_id and id=p_to_cash_account_id and not is_deleted for update;
  if v_from.id is null or v_to.id is null then raise exception 'cashbox_not_found'; end if;
  v_from_currency:=upper(coalesce(v_from.data->>'currency','')); v_to_currency:=upper(coalesce(v_to.data->>'currency',''));
  v_from_ledger:=coalesce(v_from.data->>'accountId',v_from.data->>'account_id'); v_to_ledger:=coalesce(v_to.data->>'accountId',v_to.data->>'account_id');
  if v_from_ledger is null or v_to_ledger is null then raise exception 'cashbox_ledger_required'; end if;
  if v_from_currency=v_to_currency then
    if abs(p_exchange_rate-1)>0.000001 or abs(p_source_amount-p_target_amount)>0.01 then raise exception 'same_currency_transfer_requires_rate_one'; end if;
    v_counter_from:=v_to_ledger; v_counter_to:=v_from_ledger;
  else
    if abs(p_target_amount-p_source_amount*p_exchange_rate)>greatest(0.01,abs(p_target_amount)*0.000001) then raise exception 'cash_transfer_amount_rate_mismatch'; end if;
    insert into public.erp_accounts(organization_id,account_id,code,name,account_type,currency,opening_balance,is_active,source_updated_at,synced_at,synced_by)
    values(p_company_id,v_clearing,'FXCLR','FX cash transfer clearing / تسوية تحويل الصناديق','asset','MULTI',0,true,now(),now(),auth.uid())
    on conflict(organization_id,account_id) do update set is_active=true,synced_at=now(),synced_by=auth.uid();
    v_counter_from:=v_clearing; v_counter_to:=v_clearing;
  end if;
  select public.erp_try_numeric(coalesce(v_from.data->>'openingBalance',v_from.data->>'opening_balance'),0)+coalesce(sum(case when data->>'type'='receipt' then public.erp_try_numeric(data->>'amount',0) else -public.erp_try_numeric(data->>'amount',0) end),0)
  into v_balance from public.erp_cash_transactions where company_id=p_company_id and not is_deleted and data->>'cashAccountId'=p_from_cash_account_id;
  if v_balance<p_source_amount then raise exception 'source_cashbox_balance_insufficient'; end if;
  v_number:=public.erp_next_document_number(p_company_id,'cash_transfer','CT',p_transfer_date);
  insert into public.erp_cash_transfers(company_id,id,data,created_by,updated_by) values(p_company_id,v_transfer,jsonb_build_object(
    'id',v_transfer,'transferNumber',v_number,'fromAccountId',p_from_cash_account_id,'toAccountId',p_to_cash_account_id,
    'sourceAmount',p_source_amount,'sourceCurrency',v_from_currency,'targetAmount',p_target_amount,'targetCurrency',v_to_currency,
    'exchangeRate',p_exchange_rate,'transferDate',p_transfer_date,'notes',p_notes,'journalMode','balanced_cash_transfer'),auth.uid(),auth.uid());
  perform public.erp_post_cloud_cash_transaction(p_company_id,jsonb_build_object('id',gen_random_uuid()::text,'voucherNumber',v_number,'type','payment','category','cash_transfer','amount',p_source_amount,'currency',v_from_currency,'transactionDate',p_transfer_date,'referenceType','cash_transfer','referenceId',v_transfer,'cashAccountId',p_from_cash_account_id,'counterAccountId',v_counter_from,'notes',p_notes),false);
  perform public.erp_post_cloud_cash_transaction(p_company_id,jsonb_build_object('id',gen_random_uuid()::text,'voucherNumber',v_number,'type','receipt','category','cash_transfer','amount',p_target_amount,'currency',v_to_currency,'transactionDate',p_transfer_date,'referenceType','cash_transfer','referenceId',v_transfer,'cashAccountId',p_to_cash_account_id,'counterAccountId',v_counter_to,'notes',p_notes),false);
end $$;

create or replace function public.erp_apply_cloud_workflow_invoice_payment_batch(
  p_company_id uuid,p_invoice_id uuid,p_module text,p_payments jsonb
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  d public.erp_commercial_workflow_documents%rowtype;
  p jsonb; v_invoice_currency text; v_payment_currency text;
  v_cash_id text; v_linked_cash_id text; v_cash_currency text; v_linked_currency text;
  v_amount numeric; v_cash_amount numeric; v_rate numeric; v_expected numeric;
  v_remaining numeric; v_paid numeric; v_payment_id text; v_tx_id text;
  v_bridge_in text; v_bridge_out text; v_voucher text; v_date timestamptz;
  v_results jsonb:='[]'::jsonb; v_payments jsonb;
begin
  if p_module not in ('sales','purchases') then raise exception 'invalid_workflow_module'; end if;
  perform public.erp_require_any_cloud_permission(
    p_company_id,case when p_module='sales' then array['cashbox.receipt'] else array['cashbox.payment'] end);
  if p_payments is null or jsonb_typeof(p_payments)<>'array' or jsonb_array_length(p_payments)=0 then
    raise exception 'payment_batch_required';
  end if;
  select * into d from public.erp_commercial_workflow_documents
  where company_id=p_company_id and id=p_invoice_id and module=p_module
    and document_type='invoice' and status='approved' and not is_deleted for update;
  if not found then raise exception 'approved_invoice_required'; end if;
  v_invoice_currency:=upper(coalesce(d.payload->>'currency',''));
  v_paid:=public.erp_try_numeric(d.payload->>'paidAmount',0);
  v_remaining:=public.erp_try_numeric(d.payload->>'remainingAmount',
    public.erp_try_numeric(d.payload->>'totalAmount',0)-v_paid);
  v_payments:=coalesce(d.payload->'payments','[]'::jsonb);

  for p in select value from jsonb_array_elements(p_payments) loop
    v_cash_id:=nullif(btrim(p->>'cashAccountId'),'');
    v_linked_cash_id:=nullif(btrim(p->>'linkedCashAccountId'),'');
    if v_linked_cash_id is null then
      v_linked_cash_id:=public.erp_resolve_linked_cash_account(p_company_id,v_cash_id,v_invoice_currency);
    end if;
    v_payment_currency:=upper(coalesce(p->>'paymentCurrency',''));
    v_amount:=public.erp_try_numeric(p->>'invoiceAmount',0);
    v_cash_amount:=public.erp_try_numeric(p->>'cashAmount',0);
    v_rate:=public.erp_try_numeric(p->>'exchangeRate',0);
    v_date:=public.erp_try_timestamptz(p->>'paymentDate',now());
    if v_cash_id is null or v_amount<=0 or v_cash_amount<=0 or v_rate<=0 or v_amount>v_remaining+0.01 then
      raise exception 'invalid_or_excessive_invoice_payment';
    end if;
    select upper(coalesce(ca.data->>'currency','')) into v_cash_currency
    from public.erp_cash_accounts ca where ca.company_id=p_company_id and ca.id=v_cash_id
      and not ca.is_deleted and public.erp_try_boolean(ca.data->>'isActive',true) for share;
    if not found or v_cash_currency<>v_payment_currency then raise exception 'payment_cashbox_currency_mismatch'; end if;
    if v_payment_currency=v_invoice_currency then
      if abs(v_rate-1)>0.000001 or abs(v_cash_amount-v_amount)>0.01 then
        raise exception 'same_currency_payment_requires_rate_one';
      end if;
      v_linked_cash_id:=v_cash_id;
    else
      if v_linked_cash_id is null or v_linked_cash_id=v_cash_id then raise exception 'linked_invoice_currency_cashbox_required'; end if;
      select upper(coalesce(ca.data->>'currency','')) into v_linked_currency
      from public.erp_cash_accounts ca where ca.company_id=p_company_id and ca.id=v_linked_cash_id
        and not ca.is_deleted and public.erp_try_boolean(ca.data->>'isActive',true) for share;
      if not found or v_linked_currency<>v_invoice_currency then raise exception 'linked_cashbox_must_use_invoice_currency'; end if;
      v_expected:=case
        when v_invoice_currency='USD' and v_payment_currency='IQD' then v_amount*v_rate
        when v_invoice_currency='IQD' and v_payment_currency='USD' then v_amount/v_rate
        else null end;
      if v_expected is null or abs(v_cash_amount-v_expected)>greatest(0.01,abs(v_expected)*0.005) then
        raise exception 'cash_amount_exchange_rate_mismatch';
      end if;
    end if;

    v_payment_id:=gen_random_uuid()::text; v_tx_id:=gen_random_uuid()::text;
    v_voucher:=public.erp_next_document_number(p_company_id,
      case when p_module='sales' then 'customer_payment' else 'supplier_payment' end,
      case when p_module='sales' then 'RC' else 'PY' end,v_date);
    insert into public.erp_cash_transactions(company_id,id,data,created_by,updated_by)
    values(p_company_id,v_tx_id,jsonb_build_object(
      'id',v_tx_id,'cashAccountId',v_cash_id,'voucherNumber',v_voucher,
      'type',case when p_module='sales' then 'receipt' else 'payment' end,
      'category',case when p_module='sales' then 'customer_payment' else 'supplier_payment' end,
      'amount',v_cash_amount,'currency',v_payment_currency,'exchangeRate',v_rate,
      'invoiceAmount',v_amount,'invoiceCurrency',v_invoice_currency,'transactionDate',v_date,
      'referenceType','workflow_invoice_payment','referenceId',v_payment_id,
      'invoiceId',p_invoice_id::text,'orderId',d.parent_id::text,'module',p_module,
      'invoiceNumber',d.document_number,'linkedCashAccountId',v_linked_cash_id,
      'notes',nullif(btrim(p->>'notes'),''),'automaticJournalPosting',true),auth.uid(),auth.uid());

    if v_payment_currency<>v_invoice_currency then
      v_bridge_in:=gen_random_uuid()::text; v_bridge_out:=gen_random_uuid()::text;
      insert into public.erp_cash_transactions(company_id,id,data,created_by,updated_by) values
      (p_company_id,v_bridge_in,jsonb_build_object(
        'id',v_bridge_in,'cashAccountId',v_linked_cash_id,'voucherNumber',v_voucher,
        'type','receipt','category','linked_fx_conversion','amount',v_amount,
        'currency',v_invoice_currency,'exchangeRate',v_rate,'transactionDate',v_date,
        'referenceType','workflow_invoice_payment_fx','referenceId',v_payment_id,
        'sourceCashAccountId',v_cash_id,'invoiceId',p_invoice_id::text,'orderId',d.parent_id::text),auth.uid(),auth.uid()),
      (p_company_id,v_bridge_out,jsonb_build_object(
        'id',v_bridge_out,'cashAccountId',v_linked_cash_id,'voucherNumber',v_voucher,
        'type','payment','category','invoice_settlement','amount',v_amount,
        'currency',v_invoice_currency,'exchangeRate',1,'transactionDate',v_date,
        'referenceType','workflow_invoice_payment_fx','referenceId',v_payment_id,
        'invoiceId',p_invoice_id::text,'orderId',d.parent_id::text),auth.uid(),auth.uid());
    end if;

    v_paid:=v_paid+v_amount; v_remaining:=greatest(0,v_remaining-v_amount);
    v_payments:=v_payments||jsonb_build_array(jsonb_build_object(
      'paymentId',v_payment_id,'cashTransactionId',v_tx_id,'voucherNumber',v_voucher,
      'cashAccountId',v_cash_id,'linkedCashAccountId',v_linked_cash_id,
      'paymentCurrency',v_payment_currency,'invoiceCurrency',v_invoice_currency,
      'invoiceAmount',v_amount,'cashAmount',v_cash_amount,'exchangeRate',v_rate,
      'paymentDate',v_date,'notes',nullif(btrim(p->>'notes'),''),'automaticJournalPosting',true));
    v_results:=v_results||jsonb_build_array(v_payments->-1);
  end loop;
  update public.erp_commercial_workflow_documents set payload=payload||jsonb_build_object(
    'payments',v_payments,'paidAmount',v_paid,'remainingAmount',v_remaining,
    'paymentStatus',case when v_remaining<=0.001 then 'paid' when v_paid>0 then 'partial' else 'unpaid' end)
  ,updated_at=now(),updated_by=auth.uid() where company_id=p_company_id and id=p_invoice_id;
  return v_results;
end;
$$;


grant select,insert,update,delete on public.erp_cash_account_links to authenticated;
grant execute on function public.erp_save_cloud_cash_account(uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_resolve_linked_cash_account(uuid,text,text) to authenticated,service_role;
grant execute on function public.erp_transfer_cloud_cash(uuid,text,text,numeric,numeric,numeric,timestamptz,text) to authenticated,service_role;

commit;
