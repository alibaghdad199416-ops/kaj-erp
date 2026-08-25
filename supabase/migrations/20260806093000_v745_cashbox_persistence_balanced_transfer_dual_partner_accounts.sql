begin;

-- V7.4.5: authoritative cashbox bindings, reciprocal FX links, one balanced
-- journal per transfer leg, and separate IQD/USD partner ledger accounts.

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
    and coalesce(ca.data->>'account_id',ca.data->>'accountId')=v_ledger) then
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
    'isActive',v_active,'is_active',v_active,
    'accountId',v_ledger,'account_id',v_ledger,
    'linkedCashAccountId',v_linked,'linked_cash_account_id',v_linked,
    'createdAt',coalesce(p_account->'created_at',p_account->'createdAt',to_jsonb(now())),
    'updatedAt',to_jsonb(now()),'updated_at',to_jsonb(now()),'schemaVersion',4,'schema_version',4
  ),auth.uid(),auth.uid())
  on conflict(company_id,id) do update set data=excluded.data,is_deleted=false,deleted_at=null,
    version=erp_cash_accounts.version+1,updated_at=now(),updated_by=auth.uid();

  delete from public.erp_cash_account_links where company_id=p_company_id
    and (source_cash_account_id=v_id or target_cash_account_id=v_id);
  if v_linked is not null then
    insert into public.erp_cash_account_links(company_id,source_cash_account_id,target_cash_account_id,created_by,updated_by)
    values(p_company_id,v_id,v_linked,auth.uid(),auth.uid()),(p_company_id,v_linked,v_id,auth.uid(),auth.uid())
    on conflict(company_id,source_cash_account_id) do update set target_cash_account_id=excluded.target_cash_account_id,
      updated_at=now(),updated_by=auth.uid();
    update public.erp_cash_accounts set data=jsonb_set(jsonb_set(data,'{linkedCashAccountId}',to_jsonb(v_id),true),'{linked_cash_account_id}',to_jsonb(v_id),true),
      version=version+1,updated_at=now(),updated_by=auth.uid()
    where company_id=p_company_id and id=v_linked and not is_deleted;
  end if;
end $$;

