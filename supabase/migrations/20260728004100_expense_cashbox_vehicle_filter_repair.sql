begin;

-- Expenses are posted in the selected cashbox currency. The cashbox currency is
-- authoritative, preventing an IQD expense from being persisted as USD or the
-- reverse. Cash movement, journal and expense are written atomically.
create or replace function public.erp_post_cloud_expense(
  p_company_id uuid,
  p_expense jsonb
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id text := btrim(coalesce(p_expense->>'id',''));
  v_cash_account_id text := nullif(btrim(coalesce(p_expense->>'accountId',p_expense->>'account_id','')),'');
  v_cash_ledger_id text;
  v_cash_currency text;
  v_expense_ledger_id text;
  v_amount numeric := public.erp_try_numeric(p_expense->>'amount',0);
  v_currency text := upper(coalesce(nullif(btrim(p_expense->>'currency'),''),'USD'));
  v_amount_usd numeric := 0;
  v_amount_iqd numeric := 0;
  v_journal_id text := gen_random_uuid()::text;
  v_cash_transaction_id text := gen_random_uuid()::text;
  v_now timestamptz := now();
  v_date date;
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  if v_id='' or btrim(coalesce(p_expense->>'title',''))='' or btrim(coalesce(p_expense->>'category',''))='' then
    raise exception 'بيانات المصروف غير مكتملة';
  end if;
  if v_amount<=0 then raise exception 'مبلغ المصروف يجب أن يكون أكبر من صفر'; end if;
  if v_currency not in ('USD','IQD') then raise exception 'عملة المصروف غير مدعومة'; end if;
  v_date := (p_expense->>'date')::date;

  if exists(select 1 from public.erp_expenses where company_id=p_company_id and id=v_id and not is_deleted) then
    raise exception 'المصروف موجود مسبقاً';
  end if;

  if v_cash_account_id is null then raise exception 'يجب اختيار صندوق للمصروف'; end if;
  select nullif(coalesce(data->>'accountId',data->>'account_id'),''),
         upper(coalesce(data->>'currency',''))
    into v_cash_ledger_id,v_cash_currency
  from public.erp_cash_accounts
  where company_id=p_company_id and id=v_cash_account_id and not is_deleted
    and public.erp_try_boolean(coalesce(data->>'isActive',data->>'is_active'),'true')
  for update;
  if not found then raise exception 'الصندوق غير موجود أو غير فعال'; end if;
  if v_cash_ledger_id is null then raise exception 'الصندوق غير مرتبط بحساب في شجرة الحسابات'; end if;
  if v_cash_currency<>v_currency then
    raise exception 'عملة المصروف يجب أن تطابق عملة الصندوق المختار';
  end if;

  select account_id into v_expense_ledger_id
  from public.erp_accounts
  where organization_id=p_company_id and code='5200' and is_active
  limit 1;
  if v_expense_ledger_id is null then raise exception 'حساب المصروفات 5200 غير موجود أو غير فعال'; end if;

  if v_currency='USD' then v_amount_usd:=v_amount; else v_amount_iqd:=v_amount; end if;

  insert into public.erp_journal_entries(company_id,id,data,created_by,updated_by)
  values(p_company_id,v_journal_id,jsonb_build_object(
    'id',v_journal_id,'entryNumber','EXP-'||replace(v_id,'-',''),
    'entryDate',v_date,'description',p_expense->>'title','referenceType','expense',
    'referenceId',v_id,'status','posted','currency',v_currency,
    'totalDebit',v_amount,'totalCredit',v_amount,
    'createdAt',v_now,'updatedAt',v_now
  ),auth.uid(),auth.uid());

  insert into public.erp_journal_lines(company_id,id,data,created_by,updated_by) values
  (p_company_id,gen_random_uuid()::text,jsonb_build_object(
    'entryId',v_journal_id,'accountId',v_expense_ledger_id,
    'debit',v_amount,'credit',0,'currency',v_currency,
    'description',p_expense->>'title','createdAt',v_now,'updatedAt',v_now
  ),auth.uid(),auth.uid()),
  (p_company_id,gen_random_uuid()::text,jsonb_build_object(
    'entryId',v_journal_id,'accountId',v_cash_ledger_id,
    'debit',0,'credit',v_amount,'currency',v_currency,
    'description',p_expense->>'title','createdAt',v_now,'updatedAt',v_now
  ),auth.uid(),auth.uid());

  insert into public.erp_cash_transactions(company_id,id,data,created_by,updated_by)
  values(p_company_id,v_cash_transaction_id,jsonb_build_object(
    'id',v_cash_transaction_id,'voucherNumber','EXP-'||replace(v_id,'-',''),
    'type','payment','category',p_expense->>'category',
    'cashAccountId',v_cash_account_id,'accountId',v_cash_account_id,
    'branchId',coalesce(nullif(p_expense->>'branchId',''),'branch-main'),
    'amount',v_amount,'currency',v_currency,'exchangeRate',1,
    'amountUsd',v_amount_usd,'amountIqd',v_amount_iqd,
    'transactionDate',v_date,'referenceType','expense','referenceId',v_id,
    'partyType','other','partyName',p_expense->>'title','notes',p_expense->>'notes',
    'journalEntryId',v_journal_id,'createdAt',v_now,'updatedAt',v_now
  ),auth.uid(),auth.uid());

  insert into public.erp_expenses(company_id,id,data,created_by,updated_by)
  values(p_company_id,v_id,p_expense||jsonb_build_object(
    'currency',v_currency,'exchangeRate',1,'amountUsd',v_amount_usd,'amountIqd',v_amount_iqd,
    'accountId',v_cash_account_id,'postingStatus','posted',
    'journalEntryId',v_journal_id,'cashTransactionId',v_cash_transaction_id,
    'updatedAt',v_now
  ),auth.uid(),auth.uid());

  return jsonb_build_object('id',v_id,'postingStatus','posted','currency',v_currency,
    'journalEntryId',v_journal_id,'cashTransactionId',v_cash_transaction_id);
end;
$$;

-- Deleting an expense reverses its entire generated document package by soft
-- deleting the expense, cash movement, journal lines and journal header in one
-- transaction. Cash balances therefore refresh immediately and consistently.
create or replace function public.erp_delete_cloud_expense(
  p_company_id uuid,
  p_expense_id text
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_expense public.erp_expenses%rowtype;
  v_journal_id text;
  v_cash_transaction_id text;
  v_now timestamptz:=now();
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  select * into v_expense from public.erp_expenses
  where company_id=p_company_id and id=p_expense_id and not is_deleted for update;
  if not found then return; end if;

  v_journal_id:=nullif(v_expense.data->>'journalEntryId','');
  v_cash_transaction_id:=nullif(v_expense.data->>'cashTransactionId','');

  update public.erp_cash_transactions set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid()
  where company_id=p_company_id and not is_deleted
    and (id=v_cash_transaction_id or (data->>'referenceType'='expense' and data->>'referenceId'=p_expense_id));

  if v_journal_id is not null then
    update public.erp_journal_lines set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid()
    where company_id=p_company_id and not is_deleted and data->>'entryId'=v_journal_id;
    update public.erp_journal_entries set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid()
    where company_id=p_company_id and id=v_journal_id and not is_deleted;
  end if;

  update public.erp_expenses set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid()
  where company_id=p_company_id and id=p_expense_id;
end;
$$;

grant execute on function public.erp_post_cloud_expense(uuid,jsonb) to authenticated;
grant execute on function public.erp_delete_cloud_expense(uuid,text) to authenticated;

commit;
