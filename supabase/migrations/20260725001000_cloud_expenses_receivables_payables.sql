begin;

create table if not exists public.erp_expenses (like public.erp_cars including all);

create index if not exists erp_expenses_date_idx
  on public.erp_expenses(company_id, (data->>'date')) where not is_deleted;
create index if not exists erp_expenses_cash_account_idx
  on public.erp_expenses(company_id, (data->>'accountId')) where not is_deleted;
create index if not exists erp_expenses_journal_idx
  on public.erp_expenses(company_id, (data->>'journalEntryId')) where not is_deleted;

alter table public.erp_expenses enable row level security;
drop policy if exists erp_expenses_select on public.erp_expenses;
drop policy if exists erp_expenses_insert on public.erp_expenses;
drop policy if exists erp_expenses_update on public.erp_expenses;
create policy erp_expenses_select on public.erp_expenses for select to authenticated
  using (public.is_active_company_member(company_id));
create policy erp_expenses_insert on public.erp_expenses for insert to authenticated
  with check (public.can_manage_master_data(company_id));
create policy erp_expenses_update on public.erp_expenses for update to authenticated
  using (public.can_manage_master_data(company_id))
  with check (public.can_manage_master_data(company_id));

drop trigger if exists erp_expenses_before_write on public.erp_expenses;
create trigger erp_expenses_before_write before insert or update on public.erp_expenses
  for each row execute function public.erp_master_before_write();

grant select,insert,update on public.erp_expenses to authenticated;

