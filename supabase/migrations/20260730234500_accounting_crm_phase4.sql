begin;

-- Phase 4: CRM/accounting refinements.
-- Commercial opportunities create sales documents only; no schema change is needed for that UI rule.

create or replace function public.erp_save_cloud_ledger_account(
  p_company_id uuid,p_account jsonb,p_require_existing boolean default false
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_id text:=btrim(coalesce(p_account->>'id',''));
  v_parent text:=nullif(btrim(coalesce(p_account->>'parentId',p_account->>'parent_id','')),'');
  v_code text:=btrim(coalesce(p_account->>'code',''));
  v_name text:=btrim(coalesce(p_account->>'name',''));
  v_currency text:=upper(coalesce(nullif(btrim(p_account->>'currency'),''),'USD'));
  v_type text:=lower(btrim(coalesce(p_account->>'type',p_account->>'account_type','')));
  v_parent_currency text;
  v_parent_type text;
  v_existing public.erp_accounts%rowtype;
  v_active boolean:=public.erp_try_boolean(coalesce(p_account->>'isActive',p_account->>'is_active'),'true');
  v_opening numeric:=public.erp_try_numeric(coalesce(p_account->>'openingBalance',p_account->>'opening_balance'),0);
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  if v_id='' or v_code='' or v_name='' then raise exception 'بيانات الحساب غير مكتملة'; end if;
  if v_type not in ('asset','liability','equity','revenue','expense') then raise exception 'نوع الحساب غير صحيح'; end if;
  if v_currency not in ('USD','IQD','MULTI') then raise exception 'عملة الحساب غير صحيحة'; end if;

  select * into v_existing from public.erp_accounts
  where organization_id=p_company_id and account_id=v_id for update;
  if p_require_existing and not found then raise exception 'الحساب غير موجود'; end if;

  if not v_active and exists(
    select 1 from public.erp_accounts
    where organization_id=p_company_id and parent_account_id=v_id and is_active
  ) then raise exception 'لا يمكن تعطيل حساب يحتوي على حسابات فرعية فعالة'; end if;

  if v_existing.account_id is not null and
     (upper(v_existing.currency)<>v_currency or v_existing.account_type<>v_type) and exists(
       select 1 from public.erp_journal_lines
       where company_id=p_company_id and not is_deleted and data->>'accountId'=v_id
     ) then raise exception 'لا يمكن تغيير نوع أو عملة حساب مرتبط بقيود'; end if;

  if exists(
    select 1 from public.erp_accounts
    where organization_id=p_company_id and lower(code)=lower(v_code)
      and account_id<>v_id and is_active
  ) then raise exception 'رمز الحساب مستخدم مسبقًا'; end if;

  if v_parent=v_id then raise exception 'لا يمكن جعل الحساب أباً لنفسه'; end if;
  if v_parent is not null then
    select upper(currency),account_type into v_parent_currency,v_parent_type
    from public.erp_accounts
    where organization_id=p_company_id and account_id=v_parent and is_active;
    if v_parent_currency is null then raise exception 'الحساب الأب غير موجود أو غير فعال'; end if;
    if v_parent_type<>v_type then raise exception 'نوع الحساب الفرعي يجب أن يطابق نوع الحساب الأب'; end if;
    -- Child accounts may use a currency different from the parent.
    -- The parent remains a grouping account; posting currency is validated on the leaf account.
    if exists(
      select 1 from public.erp_journal_lines
      where company_id=p_company_id and not is_deleted and data->>'accountId'=v_parent
    ) then raise exception 'لا يمكن إضافة حساب فرعي تحت حساب مستخدم في قيود؛ أنشئ حساباً تجميعياً'; end if;
    if exists(
      with recursive descendants as (
        select account_id from public.erp_accounts
        where organization_id=p_company_id and parent_account_id=v_id
        union all
        select a.account_id from public.erp_accounts a
        join descendants d on a.parent_account_id=d.account_id
        where a.organization_id=p_company_id
      ) select 1 from descendants where account_id=v_parent
    ) then raise exception 'لا يمكن نقل الحساب تحت أحد حساباته الفرعية'; end if;
  end if;

  insert into public.erp_accounts(
    organization_id,account_id,code,name,account_type,parent_account_id,
    currency,opening_balance,is_active,source_updated_at,synced_at,synced_by
  ) values(
    p_company_id,v_id,v_code,v_name,v_type,v_parent,v_currency,v_opening,
    v_active,now(),now(),auth.uid()
  ) on conflict(organization_id,account_id) do update set
    code=excluded.code,name=excluded.name,account_type=excluded.account_type,
    parent_account_id=excluded.parent_account_id,currency=excluded.currency,
    opening_balance=excluded.opening_balance,is_active=excluded.is_active,
    source_updated_at=now(),synced_at=now(),synced_by=auth.uid();
end $$;

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
  v_expense_ledger_id text := nullif(btrim(coalesce(p_expense->>'expenseAccountId',p_expense->>'expense_account_id','')),'');
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

  if v_expense_ledger_id is null then raise exception 'يجب اختيار حساب كلفة من نوع مصروف'; end if;
  perform 1 from public.erp_accounts
  where organization_id=p_company_id and account_id=v_expense_ledger_id
    and is_active and account_type='expense'
    and upper(currency) in (v_currency,'MULTI');
  if not found then raise exception 'حساب الكلفة يجب أن يكون حساب مصروف فعالاً ومطابقاً للعملة'; end if;

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
    'accountId',v_cash_account_id,'expenseAccountId',v_expense_ledger_id,'postingStatus','posted',
    'journalEntryId',v_journal_id,'cashTransactionId',v_cash_transaction_id,
    'updatedAt',v_now
  ),auth.uid(),auth.uid());

  return jsonb_build_object('id',v_id,'postingStatus','posted','currency',v_currency,
    'journalEntryId',v_journal_id,'cashTransactionId',v_cash_transaction_id);
end;
$$;

grant execute on function public.erp_save_cloud_ledger_account(uuid,jsonb,boolean) to authenticated;
grant execute on function public.erp_post_cloud_expense(uuid,jsonb) to authenticated;

commit;
