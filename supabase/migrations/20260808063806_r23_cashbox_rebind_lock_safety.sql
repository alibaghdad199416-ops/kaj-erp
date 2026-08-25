-- R23 reconciliation must not block live users. Lock candidate transactions
-- with SKIP LOCKED and report deferred rows instead of waiting for timeout.
create or replace function public.erp_r23_rebind_cashbox_journals_internal(p_company_id uuid,p_cash_account_id text)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_cash public.erp_cash_accounts%rowtype;
  v_ledger record;
  v_tx record;
  v_result jsonb;
  v_opening numeric;
  v_bound integer:=0;
  v_failed integer:=0;
  v_total integer:=0;
  v_processed integer:=0;
  v_results jsonb:='[]'::jsonb;
begin
  select * into v_cash from public.erp_cash_accounts
  where company_id=p_company_id and id=p_cash_account_id and not is_deleted;
  if not found then return jsonb_build_object('ok',false,'cashAccountId',p_cash_account_id,'code','cashbox_missing'); end if;
  select a.account_id,a.code,a.name,a.currency into v_ledger
  from public.erp_accounts a
  where a.organization_id=p_company_id and a.account_id=public.erp_r23_cashbox_ledger_account_id(v_cash.data) and a.is_active;
  if v_ledger.account_id is null then return jsonb_build_object('ok',false,'cashAccountId',p_cash_account_id,'code','ledger_missing'); end if;
  if upper(coalesce(v_ledger.currency,''))<>upper(coalesce(v_cash.data->>'currency','')) then return jsonb_build_object('ok',false,'cashAccountId',p_cash_account_id,'code','ledger_currency_mismatch'); end if;
  v_opening:=public.erp_try_numeric(coalesce(v_cash.data->>'openingBalance',v_cash.data->>'opening_balance'),0);
  update public.erp_accounts set opening_balance=v_opening,source_updated_at=now(),synced_at=now()
  where organization_id=p_company_id and account_id=v_ledger.account_id and opening_balance is distinct from v_opening;
  select count(*)::integer into v_total from public.erp_cash_transactions
  where company_id=p_company_id and not is_deleted
    and coalesce(data->>'cashAccountId',data->>'cash_account_id')=p_cash_account_id
    and nullif(coalesce(data->>'journalEntryId',data->>'journal_entry_id'),'') is not null;
  for v_tx in
    select id from public.erp_cash_transactions
    where company_id=p_company_id and not is_deleted
      and coalesce(data->>'cashAccountId',data->>'cash_account_id')=p_cash_account_id
      and nullif(coalesce(data->>'journalEntryId',data->>'journal_entry_id'),'') is not null
    order by created_at,id for update skip locked
  loop
    v_processed:=v_processed+1;
    v_result:=public.erp_r22_bind_cash_transaction_exact(p_company_id,v_tx.id,p_cash_account_id);
    v_results:=v_results||jsonb_build_array(v_result);
    if coalesce((v_result->>'ok')::boolean,false) then v_bound:=v_bound+1; else v_failed:=v_failed+1; end if;
  end loop;
  return jsonb_build_object(
    'ok',v_failed=0,'cashAccountId',p_cash_account_id,'ledgerAccountId',v_ledger.account_id,
    'boundTransactions',v_bound,'unresolvedTransactions',v_failed,
    'skippedLockedTransactions',greatest(v_total-v_processed,0),
    'openingBalance',v_opening,'results',v_results);
end $$;

create or replace function public.erp_r15_rebind_cashbox_journals_internal(p_company_id uuid,p_cash_account_id text)
returns jsonb language sql security definer set search_path=public
as $$ select public.erp_r23_rebind_cashbox_journals_internal($1,$2) $$;
notify pgrst,'reload schema';