create or replace function public.erp_post_cloud_expense(
  p_company_id uuid,
  p_expense jsonb
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_id text := p_expense->>'id';
  v_account_id text := nullif(p_expense->>'accountId','');
  v_amount numeric := coalesce((p_expense->>'amount')::numeric,0);
  v_rate numeric := coalesce((p_expense->>'exchangeRate')::numeric,1);
  v_currency text := upper(coalesce(nullif(p_expense->>'currency',''),'USD'));
  v_amount_usd numeric;
  v_amount_iqd numeric;
  v_journal_id text;
  v_cash_transaction_id text;
  v_now timestamptz := now();
  v_date date;
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  if coalesce(v_id,'')='' or coalesce(p_expense->>'title','')='' or coalesce(p_expense->>'category','')='' then
    raise exception 'بيانات المصروف غير مكتملة';
  end if;
  if v_amount<=0 or v_rate<=0 then raise exception 'المبلغ وسعر الصرف يجب أن يكونا أكبر من صفر'; end if;
  v_date := (p_expense->>'date')::date;
  if exists(select 1 from public.erp_expenses where company_id=p_company_id and id=v_id and not is_deleted) then
    raise exception 'المصروف موجود مسبقاً';
  end if;

  if v_currency='IQD' then
    v_amount_iqd:=v_amount;
    v_amount_usd:=round(v_amount/nullif(v_rate,0),2);
  else
    v_amount_usd:=v_amount;
    v_amount_iqd:=round(v_amount*v_rate,0);
  end if;

  if v_account_id is null then
    insert into public.erp_expenses(company_id,id,data,created_by,updated_by)
    values(p_company_id,v_id,p_expense||jsonb_build_object(
      'amountUsd',v_amount_usd,'amountIqd',v_amount_iqd,
      'postingStatus','draft','journalEntryId',null,'updatedAt',v_now
    ),auth.uid(),auth.uid());
    return jsonb_build_object('id',v_id,'postingStatus','draft');
  end if;

  perform 1 from public.erp_cash_accounts
   where company_id=p_company_id and id=v_account_id and not is_deleted
     and coalesce((data->>'isActive')::boolean,true) for update;
  if not found then raise exception 'الصندوق غير موجود أو غير فعال'; end if;

  if not exists(select 1 from public.erp_accounts where organization_id=p_company_id and account_id='acc-5200' and is_active) then
    raise exception 'حساب المصروفات acc-5200 غير موجود أو غير فعال';
  end if;
  if not exists(select 1 from public.erp_accounts where organization_id=p_company_id and account_id='acc-1100' and is_active) then
    raise exception 'حساب النقدية acc-1100 غير موجود أو غير فعال';
  end if;

  v_journal_id := gen_random_uuid()::text;
  v_cash_transaction_id := gen_random_uuid()::text;

  insert into public.erp_journal_entries(company_id,id,data,created_by,updated_by)
  values(p_company_id,v_journal_id,jsonb_build_object(
    'id',v_journal_id,'entryNumber','EXP-'||replace(v_id,'-',''),
    'entryDate',v_date,'description',p_expense->>'title','referenceType','expense',
    'referenceId',v_id,'status','posted','totalDebit',v_amount_usd,
    'totalCredit',v_amount_usd,'createdAt',v_now,'updatedAt',v_now
  ),auth.uid(),auth.uid());

  insert into public.erp_journal_lines(company_id,id,data,created_by,updated_by) values
  (p_company_id,gen_random_uuid()::text,jsonb_build_object(
    'entryId',v_journal_id,'accountId','acc-5200','debit',v_amount_usd,'credit',0,
    'description',p_expense->>'title','createdAt',v_now,'updatedAt',v_now
  ),auth.uid(),auth.uid()),
  (p_company_id,gen_random_uuid()::text,jsonb_build_object(
    'entryId',v_journal_id,'accountId','acc-1100','debit',0,'credit',v_amount_usd,
    'description',p_expense->>'title','createdAt',v_now,'updatedAt',v_now
  ),auth.uid(),auth.uid());

  insert into public.erp_cash_transactions(company_id,id,data,created_by,updated_by)
  values(p_company_id,v_cash_transaction_id,jsonb_build_object(
    'id',v_cash_transaction_id,'voucherNumber','EXP-'||replace(v_id,'-',''),
    'type','payment','category',p_expense->>'category','accountId',v_account_id,
    'branchId',coalesce(p_expense->>'branchId','branch-main'),'amount',v_amount,
    'currency',v_currency,'exchangeRate',v_rate,'amountUsd',v_amount_usd,
    'amountIqd',v_amount_iqd,'transactionDate',v_date,'referenceType','expense',
    'referenceId',v_id,'partyType','other','partyName',p_expense->>'title',
    'notes',p_expense->>'notes','journalEntryId',v_journal_id,
    'createdAt',v_now,'updatedAt',v_now
  ),auth.uid(),auth.uid());

  insert into public.erp_expenses(company_id,id,data,created_by,updated_by)
  values(p_company_id,v_id,p_expense||jsonb_build_object(
    'amountUsd',v_amount_usd,'amountIqd',v_amount_iqd,'postingStatus','posted',
    'journalEntryId',v_journal_id,'cashTransactionId',v_cash_transaction_id,
    'updatedAt',v_now
  ),auth.uid(),auth.uid());

  return jsonb_build_object('id',v_id,'postingStatus','posted','journalEntryId',v_journal_id);
end $$;

create or replace function public.erp_delete_cloud_expense(
  p_company_id uuid,
  p_expense_id text
) returns void language plpgsql security definer set search_path=public as $$
declare v_expense public.erp_expenses%rowtype; v_now timestamptz:=now();
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  select * into v_expense from public.erp_expenses
   where company_id=p_company_id and id=p_expense_id and not is_deleted for update;
  if not found then return; end if;
  if coalesce(v_expense.data->>'postingStatus','draft')='posted' then
    raise exception 'لا يمكن حذف مصروف مرحّل. أنشئ قيداً عكسياً.';
  end if;
  update public.erp_expenses set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid()
   where company_id=p_company_id and id=p_expense_id;
end $$;

create or replace function public.erp_cloud_expense_total(p_company_id uuid)
returns numeric language sql stable security definer set search_path=public as $$
  select coalesce(sum(coalesce((data->>'amountUsd')::numeric,0)),0)
  from public.erp_expenses
  where company_id=p_company_id and not is_deleted
    and public.is_active_company_member(p_company_id)
$$;

create or replace function public.erp_cloud_receivables_payables(p_company_id uuid)
returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'receivables',coalesce((select sum(greatest(coalesce((data->>'remainingAmount')::numeric,0),0))
      from public.erp_sales where company_id=p_company_id and not is_deleted),0),
    'payables',coalesce((select sum(greatest(
      coalesce((data->>'totalAmount')::numeric,0)-coalesce((data->>'paidAmount')::numeric,0),0))
      from public.erp_purchases where company_id=p_company_id and not is_deleted),0)
  ) where public.is_active_company_member(p_company_id)
$$;

grant execute on function public.erp_post_cloud_expense(uuid,jsonb) to authenticated;
grant execute on function public.erp_delete_cloud_expense(uuid,text) to authenticated;
grant execute on function public.erp_cloud_expense_total(uuid) to authenticated;
grant execute on function public.erp_cloud_receivables_payables(uuid) to authenticated;

alter publication supabase_realtime add table public.erp_expenses;

commit;
