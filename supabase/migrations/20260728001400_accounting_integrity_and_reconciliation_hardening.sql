-- Accounting integrity hardening: chart hierarchy, cashbox linkage and
-- reconciliation correctness. This migration is intentionally additive.
begin;

create unique index if not exists erp_accounts_code_company_uq
  on public.erp_accounts(organization_id, lower(code)) where is_active;

create unique index if not exists erp_cash_account_ledger_company_uq
  on public.erp_cash_accounts(company_id, (data->>'accountId'))
  where not is_deleted and coalesce((data->>'isActive')::boolean,true);

create or replace function public.erp_save_cloud_ledger_account(
  p_company_id uuid,p_account jsonb,p_require_existing boolean default false
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_id text:=p_account->>'id';
  v_parent text:=nullif(p_account->>'parentId','');
  v_currency text:=upper(coalesce(nullif(p_account->>'currency',''),'USD'));
  v_parent_currency text;
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  if coalesce(v_id,'')='' or coalesce(trim(p_account->>'code'),'')='' or coalesce(trim(p_account->>'name'),'')='' then raise exception 'بيانات الحساب غير مكتملة'; end if;
  if p_require_existing and not exists(select 1 from public.erp_accounts where organization_id=p_company_id and account_id=v_id) then raise exception 'الحساب غير موجود'; end if;
  if exists(select 1 from public.erp_accounts where organization_id=p_company_id and lower(code)=lower(trim(p_account->>'code')) and account_id<>v_id and is_active) then raise exception 'رمز الحساب مستخدم مسبقًا'; end if;
  if v_parent=v_id then raise exception 'لا يمكن جعل الحساب أباً لنفسه'; end if;
  if v_parent is not null then
    select currency into v_parent_currency from public.erp_accounts where organization_id=p_company_id and account_id=v_parent and is_active;
    if v_parent_currency is null then raise exception 'الحساب الأب غير موجود أو غير فعال'; end if;
    if upper(v_parent_currency)<>v_currency then raise exception 'عملة الحساب الفرعي يجب أن تطابق عملة الحساب الأب'; end if;
    if p_require_existing and exists(
      with recursive descendants as (
        select account_id from public.erp_accounts where organization_id=p_company_id and parent_account_id=v_id and is_active
        union all
        select a.account_id from public.erp_accounts a join descendants d on a.parent_account_id=d.account_id
        where a.organization_id=p_company_id and a.is_active
      ) select 1 from descendants where account_id=v_parent
    ) then raise exception 'لا يمكن نقل الحساب تحت أحد حساباته الفرعية'; end if;
  end if;
  insert into public.erp_accounts(organization_id,account_id,code,name,account_type,parent_account_id,currency,opening_balance,is_active,source_updated_at,synced_at,synced_by)
  values(p_company_id,v_id,trim(p_account->>'code'),trim(p_account->>'name'),p_account->>'type',v_parent,v_currency,coalesce((p_account->>'openingBalance')::numeric,0),coalesce((p_account->>'isActive')::boolean,true),now(),now(),auth.uid())
  on conflict(organization_id,account_id) do update set code=excluded.code,name=excluded.name,account_type=excluded.account_type,parent_account_id=excluded.parent_account_id,currency=excluded.currency,opening_balance=excluded.opening_balance,is_active=excluded.is_active,source_updated_at=now(),synced_at=now(),synced_by=auth.uid();
end $$;

create or replace function public.erp_cloud_cash_ledger_reconciliation(
  p_company_id uuid
) returns table(cash_account_id text,cash_account_name text,currency text,subledger_balance numeric,ledger_balance numeric,difference numeric)
language sql security definer set search_path=public as $$
  with cash as (
    select ca.id,ca.data->>'name' name,upper(coalesce(ca.data->>'currency','')) currency,
      ca.data->>'accountId' ledger_account_id,
      coalesce(nullif(ca.data->>'openingBalance','')::numeric,0)+coalesce(sum(case when ct.data->>'type'='receipt' then coalesce(nullif(ct.data->>'amount','')::numeric,0) when ct.data->>'type'='payment' then -coalesce(nullif(ct.data->>'amount','')::numeric,0) else 0 end),0) subledger_balance
    from public.erp_cash_accounts ca left join public.erp_cash_transactions ct
      on ct.company_id=ca.company_id and ct.data->>'cashAccountId'=ca.id and not ct.is_deleted
    where ca.company_id=p_company_id and not ca.is_deleted and public.is_active_company_member(p_company_id)
    group by ca.id,ca.data
  ), ledger as (
    select a.account_id,
      coalesce(a.opening_balance,0)+coalesce(sum(case when je.id is not null then
        case when a.account_type in ('liability','equity','revenue')
          then coalesce(nullif(jl.data->>'credit','')::numeric,0)-coalesce(nullif(jl.data->>'debit','')::numeric,0)
          else coalesce(nullif(jl.data->>'debit','')::numeric,0)-coalesce(nullif(jl.data->>'credit','')::numeric,0) end
        else 0 end),0) ledger_balance
    from public.erp_accounts a
    left join public.erp_journal_lines jl on jl.company_id=a.organization_id and jl.data->>'accountId'=a.account_id and not jl.is_deleted
    left join public.erp_journal_entries je on je.company_id=jl.company_id and je.id=jl.data->>'entryId' and not je.is_deleted and coalesce(je.data->>'status','posted')='posted'
    where a.organization_id=p_company_id and a.is_active and public.is_active_company_member(p_company_id)
    group by a.account_id,a.opening_balance,a.account_type
  )
  select c.id,c.name,c.currency,c.subledger_balance,coalesce(l.ledger_balance,0),c.subledger_balance-coalesce(l.ledger_balance,0)
  from cash c left join ledger l on l.account_id=c.ledger_account_id order by c.name;
$$;

grant execute on function public.erp_save_cloud_ledger_account(uuid,jsonb,boolean) to authenticated;
grant execute on function public.erp_cloud_cash_ledger_reconciliation(uuid) to authenticated;
commit;
