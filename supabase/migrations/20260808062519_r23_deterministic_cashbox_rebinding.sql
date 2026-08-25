-- R23 deterministic historical cashbox rebinding.
-- Identity selection is based on Cash Transaction ID, then Transfer ID + side +
-- current cashbox/current ledger. Amount is NOT used to select the line;
-- it is validation only after identity has already been established.
create or replace function public.erp_r22_bind_cash_transaction_exact(
  p_company_id uuid,p_transaction_id text,p_cash_account_id text
) returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
  v_tx public.erp_cash_transactions%rowtype;
  v_cash public.erp_cash_accounts%rowtype;
  v_entry public.erp_journal_entries%rowtype;
  v_transfer public.erp_cash_transfers%rowtype;
  v_ledger record;
  v_line public.erp_journal_lines%rowtype;
  v_amount numeric; v_type text; v_currency text; v_ref_type text; v_ref_id text;
  v_line_id text; v_count integer:=0; v_method text; v_side text; v_expected_tx text;
begin
  select * into v_tx from public.erp_cash_transactions
  where company_id=p_company_id and id=p_transaction_id and not is_deleted for update;
  if not found then
    perform public.erp_r16_record_reconciliation_issue(p_company_id,'r23_cash_transaction_missing','cash_transaction',p_transaction_id,jsonb_build_object('cashAccountId',p_cash_account_id));
    return jsonb_build_object('ok',false,'code','cash_transaction_missing','transactionId',p_transaction_id);
  end if;
  if coalesce(v_tx.data->>'cashAccountId',v_tx.data->>'cash_account_id') is distinct from p_cash_account_id then
    perform public.erp_r16_record_reconciliation_issue(p_company_id,'r23_cash_transaction_cashbox_mismatch','cash_transaction',p_transaction_id,jsonb_build_object('expectedCashAccountId',p_cash_account_id,'actualCashAccountId',coalesce(v_tx.data->>'cashAccountId',v_tx.data->>'cash_account_id')));
    return jsonb_build_object('ok',false,'code','cash_transaction_cashbox_mismatch','transactionId',p_transaction_id);
  end if;
  select * into v_cash from public.erp_cash_accounts where company_id=p_company_id and id=p_cash_account_id and not is_deleted;
  if not found then return jsonb_build_object('ok',false,'code','cashbox_missing','cashAccountId',p_cash_account_id); end if;
  select a.account_id,a.code,a.name,a.currency into v_ledger from public.erp_accounts a
  where a.organization_id=p_company_id and a.account_id=public.erp_r23_cashbox_ledger_account_id(v_cash.data) and a.is_active;
  if v_ledger.account_id is null then return jsonb_build_object('ok',false,'code','cashbox_ledger_missing','cashAccountId',p_cash_account_id); end if;
  select * into v_entry from public.erp_journal_entries
  where company_id=p_company_id and id=coalesce(v_tx.data->>'journalEntryId',v_tx.data->>'journal_entry_id') and not is_deleted;
  if not found then
    perform public.erp_r16_record_reconciliation_issue(p_company_id,'cash_journal_missing','cash_transaction',p_transaction_id,jsonb_build_object('cashAccountId',p_cash_account_id,'journalEntryId',coalesce(v_tx.data->>'journalEntryId',v_tx.data->>'journal_entry_id')));
    return jsonb_build_object('ok',false,'code','cash_journal_missing','transactionId',p_transaction_id);
  end if;
  v_amount:=abs(public.erp_try_numeric(v_tx.data->>'amount',0));
  v_type:=lower(coalesce(v_tx.data->>'type',''));
  v_currency:=upper(coalesce(v_tx.data->>'currency',''));
  v_ref_type:=lower(coalesce(v_tx.data->>'referenceType',v_tx.data->>'reference_type',''));
  v_ref_id:=nullif(coalesce(v_tx.data->>'referenceId',v_tx.data->>'reference_id'),'');

  select count(*)::integer,min(jl.id) into v_count,v_line_id
  from public.erp_journal_lines jl
  where jl.company_id=p_company_id and not jl.is_deleted
    and jl.data->>'entryId'=v_entry.id and jl.data->>'cashTransactionId'=p_transaction_id;
  if v_count=1 then v_method:='cash_transaction_id';
  elsif v_count>1 then
    perform public.erp_r16_record_reconciliation_issue(p_company_id,'r23_cash_identity_ambiguous','cash_transaction',p_transaction_id,jsonb_build_object('journalEntryId',v_entry.id,'candidateCount',v_count,'method','cash_transaction_id'));
    return jsonb_build_object('ok',false,'code','cash_identity_ambiguous','transactionId',p_transaction_id,'candidateCount',v_count);
  end if;

  if v_line_id is null and v_ref_type='cash_transfer' and v_ref_id is not null then
    select * into v_transfer from public.erp_cash_transfers where company_id=p_company_id and id=v_ref_id and not is_deleted;
    if found then
      if coalesce(v_transfer.data->>'fromAccountId',v_transfer.data->>'from_account_id')=p_cash_account_id
         and v_type in ('payment','expense','out','cash_out','supplier_payment','transfer_out') then
        v_side:='source'; v_expected_tx:=nullif(coalesce(v_transfer.data->>'sourceTransactionId',v_transfer.data->>'source_transaction_id'),'');
      elsif coalesce(v_transfer.data->>'toAccountId',v_transfer.data->>'to_account_id')=p_cash_account_id
         and v_type in ('receipt','income','in','cash_in','customer_receipt','transfer_in') then
        v_side:='target'; v_expected_tx:=nullif(coalesce(v_transfer.data->>'targetTransactionId',v_transfer.data->>'target_transaction_id'),'');
      end if;
      if v_side is not null and (v_expected_tx is null or v_expected_tx=p_transaction_id) then
        select count(*)::integer,min(jl.id) into v_count,v_line_id
        from public.erp_journal_lines jl
        where jl.company_id=p_company_id and not jl.is_deleted
          and jl.data->>'entryId'=v_entry.id
          and coalesce(jl.data->>'referenceId',jl.data->>'reference_id')=v_ref_id
          and upper(coalesce(nullif(jl.data->>'currency',''),v_entry.data->>'currency',''))=v_currency
          and (jl.data->>'cashAccountId'=p_cash_account_id or jl.data->>'accountId'=v_ledger.account_id)
          and case when v_side='source'
            then public.erp_try_numeric(jl.data->>'credit',0)>0 and public.erp_try_numeric(jl.data->>'debit',0)=0
            else public.erp_try_numeric(jl.data->>'debit',0)>0 and public.erp_try_numeric(jl.data->>'credit',0)=0 end;
        if v_count=1 then v_method:='transfer_id_cashbox_current_account';
        elsif v_count>1 then
          perform public.erp_r16_record_reconciliation_issue(p_company_id,'r23_cash_transfer_identity_ambiguous','cash_transaction',p_transaction_id,jsonb_build_object('transferId',v_ref_id,'side',v_side,'journalEntryId',v_entry.id,'candidateCount',v_count));
          return jsonb_build_object('ok',false,'code','cash_identity_ambiguous','transactionId',p_transaction_id,'candidateCount',v_count);
        end if;
      end if;
    end if;
  end if;

  if v_line_id is null and (
       v_entry.data->>'cashTransactionId'=p_transaction_id
       or (coalesce(v_entry.data->>'referenceId',v_entry.data->>'reference_id')=p_transaction_id
           and lower(coalesce(v_entry.data->>'referenceType',v_entry.data->>'reference_type','')) in ('cash_transaction','manual_cash_transaction'))
     ) then
    select count(*)::integer,min(jl.id) into v_count,v_line_id
    from public.erp_journal_lines jl
    where jl.company_id=p_company_id and not jl.is_deleted
      and jl.data->>'entryId'=v_entry.id
      and upper(coalesce(nullif(jl.data->>'currency',''),v_entry.data->>'currency',''))=v_currency
      and (jl.data->>'cashAccountId'=p_cash_account_id or jl.data->>'accountId'=v_ledger.account_id)
      and case when v_type in ('receipt','income','in','cash_in','customer_receipt','transfer_in')
        then public.erp_try_numeric(jl.data->>'debit',0)>0 and public.erp_try_numeric(jl.data->>'credit',0)=0
        else public.erp_try_numeric(jl.data->>'credit',0)>0 and public.erp_try_numeric(jl.data->>'debit',0)=0 end;
    if v_count=1 then v_method:='journal_transaction_identity_current_account';
    elsif v_count>1 then
      perform public.erp_r16_record_reconciliation_issue(p_company_id,'r23_cash_header_identity_ambiguous','cash_transaction',p_transaction_id,jsonb_build_object('journalEntryId',v_entry.id,'candidateCount',v_count));
      return jsonb_build_object('ok',false,'code','cash_identity_ambiguous','transactionId',p_transaction_id,'candidateCount',v_count);
    end if;
  end if;

  if v_line_id is null then
    perform public.erp_r16_record_reconciliation_issue(p_company_id,'r23_cash_identity_unresolved','cash_transaction',p_transaction_id,jsonb_build_object('cashAccountId',p_cash_account_id,'journalEntryId',v_entry.id,'transferId',case when v_ref_type='cash_transfer' then v_ref_id else null end,'currentLedgerAccountId',v_ledger.account_id));
    return jsonb_build_object('ok',false,'code','cash_identity_unresolved','transactionId',p_transaction_id);
  end if;
  select * into v_line from public.erp_journal_lines where company_id=p_company_id and id=v_line_id and not is_deleted;
  if upper(coalesce(nullif(v_line.data->>'currency',''),v_entry.data->>'currency',''))<>v_currency
     or not public.erp_r16_cash_line_matches(v_line.data,v_type,v_amount) then
    perform public.erp_r16_record_reconciliation_issue(p_company_id,'r23_cash_identity_amount_or_side_mismatch','cash_transaction',p_transaction_id,jsonb_build_object('journalEntryId',v_entry.id,'journalLineId',v_line_id,'method',v_method,'amount',v_amount,'type',v_type));
    return jsonb_build_object('ok',false,'code','cash_identity_validation_failed','transactionId',p_transaction_id,'journalLineId',v_line_id);
  end if;

  update public.erp_journal_lines
  set data=data||jsonb_build_object(
      'accountId',v_ledger.account_id,'accountCode',v_ledger.code,'accountName',v_ledger.name,'currency',upper(v_ledger.currency),
      'cashTransactionId',p_transaction_id,'cashAccountId',p_cash_account_id,
      'r22CanonicalCashBinding',true,'r23DeterministicCashBinding',true,'r23CashIdentityMethod',v_method),
      updated_at=now(),updated_by=auth.uid()
  where company_id=p_company_id and id=v_line_id;
  update public.erp_cash_transactions
  set data=data||jsonb_build_object('cashLedgerAccountId',v_ledger.account_id,'r22CanonicalCashBinding',true,
      'r23DeterministicCashBinding',true,'r23CashIdentityMethod',v_method),updated_at=now(),updated_by=auth.uid()
  where company_id=p_company_id and id=p_transaction_id;
  perform public.erp_r16_resolve_reconciliation_issues(p_company_id,'cash_transaction',p_transaction_id);
  return jsonb_build_object('ok',true,'transactionId',p_transaction_id,'cashAccountId',p_cash_account_id,
    'journalEntryId',v_entry.id,'journalLineId',v_line_id,'ledgerAccountId',v_ledger.account_id,'identityMethod',v_method);
