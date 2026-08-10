-- R24 runtime closure: accounting/cashbox persistence, vouchers, transfers and lock-free operational posting.
-- Historical cash reconciliation remains explicit. Normal saves/posts never scan old transactions.
begin;

create or replace function public.erp_r24_guard_cash_transaction_payload(
  p_company_id uuid,p_existing jsonb,p_incoming jsonb
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_result jsonb:=coalesce(p_incoming,'{}'::jsonb);
  v_item record;
  v_field text;
  v_technical boolean;
begin
  if not public.erp_cloud_user_has_permission(p_company_id,'cashbox.fields.restrict') then
    return v_result;
  end if;
  for v_item in select key,value from jsonb_each(coalesce(p_incoming,'{}'::jsonb)) loop
    v_technical:=v_item.key in ('id','createdAt','created_at','updatedAt','updated_at');
    v_field:=case v_item.key
      when 'type' then 'transactionType'
      when 'voucherNumber' then 'documentNumber'
      when 'voucher_number' then 'documentNumber'
      when 'category' then 'purpose'
      when 'amount' then 'amount'
      when 'currency' then 'currency'
      when 'transactionDate' then 'operationalDate'
      when 'transaction_date' then 'operationalDate'
      when 'partyType' then 'partyType'
      when 'party_type' then 'partyType'
      when 'partyId' then 'partyId'
      when 'party_id' then 'partyId'
      when 'partyName' then 'partyName'
      when 'party_name' then 'partyName'
      when 'paymentMethod' then 'paymentMethod'
      when 'payment_method' then 'paymentMethod'
      when 'referenceType' then 'reference'
      when 'reference_type' then 'reference'
      when 'referenceId' then 'reference'
      when 'reference_id' then 'reference'
      when 'cashAccountId' then 'cashAccount'
      when 'cash_account_id' then 'cashAccount'
      when 'counterAccountId' then 'counterAccount'
      when 'counter_account_id' then 'counterAccount'
      when 'journalEntryId' then 'journalEntryId'
      when 'journal_entry_id' then 'journalEntryId'
      when 'notes' then 'notes'
      else null end;
    if not v_technical and (v_field is null or not public.erp_cloud_user_can_edit_field(p_company_id,'cashbox',v_field,null)) then
      if coalesce(p_existing,'{}'::jsonb) ? v_item.key then
        v_result:=jsonb_set(v_result,array[v_item.key],p_existing->v_item.key,true);
      else
        v_result:=v_result-v_item.key;
      end if;
    end if;
  end loop;
  return v_result;
end $$;

create or replace function public.erp_r24_guard_cash_account_payload(
  p_company_id uuid,p_existing jsonb,p_incoming jsonb
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_result jsonb:=coalesce(p_incoming,'{}'::jsonb);
  v_item record;
  v_field text;
  v_technical boolean;
begin
  if not public.erp_cloud_user_has_permission(p_company_id,'cashbox.fields.restrict') then
    return v_result;
  end if;
  for v_item in select key,value from jsonb_each(coalesce(p_incoming,'{}'::jsonb)) loop
    v_technical:=v_item.key in ('id','createdAt','created_at','updatedAt','updated_at','schemaVersion','schema_version');
    v_field:=case v_item.key
      when 'name' then 'name'
      when 'type' then 'type'
      when 'currency' then 'currency'
      when 'openingBalance' then 'openingBalance'
      when 'opening_balance' then 'openingBalance'
      when 'isActive' then 'isActive'
      when 'is_active' then 'isActive'
      when 'accountId' then 'ledgerAccount'
      when 'account_id' then 'ledgerAccount'
      when 'linkedCashAccountId' then 'linkedCashAccount'
      when 'linked_cash_account_id' then 'linkedCashAccount'
      else null end;
    if not v_technical and (v_field is null or not public.erp_cloud_user_can_edit_field(p_company_id,'cashbox',v_field,null)) then
      if coalesce(p_existing,'{}'::jsonb) ? v_item.key then
        v_result:=jsonb_set(v_result,array[v_item.key],p_existing->v_item.key,true);
      else
        v_result:=v_result-v_item.key;
      end if;
    end if;
  end loop;
  return v_result;
end $$;

create or replace function public.erp_r9_post_cloud_cash_transaction(
  p_company_id uuid,p_transaction jsonb,p_replace boolean default false
) returns void language plpgsql security definer set search_path=public as $$
declare v_old jsonb; v_guarded jsonb; v_id text:=coalesce(p_transaction->>'id','');
begin
  select data into v_old from public.erp_cash_transactions
   where company_id=p_company_id and id=v_id and not is_deleted;
  if p_replace then
    if not public.erp_cloud_user_has_permission(p_company_id,'accounting.update') then
      raise exception 'permission_denied:accounting.update' using errcode='42501';
    end if;
  else
    if not public.erp_cloud_user_has_permission(p_company_id,'accounting.create') then
      raise exception 'permission_denied:accounting.create' using errcode='42501';
    end if;
  end if;
  v_guarded:=public.erp_r24_guard_cash_transaction_payload(p_company_id,coalesce(v_old,'{}'::jsonb),p_transaction);
  perform public.erp_post_cloud_cash_transaction(p_company_id,v_guarded,p_replace);
end $$;

create or replace function public.erp_r9_save_cloud_cash_account(p_company_id uuid,p_account jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare v_old jsonb; v_guarded jsonb; v_id text:=coalesce(p_account->>'id','');
begin
  select data into v_old from public.erp_cash_accounts where company_id=p_company_id and id=v_id and not is_deleted;
  if v_old is null then
    perform public.erp_r9_require_field_edit(p_company_id,'cashbox','name','accounting.create');
  elsif not public.erp_cloud_user_has_permission(p_company_id,'accounting.update') then
    raise exception 'permission_denied:accounting.update' using errcode='42501';
  end if;
  v_guarded:=public.erp_r24_guard_cash_account_payload(p_company_id,coalesce(v_old,'{}'::jsonb),p_account);
  perform public.erp_save_cloud_cash_account(p_company_id,v_guarded);
end $$;

-- Cashbox definition changes only synchronize the current ledger opening balance.
-- Historical rebinding is intentionally NOT part of an interactive save transaction.
create or replace function public.erp_r15_cashbox_definition_changed()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_ledger text; v_opening numeric;
begin
  if new.is_deleted then return new; end if;
  v_ledger:=public.erp_r23_cashbox_ledger_account_id(new.data);
  v_opening:=public.erp_try_numeric(coalesce(new.data->>'openingBalance',new.data->>'opening_balance'),0);
  if nullif(v_ledger,'') is not null then
    update public.erp_accounts
       set opening_balance=v_opening,source_updated_at=now(),synced_at=now()
     where organization_id=new.company_id and account_id=v_ledger and is_active
       and opening_balance is distinct from v_opening;
  end if;
  return new;
end $$;

-- Deferred reconciliation is bounded to the single changed transaction.
-- Canonical R22/R23 rows are already exact and need no further writes.
create or replace function public.erp_r16_deferred_cash_reconcile()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_cash_id text; v_journal_id text;
begin
  if new.is_deleted then return new; end if;
  if public.erp_try_boolean(coalesce(new.data->>'r23DeterministicCashBinding',new.data->>'r22CanonicalCashBinding'),'false') then
    return new;
  end if;
  v_cash_id:=coalesce(new.data->>'cashAccountId',new.data->>'cash_account_id');
  v_journal_id:=coalesce(new.data->>'journalEntryId',new.data->>'journal_entry_id');
  if nullif(v_cash_id,'') is not null and nullif(v_journal_id,'') is not null then
    perform public.erp_r22_bind_cash_transaction_exact(new.company_id,new.id,v_cash_id);
  end if;
  return new;
end $$;

create or replace function public.erp_r22_save_cloud_cash_account(p_company_id uuid,p_account jsonb)
returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_r15_save_cloud_cash_account(p_company_id,p_account);
end $$;

create or replace function public.erp_r22_post_cloud_cash_transaction(
  p_company_id uuid,p_transaction jsonb,p_replace boolean default false
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_r15_post_cloud_cash_transaction(p_company_id,p_transaction,p_replace);
end $$;

create or replace function public.erp_r22_transfer_cloud_cash(
  p_company_id uuid,p_from_cash_account_id text,p_to_cash_account_id text,
  p_source_amount numeric,p_target_amount numeric,p_exchange_rate numeric(38,20),
  p_transfer_date timestamptz,p_notes text default null
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
  voucher text; out_voucher text; in_voucher text;
  source_entry_number text; target_entry_number text;
  available numeric; tolerance numeric; linked text;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  perform public.erp_r9_require_field_edit(p_company_id,'cashbox','transferFrom','accounting.update');
  perform public.erp_r9_require_field_edit(p_company_id,'cashbox','transferTo',null);
  perform public.erp_r9_require_field_edit(p_company_id,'cashbox','amount',null);
  perform public.erp_r9_require_field_edit(p_company_id,'cashbox','exchangeRate',null);
  perform public.erp_r9_require_field_edit(p_company_id,'cashbox','operationalDate',null);
  if p_notes is not null then perform public.erp_r9_require_field_edit(p_company_id,'cashbox','notes',null); end if;
  if p_transfer_date is null then raise exception 'transfer_date_required'; end if;
  perform public.erp_validate_operational_date(p_company_id,'accounting',p_transfer_date);
  if p_from_cash_account_id is null or p_to_cash_account_id is null
     or p_from_cash_account_id=p_to_cash_account_id
     or coalesce(p_source_amount,0)<=0 or coalesce(p_target_amount,0)<=0
     or coalesce(p_exchange_rate,0)<=0 then raise exception 'invalid_cash_transfer'; end if;

  select * into f from public.erp_cash_accounts
  where company_id=p_company_id and id=p_from_cash_account_id and not is_deleted for update;
  select * into t from public.erp_cash_accounts
  where company_id=p_company_id and id=p_to_cash_account_id and not is_deleted for update;
  if f.id is null or t.id is null then raise exception 'cashbox_not_found'; end if;
  if not public.erp_try_boolean(coalesce(f.data->>'isActive',f.data->>'is_active'),'true')
     or not public.erp_try_boolean(coalesce(t.data->>'isActive',t.data->>'is_active'),'true') then
    raise exception 'cashbox_inactive';
  end if;
  fc:=upper(coalesce(f.data->>'currency',''));
  tc:=upper(coalesce(t.data->>'currency',''));
  fl:=public.erp_r23_cashbox_ledger_account_id(f.data);
  tl:=public.erp_r23_cashbox_ledger_account_id(t.data);
  if fc not in ('IQD','USD') or tc not in ('IQD','USD') then raise exception 'cashbox_currency_invalid'; end if;
  if fl is null or tl is null then raise exception 'cashbox_ledger_required'; end if;
  perform public.erp_phase2_account_guard(p_company_id,fl,'asset',fc);
  perform public.erp_phase2_account_guard(p_company_id,tl,'asset',tc);

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
    if linked is distinct from p_to_cash_account_id then raise exception 'cashboxes_not_linked_for_fx'; end if;
    source_clearing:=public.erp_ensure_fx_clearing_account(p_company_id,fc);
    target_clearing:=public.erp_ensure_fx_clearing_account(p_company_id,tc);
  end if;

  select balance into available from public.erp_cloud_cash_account_balances(p_company_id)
  where cash_account_id=p_from_cash_account_id;
  if coalesce(available,0)<p_source_amount then raise exception 'source_cashbox_balance_insufficient'; end if;

  voucher:=public.erp_next_document_number(p_company_id,'cash_transfer','CT',p_transfer_date);
  out_voucher:=public.erp_next_document_number(p_company_id,'cash_payment','CP',p_transfer_date);
  in_voucher:=public.erp_next_document_number(p_company_id,'cash_receipt','CR',p_transfer_date);
  source_entry_number:=public.erp_next_document_number(p_company_id,'journal_entry','JE',p_transfer_date);
  if fc<>tc then target_entry_number:=public.erp_next_document_number(p_company_id,'journal_entry','JE',p_transfer_date); end if;

  insert into public.erp_cash_transfers(company_id,id,data,created_by,updated_by)
  values(p_company_id,transfer_id,jsonb_build_object(
    'id',transfer_id,'transferNumber',voucher,'fromAccountId',p_from_cash_account_id,'toAccountId',p_to_cash_account_id,
    'sourceAmount',p_source_amount,'sourceCurrency',fc,'targetAmount',p_target_amount,'targetCurrency',tc,
    'exchangeRate',p_exchange_rate,'transferDate',p_transfer_date,'notes',p_notes,'status','posted',
    'sourceTransactionId',tx_out,'targetTransactionId',tx_in,'sourceJournalId',j_source,
    'targetJournalId',case when fc=tc then null else j_target end,
    'runtimeVersion','r22','canonicalIdentity',true),auth.uid(),auth.uid());

  insert into public.erp_cash_transactions(company_id,id,data,created_by,updated_by) values
  (p_company_id,tx_out,jsonb_build_object(
    'id',tx_out,'voucherNumber',out_voucher,'type','payment','category','cash_transfer',
    'amount',p_source_amount,'currency',fc,'transactionDate',p_transfer_date,
    'referenceType','cash_transfer','referenceId',transfer_id,'cashAccountId',p_from_cash_account_id,
    'cashLedgerAccountId',fl,'counterAccountId',case when fc=tc then tl else source_clearing end,
    'journalEntryId',j_source,'notes',p_notes,'r22CanonicalCashBinding',true),auth.uid(),auth.uid()),
  (p_company_id,tx_in,jsonb_build_object(
    'id',tx_in,'voucherNumber',in_voucher,'type','receipt','category','cash_transfer',
    'amount',p_target_amount,'currency',tc,'transactionDate',p_transfer_date,
    'referenceType','cash_transfer','referenceId',transfer_id,'cashAccountId',p_to_cash_account_id,
    'cashLedgerAccountId',tl,'counterAccountId',case when fc=tc then fl else target_clearing end,
    'journalEntryId',case when fc=tc then j_source else j_target end,'notes',p_notes,
    'r22CanonicalCashBinding',true),auth.uid(),auth.uid());

  insert into public.erp_journal_entries(company_id,id,data,created_by,updated_by)
  values(p_company_id,j_source,jsonb_build_object(
    'id',j_source,'entryNumber',source_entry_number,'entryDate',p_transfer_date,
    'description','Cashbox transfer','currency',fc,
    'referenceType',case when fc=tc then 'cash_transfer' else 'cash_transfer_source' end,
    'referenceId',transfer_id,'cashTransactionIds',jsonb_build_array(tx_out,case when fc=tc then tx_in else null end),
    'totalDebit',p_source_amount,'totalCredit',p_source_amount,'status','posted','createdAt',now(),
    'r22CanonicalCashTransfer',true),auth.uid(),auth.uid());

  insert into public.erp_journal_lines(company_id,id,data,created_by,updated_by) values
  (p_company_id,gen_random_uuid()::text,jsonb_build_object(
    'entryId',j_source,'accountId',case when fc=tc then tl else source_clearing end,'currency',fc,
    'referenceType',case when fc=tc then 'cash_transfer' else 'cash_transfer_source' end,'referenceId',transfer_id,
    'cashTransactionId',case when fc=tc then tx_in else null end,'cashAccountId',case when fc=tc then p_to_cash_account_id else null end,
    'debit',p_source_amount,'credit',0,'description',coalesce(p_notes,'Cashbox transfer'),
    'r22CanonicalCashBinding',fc=tc),auth.uid(),auth.uid()),
  (p_company_id,gen_random_uuid()::text,jsonb_build_object(
    'entryId',j_source,'accountId',fl,'currency',fc,
    'referenceType',case when fc=tc then 'cash_transfer' else 'cash_transfer_source' end,'referenceId',transfer_id,
    'cashTransactionId',tx_out,'cashAccountId',p_from_cash_account_id,
    'debit',0,'credit',p_source_amount,'description',coalesce(p_notes,'Cashbox transfer'),
    'r22CanonicalCashBinding',true),auth.uid(),auth.uid());

  if fc<>tc then
    insert into public.erp_journal_entries(company_id,id,data,created_by,updated_by)
    values(p_company_id,j_target,jsonb_build_object(
      'id',j_target,'entryNumber',target_entry_number,'entryDate',p_transfer_date,
      'description','FX cashbox transfer receipt','currency',tc,
      'referenceType','cash_transfer_target','referenceId',transfer_id,
      'cashTransactionIds',jsonb_build_array(tx_in),
      'totalDebit',p_target_amount,'totalCredit',p_target_amount,'status','posted','createdAt',now(),
      'r22CanonicalCashTransfer',true),auth.uid(),auth.uid());
    insert into public.erp_journal_lines(company_id,id,data,created_by,updated_by) values
    (p_company_id,gen_random_uuid()::text,jsonb_build_object(
      'entryId',j_target,'accountId',tl,'currency',tc,'referenceType','cash_transfer_target','referenceId',transfer_id,
      'cashTransactionId',tx_in,'cashAccountId',p_to_cash_account_id,
      'debit',p_target_amount,'credit',0,'description',coalesce(p_notes,'FX cashbox receipt'),
      'r22CanonicalCashBinding',true),auth.uid(),auth.uid()),
    (p_company_id,gen_random_uuid()::text,jsonb_build_object(
      'entryId',j_target,'accountId',target_clearing,'currency',tc,'referenceType','cash_transfer_target','referenceId',transfer_id,
      'debit',0,'credit',p_target_amount,'description',coalesce(p_notes,'FX cashbox receipt')),
      auth.uid(),auth.uid());
  end if;

  perform public.erp_v762_assert_posted_journal_balanced(p_company_id,j_source,'r22_cash_transfer_source');
  if fc<>tc then perform public.erp_v762_assert_posted_journal_balanced(p_company_id,j_target,'r22_cash_transfer_target'); end if;
  return jsonb_build_object(
    'ok',true,'version','r22','transferId',transfer_id,'transferNumber',voucher,
    'sourceTransactionId',tx_out,'targetTransactionId',tx_in,
    'sourceJournalId',j_source,'targetJournalId',case when fc=tc then null else j_target end,
    'reconciliationMode','deferred_exact_transaction');
end;
$$;



-- Repair only deterministic duplicate legacy bindings: the cashbox name/currency
-- must resolve to exactly one unused active asset ledger with the same normalized name.
do $$
declare r record; v_candidate text; v_count integer;
begin
  for r in
    select ca.company_id,ca.id,ca.data,upper(coalesce(ca.data->>'currency','')) currency,
           regexp_replace(lower(btrim(coalesce(ca.data->>'name',''))),'\s+',' ','g') cash_name,
           regexp_replace(lower(btrim(coalesce(cur.name,''))),'\s+',' ','g') ledger_name
      from public.erp_cash_accounts ca
      left join public.erp_accounts cur on cur.organization_id=ca.company_id
       and cur.account_id=public.erp_r23_cashbox_ledger_account_id(ca.data)
     where not ca.is_deleted
       and exists(select 1 from public.erp_cash_accounts other
         where other.company_id=ca.company_id and other.id<>ca.id and not other.is_deleted
           and public.erp_r23_cashbox_ledger_account_id(other.data)=public.erp_r23_cashbox_ledger_account_id(ca.data))
  loop
    if r.cash_name<>r.ledger_name then
      select count(*)::integer,min(a.account_id) into v_count,v_candidate
        from public.erp_accounts a
       where a.organization_id=r.company_id and a.is_active and a.account_type='asset'
         and upper(coalesce(a.currency,''))=r.currency
         and regexp_replace(lower(btrim(coalesce(a.name,''))),'\s+',' ','g')=r.cash_name
         and not exists(select 1 from public.erp_cash_accounts used
           where used.company_id=r.company_id and used.id<>r.id and not used.is_deleted
             and public.erp_r23_cashbox_ledger_account_id(used.data)=a.account_id);
      if v_count=1 then
        update public.erp_cash_accounts
           set data=data||jsonb_build_object('accountId',v_candidate,'account_id',v_candidate,
                    'r24LedgerBindingRepair',true,'updatedAt',now(),'updated_at',now()),
               version=version+1,updated_at=now(),updated_by=auth.uid()
         where company_id=r.company_id and id=r.id and not is_deleted;
      end if;
    end if;
  end loop;
end $$;

revoke all on function public.erp_r24_guard_cash_transaction_payload(uuid,jsonb,jsonb) from public,anon;
revoke all on function public.erp_r24_guard_cash_account_payload(uuid,jsonb,jsonb) from public,anon;
grant execute on function public.erp_r24_guard_cash_transaction_payload(uuid,jsonb,jsonb) to authenticated,service_role;
grant execute on function public.erp_r24_guard_cash_account_payload(uuid,jsonb,jsonb) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
