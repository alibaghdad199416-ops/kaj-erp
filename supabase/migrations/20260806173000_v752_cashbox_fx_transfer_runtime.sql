-- Quality Line ERP 18.9.22 / V7.5.2
-- Complete linked cashbox FX transfer runtime. Removes dependency on the
-- historical missing FX-account helper and posts balanced
-- journals independently in each currency.
begin;

create or replace function public.erp_transfer_cloud_cash_v3(
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
  voucher text;
  available numeric;
  tolerance numeric;
  linked text;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['cashbox.transfer','accounting.update']);

  if p_from_cash_account_id is null or p_to_cash_account_id is null
     or p_from_cash_account_id=p_to_cash_account_id
     or coalesce(p_source_amount,0)<=0 or coalesce(p_target_amount,0)<=0
     or coalesce(p_exchange_rate,0)<=0 then
    raise exception 'invalid_cash_transfer';
  end if;

  select * into f from public.erp_cash_accounts
   where company_id=p_company_id and id=p_from_cash_account_id
     and not is_deleted for update;
  select * into t from public.erp_cash_accounts
   where company_id=p_company_id and id=p_to_cash_account_id
     and not is_deleted for update;
  if f.id is null or t.id is null then raise exception 'cashbox_not_found'; end if;
  if not public.erp_try_boolean(coalesce(f.data->>'isActive',f.data->>'is_active'),'true')
     or not public.erp_try_boolean(coalesce(t.data->>'isActive',t.data->>'is_active'),'true') then
    raise exception 'cashbox_inactive';
  end if;

  fc:=upper(coalesce(f.data->>'currency',''));
  tc:=upper(coalesce(t.data->>'currency',''));
  fl:=nullif(coalesce(f.data->>'account_id',f.data->>'accountId'),'');
  tl:=nullif(coalesce(t.data->>'account_id',t.data->>'accountId'),'');
  if fc not in ('IQD','USD') or tc not in ('IQD','USD') then
    raise exception 'cashbox_currency_invalid';
  end if;
  if fl is null or tl is null then raise exception 'cashbox_ledger_required'; end if;
  if not exists(select 1 from public.erp_accounts where organization_id=p_company_id and account_id=fl and is_active and upper(currency)=fc)
     or not exists(select 1 from public.erp_accounts where organization_id=p_company_id and account_id=tl and is_active and upper(currency)=tc) then
    raise exception 'cashbox_ledger_currency_mismatch';
  end if;

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
    if linked is distinct from p_to_cash_account_id then
      raise exception 'cashboxes_not_linked_for_fx';
    end if;

    source_clearing:='system-fx-clearing-'||lower(fc);
    target_clearing:='system-fx-clearing-'||lower(tc);
    insert into public.erp_accounts(
      organization_id,account_id,code,name,account_type,currency,
      opening_balance,is_active,source_updated_at,synced_at,synced_by)
    values
      (p_company_id,source_clearing,'FX'||substr(fc,1,1)||'001',
       'FX transfer clearing '||fc,'asset',fc,0,true,now(),now(),auth.uid()),
      (p_company_id,target_clearing,'FX'||substr(tc,1,1)||'001',
       'FX transfer clearing '||tc,'asset',tc,0,true,now(),now(),auth.uid())
    on conflict(organization_id,account_id) do update set
      currency=excluded.currency,is_active=true,synced_at=now(),synced_by=auth.uid();
  end if;

  select public.erp_try_numeric(coalesce(f.data->>'openingBalance',f.data->>'opening_balance'),0)
       + coalesce(sum(case when data->>'type'='receipt'
                    then public.erp_try_numeric(data->>'amount',0)
                    else -public.erp_try_numeric(data->>'amount',0) end),0)
    into available
    from public.erp_cash_transactions
   where company_id=p_company_id and not is_deleted
     and coalesce(data->>'cashAccountId',data->>'cash_account_id')=p_from_cash_account_id;
  if coalesce(available,0)<p_source_amount then
    raise exception 'source_cashbox_balance_insufficient';
  end if;

  voucher:=public.erp_next_document_number(p_company_id,'cash_transfer','CT',p_transfer_date);
  insert into public.erp_cash_transfers(company_id,id,data,created_by,updated_by)
  values(p_company_id,transfer_id,jsonb_build_object(
    'id',transfer_id,'transferNumber',voucher,
    'fromAccountId',p_from_cash_account_id,'toAccountId',p_to_cash_account_id,
    'sourceAmount',p_source_amount,'sourceCurrency',fc,
    'targetAmount',p_target_amount,'targetCurrency',tc,
    'exchangeRate',p_exchange_rate,'transferDate',p_transfer_date,
    'notes',p_notes,'status','posted','runtimeVersion','v3'),auth.uid(),auth.uid());

  insert into public.erp_cash_transactions(company_id,id,data,created_by,updated_by) values
  (p_company_id,tx_out,jsonb_build_object(
    'id',tx_out,'voucherNumber',voucher,'type','payment','category','cash_transfer',
    'amount',p_source_amount,'currency',fc,'transactionDate',p_transfer_date,
    'referenceType','cash_transfer','referenceId',transfer_id,
    'cashAccountId',p_from_cash_account_id,
    'counterAccountId',case when fc=tc then tl else source_clearing end,
    'journalEntryId',j_source,'notes',p_notes),auth.uid(),auth.uid()),
  (p_company_id,tx_in,jsonb_build_object(
    'id',tx_in,'voucherNumber',voucher,'type','receipt','category','cash_transfer',
    'amount',p_target_amount,'currency',tc,'transactionDate',p_transfer_date,
    'referenceType','cash_transfer','referenceId',transfer_id,
    'cashAccountId',p_to_cash_account_id,
    'counterAccountId',case when fc=tc then fl else target_clearing end,
    'journalEntryId',case when fc=tc then j_source else j_target end,
    'notes',p_notes),auth.uid(),auth.uid());

  insert into public.erp_journal_entries(company_id,id,data,created_by,updated_by)
  values(p_company_id,j_source,jsonb_build_object(
    'id',j_source,'entryNumber',voucher,'entryDate',p_transfer_date,
    'description','Cashbox transfer','currency',fc,
    'referenceType','cash_transfer','referenceId',transfer_id,
    'totalDebit',p_source_amount,'totalCredit',p_source_amount,
    'status','posted','createdAt',now()),auth.uid(),auth.uid());
  insert into public.erp_journal_lines(company_id,id,data,created_by,updated_by) values
  (p_company_id,gen_random_uuid()::text,jsonb_build_object(
    'entryId',j_source,'accountId',case when fc=tc then tl else source_clearing end,
    'currency',fc,'referenceType','cash_transfer','referenceId',transfer_id,
    'debit',p_source_amount,'credit',0,'description',coalesce(p_notes,'Cashbox transfer')),auth.uid(),auth.uid()),
  (p_company_id,gen_random_uuid()::text,jsonb_build_object(
    'entryId',j_source,'accountId',fl,'currency',fc,
    'referenceType','cash_transfer','referenceId',transfer_id,
    'debit',0,'credit',p_source_amount,'description',coalesce(p_notes,'Cashbox transfer')),auth.uid(),auth.uid());

  if fc<>tc then
    insert into public.erp_journal_entries(company_id,id,data,created_by,updated_by)
    values(p_company_id,j_target,jsonb_build_object(
      'id',j_target,'entryNumber',voucher||'R','entryDate',p_transfer_date,
      'description','FX cashbox transfer receipt','currency',tc,
      'referenceType','cash_transfer','referenceId',transfer_id,
      'totalDebit',p_target_amount,'totalCredit',p_target_amount,
      'status','posted','createdAt',now()),auth.uid(),auth.uid());
    insert into public.erp_journal_lines(company_id,id,data,created_by,updated_by) values
    (p_company_id,gen_random_uuid()::text,jsonb_build_object(
      'entryId',j_target,'accountId',tl,'currency',tc,
      'referenceType','cash_transfer','referenceId',transfer_id,
      'debit',p_target_amount,'credit',0,'description',coalesce(p_notes,'FX cashbox receipt')),auth.uid(),auth.uid()),
    (p_company_id,gen_random_uuid()::text,jsonb_build_object(
      'entryId',j_target,'accountId',target_clearing,'currency',tc,
      'referenceType','cash_transfer','referenceId',transfer_id,
      'debit',0,'credit',p_target_amount,'description',coalesce(p_notes,'FX cashbox receipt')),auth.uid(),auth.uid());
  end if;

  return jsonb_build_object(
    'ok',true,'transferId',transfer_id,'transferNumber',voucher,
    'fromCashAccountId',p_from_cash_account_id,'toCashAccountId',p_to_cash_account_id,
    'sourceAmount',p_source_amount,'targetAmount',p_target_amount,
    'exchangeRate',p_exchange_rate,'sourceJournalId',j_source,
    'targetJournalId',case when fc=tc then null else j_target end);
end;
$$;

revoke all on function public.erp_transfer_cloud_cash_v3(uuid,text,text,numeric,numeric,numeric,timestamptz,text) from public,anon;
grant execute on function public.erp_transfer_cloud_cash_v3(uuid,text,text,numeric,numeric,numeric,timestamptz,text) to authenticated,service_role;
notify pgrst,'reload schema';
commit;