end $$;

-- First R23 wrapper; lock-safe iteration is superseded by the next migration.
create or replace function public.erp_r23_rebind_cashbox_journals_internal(p_company_id uuid,p_cash_account_id text)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare
  v_cash public.erp_cash_accounts%rowtype; v_ledger record; v_tx record; v_result jsonb;
  v_opening numeric; v_bound integer:=0; v_failed integer:=0; v_results jsonb:='[]'::jsonb;
begin
  select * into v_cash from public.erp_cash_accounts where company_id=p_company_id and id=p_cash_account_id and not is_deleted;
  if not found then return jsonb_build_object('ok',false,'cashAccountId',p_cash_account_id,'code','cashbox_missing'); end if;
  select a.account_id,a.code,a.name,a.currency into v_ledger from public.erp_accounts a
  where a.organization_id=p_company_id and a.account_id=public.erp_r23_cashbox_ledger_account_id(v_cash.data) and a.is_active;
  if v_ledger.account_id is null then return jsonb_build_object('ok',false,'cashAccountId',p_cash_account_id,'code','ledger_missing'); end if;
  if upper(coalesce(v_ledger.currency,''))<>upper(coalesce(v_cash.data->>'currency','')) then return jsonb_build_object('ok',false,'cashAccountId',p_cash_account_id,'code','ledger_currency_mismatch'); end if;
  v_opening:=public.erp_try_numeric(coalesce(v_cash.data->>'openingBalance',v_cash.data->>'opening_balance'),0);
  update public.erp_accounts set opening_balance=v_opening,source_updated_at=now(),synced_at=now()
  where organization_id=p_company_id and account_id=v_ledger.account_id and opening_balance is distinct from v_opening;
  for v_tx in select id from public.erp_cash_transactions
    where company_id=p_company_id and not is_deleted
      and coalesce(data->>'cashAccountId',data->>'cash_account_id')=p_cash_account_id
      and nullif(coalesce(data->>'journalEntryId',data->>'journal_entry_id'),'') is not null
    order by created_at,id
  loop
    v_result:=public.erp_r22_bind_cash_transaction_exact(p_company_id,v_tx.id,p_cash_account_id);
    v_results:=v_results||jsonb_build_array(v_result);
    if coalesce((v_result->>'ok')::boolean,false) then v_bound:=v_bound+1; else v_failed:=v_failed+1; end if;
  end loop;
  return jsonb_build_object('ok',v_failed=0,'cashAccountId',p_cash_account_id,'ledgerAccountId',v_ledger.account_id,
    'boundTransactions',v_bound,'unresolvedTransactions',v_failed,'openingBalance',v_opening,'results',v_results);
end $$;

create or replace function public.erp_r15_rebind_cashbox_journals_internal(p_company_id uuid,p_cash_account_id text)
returns jsonb language sql security definer set search_path=public
as $$ select public.erp_r23_rebind_cashbox_journals_internal($1,$2) $$;

revoke all on function public.erp_r23_rebind_cashbox_journals_internal(uuid,text) from public,anon,authenticated;
grant execute on function public.erp_r23_rebind_cashbox_journals_internal(uuid,text) to service_role;
notify pgrst,'reload schema';