create or replace function public.erp_transfer_cloud_cash(
  p_company_id uuid,p_from_cash_account_id text,p_to_cash_account_id text,
  p_source_amount numeric,p_target_amount numeric,p_exchange_rate numeric,
  p_transfer_date timestamptz,p_notes text default null
) returns void language plpgsql security definer set search_path=public as $$
declare
  f public.erp_cash_accounts%rowtype; t public.erp_cash_accounts%rowtype;
  fc text; tc text; fl text; tl text; clearing text:='system-fx-clearing';
  transfer_id text:=gen_random_uuid()::text; voucher text; balance numeric;
  tx_out text:=gen_random_uuid()::text; tx_in text:=gen_random_uuid()::text;
  j1 text:=gen_random_uuid()::text; j2 text:=gen_random_uuid()::text;
  now_at timestamptz:=now();
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['cashbox.transfer','accounting.update']);
  if p_from_cash_account_id=p_to_cash_account_id or p_source_amount<=0 or p_target_amount<=0 or p_exchange_rate<=0 then raise exception 'invalid_cash_transfer'; end if;
  select * into f from public.erp_cash_accounts where company_id=p_company_id and id=p_from_cash_account_id and not is_deleted for update;
  select * into t from public.erp_cash_accounts where company_id=p_company_id and id=p_to_cash_account_id and not is_deleted for update;
  if f.id is null or t.id is null then raise exception 'cashbox_not_found'; end if;
  fc:=upper(coalesce(f.data->>'currency','')); tc:=upper(coalesce(t.data->>'currency',''));
  fl:=coalesce(f.data->>'account_id',f.data->>'accountId'); tl:=coalesce(t.data->>'account_id',t.data->>'accountId');
  if fl is null or tl is null then raise exception 'cashbox_ledger_required'; end if;
  if fc=tc then
    if abs(p_exchange_rate-1)>0.000001 or abs(p_source_amount-p_target_amount)>0.01 then raise exception 'same_currency_transfer_requires_rate_one'; end if;
  else
    if abs(p_target_amount-p_source_amount*p_exchange_rate)>greatest(0.01,abs(p_target_amount)*0.005) then raise exception 'cash_amount_exchange_rate_mismatch'; end if;
    if public.erp_resolve_linked_cash_account(p_company_id,p_from_cash_account_id,tc)<>p_to_cash_account_id then raise exception 'cashboxes_not_linked_for_fx'; end if;
    perform public.erp_ensure_workflow_fx_accounts(p_company_id);
    if not exists(select 1 from public.erp_accounts where organization_id=p_company_id and account_id=clearing and is_active) then raise exception 'fx_clearing_account_missing'; end if;
  end if;
  select public.erp_try_numeric(coalesce(f.data->>'openingBalance',f.data->>'opening_balance'),0)+coalesce(sum(case when data->>'type'='receipt' then public.erp_try_numeric(data->>'amount',0) else -public.erp_try_numeric(data->>'amount',0) end),0)
  into balance from public.erp_cash_transactions where company_id=p_company_id and not is_deleted and data->>'cashAccountId'=p_from_cash_account_id;
  if balance<p_source_amount then raise exception 'source_cashbox_balance_insufficient'; end if;
  voucher:=public.erp_next_document_number(p_company_id,'cash_transfer','CT',p_transfer_date);
  insert into public.erp_cash_transfers(company_id,id,data,created_by,updated_by) values(p_company_id,transfer_id,jsonb_build_object(
    'id',transfer_id,'transferNumber',voucher,'fromAccountId',p_from_cash_account_id,'toAccountId',p_to_cash_account_id,
    'sourceAmount',p_source_amount,'sourceCurrency',fc,'targetAmount',p_target_amount,'targetCurrency',tc,'exchangeRate',p_exchange_rate,
    'transferDate',p_transfer_date,'notes',p_notes,'journalMode','single_balanced_document'),auth.uid(),auth.uid());

  insert into public.erp_cash_transactions(company_id,id,data,created_by,updated_by) values
  (p_company_id,tx_out,jsonb_build_object('id',tx_out,'voucherNumber',voucher,'type','payment','category','cash_transfer','amount',p_source_amount,'currency',fc,'transactionDate',p_transfer_date,'referenceType','cash_transfer','referenceId',transfer_id,'cashAccountId',p_from_cash_account_id,'counterAccountId',case when fc=tc then tl else clearing end,'journalEntryId',j1,'notes',p_notes),auth.uid(),auth.uid()),
  (p_company_id,tx_in,jsonb_build_object('id',tx_in,'voucherNumber',voucher,'type','receipt','category','cash_transfer','amount',p_target_amount,'currency',tc,'transactionDate',p_transfer_date,'referenceType','cash_transfer','referenceId',transfer_id,'cashAccountId',p_to_cash_account_id,'counterAccountId',case when fc=tc then fl else clearing end,'journalEntryId',case when fc=tc then j1 else j2 end,'notes',p_notes),auth.uid(),auth.uid());

  insert into public.erp_journal_entries(company_id,id,data,created_by,updated_by) values
  (p_company_id,j1,jsonb_build_object('id',j1,'entryNumber','CT-'||voucher,'entryDate',p_transfer_date,'description','تحويل بين الصناديق','currency',fc,'referenceType','cash_transfer','referenceId',transfer_id,'totalDebit',p_source_amount,'totalCredit',p_source_amount,'status','posted','createdAt',now_at),auth.uid(),auth.uid());
  insert into public.erp_journal_lines(company_id,id,data,created_by,updated_by) values
  (p_company_id,gen_random_uuid()::text,jsonb_build_object('entryId',j1,'accountId',case when fc=tc then tl else clearing end,'currency',fc,'referenceType','cash_transfer','referenceId',transfer_id,'debit',p_source_amount,'credit',0,'description',p_notes),auth.uid(),auth.uid()),
  (p_company_id,gen_random_uuid()::text,jsonb_build_object('entryId',j1,'accountId',fl,'currency',fc,'referenceType','cash_transfer','referenceId',transfer_id,'debit',0,'credit',p_source_amount,'description',p_notes),auth.uid(),auth.uid());
  if fc<>tc then
    insert into public.erp_journal_entries(company_id,id,data,created_by,updated_by) values
    (p_company_id,j2,jsonb_build_object('id',j2,'entryNumber','CT-'||voucher||'-2','entryDate',p_transfer_date,'description','استلام تحويل عملة بين الصناديق','currency',tc,'referenceType','cash_transfer','referenceId',transfer_id,'totalDebit',p_target_amount,'totalCredit',p_target_amount,'status','posted','createdAt',now_at),auth.uid(),auth.uid());
    insert into public.erp_journal_lines(company_id,id,data,created_by,updated_by) values
    (p_company_id,gen_random_uuid()::text,jsonb_build_object('entryId',j2,'accountId',tl,'currency',tc,'referenceType','cash_transfer','referenceId',transfer_id,'debit',p_target_amount,'credit',0,'description',p_notes),auth.uid(),auth.uid()),
    (p_company_id,gen_random_uuid()::text,jsonb_build_object('entryId',j2,'accountId',clearing,'currency',tc,'referenceType','cash_transfer','referenceId',transfer_id,'debit',0,'credit',p_target_amount,'description',p_notes),auth.uid(),auth.uid());
  end if;
end $$;

