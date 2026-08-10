-- Final accounting integrity hardening.
-- Corrects a later reconciliation definition that unintentionally reverted
-- credit-normal account handling, and enforces safe cash/ledger bindings.
begin;

create or replace function public.erp_save_cloud_cash_account(
  p_company_id uuid,
  p_account jsonb
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id text := p_account->>'id';
  v_ledger text := p_account->>'account_id';
  v_currency text := upper(coalesce(nullif(p_account->>'currency',''), 'USD'));
  v_ledger_currency text;
  v_ledger_type text;
begin
  if not public.can_manage_master_data(p_company_id) then
    raise exception 'access denied';
  end if;
  if coalesce(v_id,'')='' or coalesce(trim(p_account->>'name'),'')='' or coalesce(v_ledger,'')='' then
    raise exception 'بيانات الصندوق غير مكتملة';
  end if;

  select upper(currency), account_type
    into v_ledger_currency, v_ledger_type
    from public.erp_accounts
   where organization_id=p_company_id
     and account_id=v_ledger
     and is_active;

  if v_ledger_currency is null then
    raise exception 'الحساب المحاسبي المختار غير موجود أو غير فعال';
  end if;
  if v_ledger_type <> 'asset' then
    raise exception 'يجب ربط الصندوق بحساب أصول فقط';
  end if;
  if v_ledger_currency not in (v_currency, 'MULTI') then
    raise exception 'عملة الصندوق لا تطابق عملة الحساب المحاسبي';
  end if;
  if exists (
    select 1
      from public.erp_cash_accounts ca
     where ca.company_id=p_company_id
       and ca.id<>v_id
       and not ca.is_deleted
       and coalesce((ca.data->>'isActive')::boolean,true)
       and ca.data->>'accountId'=v_ledger
  ) then
    raise exception 'الحساب المحاسبي مرتبط بصندوق فعال آخر';
  end if;

  insert into public.erp_cash_accounts(company_id,id,data,created_by,updated_by)
  values(p_company_id,v_id,jsonb_build_object(
    'id',v_id,
    'name',trim(p_account->>'name'),
    'type',coalesce(p_account->>'type','cash'),
    'currency',v_currency,
    'openingBalance',coalesce(nullif(p_account->>'opening_balance','')::numeric,0),
    'isActive',coalesce((p_account->>'is_active')::boolean,true),
    'accountId',v_ledger,
    'createdAt',coalesce(p_account->'created_at',to_jsonb(now())),
    'updatedAt',to_jsonb(now())
  ),auth.uid(),auth.uid())
  on conflict(company_id,id) do update set
    data=excluded.data,
    is_deleted=false,
    deleted_at=null,
    updated_at=now(),
    updated_by=auth.uid();
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
    select
      ca.id,
      ca.data->>'name' as name,
      upper(coalesce(ca.data->>'currency','')) as currency,
      ca.data->>'accountId' as ledger_account_id,
      coalesce(nullif(ca.data->>'openingBalance','')::numeric,0)
        + coalesce(sum(case
            when ct.data->>'type'='receipt' then coalesce(nullif(ct.data->>'amount','')::numeric,0)
            when ct.data->>'type'='payment' then -coalesce(nullif(ct.data->>'amount','')::numeric,0)
            else 0
          end),0) as subledger_balance
    from public.erp_cash_accounts ca
    left join public.erp_cash_transactions ct
      on ct.company_id=ca.company_id
     and ct.data->>'cashAccountId'=ca.id
     and not ct.is_deleted
    where ca.company_id=p_company_id
      and not ca.is_deleted
      and coalesce((ca.data->>'isActive')::boolean,true)
      and public.is_active_company_member(p_company_id)
    group by ca.id, ca.data
  ), ledger as (
    select
      a.account_id,
      upper(a.currency) as currency,
      coalesce(a.opening_balance,0)
        + coalesce(sum(case when je.id is not null then
            case when a.account_type in ('liability','equity','revenue')
              then coalesce(nullif(jl.data->>'credit','')::numeric,0)
                 - coalesce(nullif(jl.data->>'debit','')::numeric,0)
              else coalesce(nullif(jl.data->>'debit','')::numeric,0)
                 - coalesce(nullif(jl.data->>'credit','')::numeric,0)
            end
          else 0 end),0) as ledger_balance
    from public.erp_accounts a
    left join public.erp_journal_lines jl
      on jl.company_id=a.organization_id
     and jl.data->>'accountId'=a.account_id
     and not jl.is_deleted
    left join public.erp_journal_entries je
      on je.company_id=jl.company_id
     and je.id=jl.data->>'entryId'
     and not je.is_deleted
     and coalesce(je.data->>'status','posted')='posted'
    where a.organization_id=p_company_id
      and a.is_active
      and public.is_active_company_member(p_company_id)
    group by a.account_id, a.currency, a.opening_balance, a.account_type
  )
  select
    c.id,
    c.name,
    c.currency,
    c.subledger_balance,
    coalesce(l.ledger_balance,0),
    c.subledger_balance-coalesce(l.ledger_balance,0)
  from cash c
  left join ledger l
    on l.account_id=c.ledger_account_id
   and l.currency in (c.currency, 'MULTI')
  order by c.name;
$$;

-- A posted line must reference an active account in the same company and use
-- non-negative one-sided debit/credit values.
create or replace function public.erp_validate_journal_line_integrity()
returns trigger
language plpgsql
set search_path=public
as $$
declare
  v_debit numeric := coalesce(nullif(new.data->>'debit','')::numeric,0);
  v_credit numeric := coalesce(nullif(new.data->>'credit','')::numeric,0);
begin
  if coalesce(new.is_deleted,false) then return new; end if;
  if coalesce(new.data->>'entryId','')='' or coalesce(new.data->>'accountId','')='' then
    raise exception 'بيانات سطر القيد غير مكتملة';
  end if;
  if v_debit < 0 or v_credit < 0 or (v_debit > 0 and v_credit > 0) or (v_debit = 0 and v_credit = 0) then
    raise exception 'يجب أن يحتوي سطر القيد على مدين أو دائن موجب واحد فقط';
  end if;
  if not exists (
    select 1 from public.erp_accounts a
     where a.organization_id=new.company_id
       and a.account_id=new.data->>'accountId'
       and a.is_active
  ) then
    raise exception 'حساب سطر القيد غير موجود أو غير فعال';
  end if;
  return new;
end
$$;

drop trigger if exists trg_erp_journal_lines_integrity on public.erp_journal_lines;
create trigger trg_erp_journal_lines_integrity
before insert or update of data,is_deleted on public.erp_journal_lines
for each row execute function public.erp_validate_journal_line_integrity();

grant execute on function public.erp_save_cloud_cash_account(uuid,jsonb) to authenticated;
grant execute on function public.erp_cloud_cash_ledger_reconciliation(uuid) to authenticated;
grant execute on function public.erp_validate_journal_line_integrity() to authenticated;

commit;
