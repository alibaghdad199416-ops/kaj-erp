-- Repairs chart-of-account writes, cash-account relinking, and per-cashbox
-- reconciliation. Existing cash history follows the selected ledger account
-- atomically so changing a cashbox binding never leaves split balances.
begin;

create or replace function public.erp_save_cloud_ledger_account(
  p_company_id uuid,
  p_account jsonb,
  p_require_existing boolean default false
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id text:=btrim(coalesce(p_account->>'id',''));
  v_parent text:=nullif(btrim(coalesce(p_account->>'parentId',p_account->>'parent_id','')),'');
  v_code text:=btrim(coalesce(p_account->>'code',''));
  v_name text:=btrim(coalesce(p_account->>'name',''));
  v_currency text:=upper(coalesce(nullif(btrim(p_account->>'currency'),''),'USD'));
  v_type text:=lower(btrim(coalesce(p_account->>'type',p_account->>'account_type','')));
  v_parent_currency text;
  v_existing public.erp_accounts%rowtype;
  v_active boolean:=public.erp_try_boolean(coalesce(p_account->>'isActive',p_account->>'is_active'),'true');
  v_opening numeric:=public.erp_try_numeric(coalesce(p_account->>'openingBalance',p_account->>'opening_balance'),0);
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  if v_id='' or v_code='' or v_name='' then raise exception 'بيانات الحساب غير مكتملة'; end if;
  if v_type not in ('asset','liability','equity','revenue','expense') then raise exception 'نوع الحساب غير صحيح'; end if;
  if v_currency not in ('USD','IQD','MULTI') then raise exception 'عملة الحساب غير صحيحة'; end if;

  select * into v_existing
  from public.erp_accounts
  where organization_id=p_company_id and account_id=v_id
  for update;
  if p_require_existing and not found then raise exception 'الحساب غير موجود'; end if;

  if v_existing.account_id is not null
     and (upper(v_existing.currency)<>v_currency or v_existing.account_type<>v_type)
     and exists (
       select 1 from public.erp_journal_lines
       where company_id=p_company_id and not is_deleted and data->>'accountId'=v_id
     ) then
    raise exception 'لا يمكن تغيير نوع أو عملة حساب مرتبط بقيود';
  end if;

  if exists (
    select 1 from public.erp_accounts
    where organization_id=p_company_id and lower(code)=lower(v_code)
      and account_id<>v_id and is_active
  ) then raise exception 'رمز الحساب مستخدم مسبقًا'; end if;

  if v_parent=v_id then raise exception 'لا يمكن جعل الحساب أباً لنفسه'; end if;
  if v_parent is not null then
    select upper(currency) into v_parent_currency
    from public.erp_accounts
    where organization_id=p_company_id and account_id=v_parent and is_active;
    if v_parent_currency is null then raise exception 'الحساب الأب غير موجود أو غير فعال'; end if;
    if v_parent_currency<>v_currency and v_parent_currency<>'MULTI' then
      raise exception 'عملة الحساب الفرعي يجب أن تطابق عملة الحساب الأب';
    end if;
    if exists (
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
  )
  on conflict(organization_id,account_id) do update set
    code=excluded.code,
    name=excluded.name,
    account_type=excluded.account_type,
    parent_account_id=excluded.parent_account_id,
    currency=excluded.currency,
    opening_balance=excluded.opening_balance,
    is_active=excluded.is_active,
    source_updated_at=now(),synced_at=now(),synced_by=auth.uid();
end
$$;

create or replace function public.erp_save_cloud_cash_account(
  p_company_id uuid,
  p_account jsonb
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id text:=btrim(coalesce(p_account->>'id',''));
  v_name text:=btrim(coalesce(p_account->>'name',''));
  v_ledger text:=btrim(coalesce(p_account->>'account_id',p_account->>'accountId',''));
  v_old_ledger text;
  v_currency text:=upper(coalesce(nullif(btrim(p_account->>'currency'),''),'USD'));
  v_ledger_currency text;
  v_ledger_type text;
  v_active boolean:=public.erp_try_boolean(coalesce(p_account->>'is_active',p_account->>'isActive'),'true');
  v_opening numeric:=public.erp_try_numeric(coalesce(p_account->>'opening_balance',p_account->>'openingBalance'),0);
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  if v_id='' or v_name='' or v_ledger='' then raise exception 'بيانات الصندوق غير مكتملة'; end if;
  if v_currency not in ('USD','IQD') then raise exception 'عملة الصندوق غير مدعومة'; end if;
  if v_opening<0 then raise exception 'الرصيد الافتتاحي غير صحيح'; end if;

  select upper(currency),account_type into v_ledger_currency,v_ledger_type
  from public.erp_accounts
  where organization_id=p_company_id and account_id=v_ledger and is_active;
  if v_ledger_currency is null then raise exception 'الحساب المحاسبي المختار غير موجود أو غير فعال'; end if;
  if v_ledger_type<>'asset' then raise exception 'يجب ربط الصندوق بحساب أصول فقط'; end if;
  if v_ledger_currency not in (v_currency,'MULTI') then raise exception 'عملة الصندوق لا تطابق عملة الحساب المحاسبي'; end if;

  select nullif(coalesce(data->>'accountId',data->>'account_id'),'') into v_old_ledger
  from public.erp_cash_accounts
  where company_id=p_company_id and id=v_id and not is_deleted
  for update;

  if exists (
    select 1 from public.erp_cash_accounts ca
    where ca.company_id=p_company_id and ca.id<>v_id and not ca.is_deleted
      and public.erp_try_boolean(coalesce(ca.data->>'isActive',ca.data->>'is_active'),'true')
      and nullif(coalesce(ca.data->>'accountId',ca.data->>'account_id'),'')=v_ledger
  ) then raise exception 'الحساب المحاسبي مرتبط بصندوق فعال آخر'; end if;

  -- When the linked chart account changes, move only this cashbox's journal
  -- lines. This keeps historical cash transactions and the ledger identical.
  if v_old_ledger is not null and v_old_ledger<>v_ledger then
    update public.erp_journal_lines jl
    set data=jsonb_set(jl.data,'{accountId}',to_jsonb(v_ledger),true),
        updated_at=now(),updated_by=auth.uid()
    where jl.company_id=p_company_id and not jl.is_deleted
      and jl.data->>'accountId'=v_old_ledger
      and jl.data->>'entryId' in (
        select ct.data->>'journalEntryId'
        from public.erp_cash_transactions ct
        where ct.company_id=p_company_id and not ct.is_deleted
          and ct.data->>'cashAccountId'=v_id
          and nullif(ct.data->>'journalEntryId','') is not null
      );
  end if;

  insert into public.erp_cash_accounts(company_id,id,data,created_by,updated_by)
  values(p_company_id,v_id,jsonb_build_object(
    'id',v_id,'name',v_name,'type',coalesce(nullif(p_account->>'type',''),'cash'),
    'currency',v_currency,'openingBalance',v_opening,'isActive',v_active,
    'accountId',v_ledger,
    'createdAt',coalesce(p_account->'created_at',p_account->'createdAt',to_jsonb(now())),
    'updatedAt',to_jsonb(now())
  ),auth.uid(),auth.uid())
  on conflict(company_id,id) do update set
    data=excluded.data,is_deleted=false,deleted_at=null,
    updated_at=now(),updated_by=auth.uid();
end
$$;

create or replace function public.erp_cloud_cash_ledger_reconciliation(
  p_company_id uuid
) returns table(
  cash_account_id text,
  cash_account_name text,
  currency text,
  subledger_balance numeric,
  ledger_balance numeric,
  difference numeric
)
language sql
security definer
set search_path=public
as $$
  with cash as (
    select ca.id,ca.data->>'name' as name,
      upper(coalesce(ca.data->>'currency','')) as currency,
      coalesce(nullif(ca.data->>'openingBalance','')::numeric,0) as opening_balance,
      coalesce(sum(case
        when ct.data->>'type'='receipt' then public.erp_try_numeric(ct.data->>'amount',0)
        when ct.data->>'type'='payment' then -public.erp_try_numeric(ct.data->>'amount',0)
        else 0 end),0) as movement_balance
    from public.erp_cash_accounts ca
    left join public.erp_cash_transactions ct
      on ct.company_id=ca.company_id and ct.data->>'cashAccountId'=ca.id and not ct.is_deleted
    where ca.company_id=p_company_id and not ca.is_deleted
      and public.is_active_company_member(p_company_id)
    group by ca.id,ca.data
  ), journal_by_cash as (
    select ca.id as cash_id,
      coalesce(sum(case
        when jl.data->>'accountId'=coalesce(ca.data->>'accountId',ca.data->>'account_id')
          then public.erp_try_numeric(jl.data->>'debit',0)-public.erp_try_numeric(jl.data->>'credit',0)
        else 0 end),0) as journal_movement
    from public.erp_cash_accounts ca
    left join public.erp_cash_transactions ct
      on ct.company_id=ca.company_id and ct.data->>'cashAccountId'=ca.id and not ct.is_deleted
    left join public.erp_journal_entries je
      on je.company_id=ct.company_id and je.id=ct.data->>'journalEntryId'
      and not je.is_deleted and coalesce(je.data->>'status','posted')='posted'
    left join public.erp_journal_lines jl
      on jl.company_id=je.company_id and jl.data->>'entryId'=je.id and not jl.is_deleted
    where ca.company_id=p_company_id and not ca.is_deleted
      and public.is_active_company_member(p_company_id)
    group by ca.id
  )
  select c.id,c.name,c.currency,
    c.opening_balance+c.movement_balance as subledger_balance,
    c.opening_balance+coalesce(j.journal_movement,0) as ledger_balance,
    c.movement_balance-coalesce(j.journal_movement,0) as difference
  from cash c left join journal_by_cash j on j.cash_id=c.id
  order by c.name;
$$;

grant execute on function public.erp_save_cloud_ledger_account(uuid,jsonb,boolean) to authenticated;
grant execute on function public.erp_save_cloud_cash_account(uuid,jsonb) to authenticated;
grant execute on function public.erp_cloud_cash_ledger_reconciliation(uuid) to authenticated;

commit;