create or replace function public.erp_partner_ledger_before_write()
returns trigger language plpgsql security definer set search_path=public as $$
declare
  typ text:=case when tg_table_name='erp_suppliers' then 'supplier' else 'customer' end;
  parent_code text:=case when tg_table_name='erp_suppliers' then '2100' else '1400' end;
  parent_id text; acct_type text:=case when typ='supplier' then 'liability' else 'asset' end;
  prefix text:=case when typ='supplier' then '21' else '14' end;
  nm text:=coalesce(nullif(btrim(new.data->>'name'),''),new.id);
  usd_id text:='partner-'||typ||'-usd-'||substr(md5(new.id),1,16);
  iqd_id text:='partner-'||typ||'-iqd-'||substr(md5(new.id),1,16);
  active boolean:=not coalesce(new.is_deleted,false) and public.erp_try_boolean(coalesce(new.data->>'is_active',new.data->>'isActive'),'true');
begin
  perform public.erp_seed_default_accounts(new.company_id);
  select account_id into parent_id from public.erp_accounts where organization_id=new.company_id and code=parent_code and is_active limit 1;
  if parent_id is null then raise exception 'partner_parent_account_missing:%',parent_code; end if;
  insert into public.erp_accounts(organization_id,account_id,code,name,account_type,parent_account_id,currency,opening_balance,is_active,source_updated_at,synced_at,synced_by) values
  (new.company_id,usd_id,prefix||'U'||upper(substr(md5(new.id),1,6)),(case when typ='supplier' then 'المورد ' else 'العميل ' end)||nm||' USD',acct_type,parent_id,'USD',0,active,now(),now(),auth.uid()),
  (new.company_id,iqd_id,prefix||'I'||upper(substr(md5(new.id),1,6)),(case when typ='supplier' then 'المورد ' else 'العميل ' end)||nm||' IQD',acct_type,parent_id,'IQD',0,active,now(),now(),auth.uid())
  on conflict(organization_id,account_id) do update set name=excluded.name,currency=excluded.currency,is_active=excluded.is_active,synced_at=now(),synced_by=auth.uid();
  insert into public.erp_partner_accounts(organization_id,partner_type,partner_id,partner_name,usd_account_id,iqd_account_id,is_active,source_updated_at,synced_at,synced_by)
  values(new.company_id,typ,new.id,nm,usd_id,iqd_id,active,now(),now(),auth.uid())
  on conflict(organization_id,partner_type,partner_id) do update set partner_name=excluded.partner_name,usd_account_id=excluded.usd_account_id,iqd_account_id=excluded.iqd_account_id,is_active=excluded.is_active,synced_at=now(),synced_by=auth.uid();
  new.data:=new.data||jsonb_build_object('accountIdUsd',usd_id,'accountIdIqd',iqd_id,'ledgerAccountId',case when upper(coalesce(new.data->>'currency','IQD'))='USD' then usd_id else iqd_id end);
  return new;
end $$;

create or replace function public.erp_workflow_partner_account(p_company_id uuid,p_partner_type text,p_partner_id text,p_currency text)
returns text language plpgsql security definer set search_path=public as $$
declare id text;
begin
  select case when upper(p_currency)='IQD' then iqd_account_id when upper(p_currency)='USD' then usd_account_id else null end into id
  from public.erp_partner_accounts where organization_id=p_company_id and partner_type=p_partner_type and partner_id=p_partner_id and is_active limit 1;
  if id is null or not exists(select 1 from public.erp_accounts where organization_id=p_company_id and account_id=id and is_active and upper(currency)=upper(p_currency)) then
    if p_partner_type='customer' then update public.erp_customers set data=data where company_id=p_company_id and id=p_partner_id and not is_deleted;
    elsif p_partner_type='supplier' then update public.erp_suppliers set data=data where company_id=p_company_id and id=p_partner_id and not is_deleted;
    else raise exception 'invalid partner type'; end if;
    select case when upper(p_currency)='IQD' then iqd_account_id else usd_account_id end into id from public.erp_partner_accounts
    where organization_id=p_company_id and partner_type=p_partner_type and partner_id=p_partner_id and is_active limit 1;
  end if;
  if id is null then raise exception 'partner_currency_account_missing:%',upper(p_currency); end if;
  return id;
end $$;

do $$ declare r record; begin
  for r in select company_id,id from public.erp_customers where not is_deleted loop update public.erp_customers set data=data where company_id=r.company_id and id=r.id; end loop;
  for r in select company_id,id from public.erp_suppliers where not is_deleted loop update public.erp_suppliers set data=data where company_id=r.company_id and id=r.id; end loop;
end $$;

grant execute on function public.erp_save_cloud_cash_account(uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_transfer_cloud_cash(uuid,text,text,numeric,numeric,numeric,timestamptz,text) to authenticated,service_role;
grant execute on function public.erp_workflow_partner_account(uuid,text,text,text) to authenticated,service_role;

commit;
