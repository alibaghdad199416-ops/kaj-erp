begin;

-- V7.6.1: strict operational no-capitalization policy and unified ledger sides.
-- Sales, purchases, maintenance, and expenses may only post to definition-owned
-- inventory/revenue/cost/expense accounts, partner accounts, cash accounts, and
-- explicit FX clearing accounts. Legacy capitalization accounts are forbidden.

create or replace function public.erp_v761_is_credit_nature(p_account_type text)
returns boolean language sql immutable as $$
  select lower(btrim(coalesce(p_account_type,''))) in
    ('liability','payable','equity','revenue','income')
$$;

create or replace function public.erp_v761_normal_balance(
  p_account_type text,p_opening numeric,p_debit numeric,p_credit numeric
) returns numeric language sql immutable as $$
  select case when public.erp_v761_is_credit_nature(p_account_type)
    then coalesce(p_opening,0)+coalesce(p_credit,0)-coalesce(p_debit,0)
    else coalesce(p_opening,0)+coalesce(p_debit,0)-coalesce(p_credit,0)
  end
$$;

-- Keep compatibility callers on the corrected implementation.
create or replace function public.erp_v760_is_credit_nature(p_account_type text)
returns boolean language sql immutable as $$
  select public.erp_v761_is_credit_nature(p_account_type)
$$;

create or replace function public.erp_v759_normal_balance(
  p_account_type text,p_opening numeric,p_debit numeric,p_credit numeric
) returns numeric language sql immutable as $$
  select public.erp_v761_normal_balance(p_account_type,p_opening,p_debit,p_credit)
$$;

-- Delete unused legacy capitalization masters. Referenced masters remain only as
-- inactive historical records so old posted journals remain auditable.
delete from public.erp_accounts a
 where (a.code in ('1391','1392') or lower(coalesce(a.name,'')) like '%capitalization%' or coalesce(a.name,'') like '%رسمل%')
   and not exists (
     select 1 from public.erp_journal_lines jl
      where jl.company_id=a.organization_id
        and jl.data->>'accountId'=a.account_id
        and not jl.is_deleted
   );

update public.erp_accounts
   set is_active=false,
       name='حساب تاريخي متوقف - ممنوع الاستخدام التشغيلي',
       source_updated_at=now(),synced_at=now(),synced_by=auth.uid()
 where code in ('1391','1392')
    or lower(coalesce(name,'')) like '%capitalization%'
    or coalesce(name,'') like '%رسمل%';

-- FX clearing accounts are not capitalization accounts and must not be shown as
-- inventory/fixed assets. They are technical clearing accounts only.
update public.erp_accounts
   set account_type='clearing',
       name=case code
         when '1393' then 'تسوية تحويل عملة المشتريات - دينار'
         when '1394' then 'تسوية تحويل عملة المشتريات - دولار'
         else name end,
       source_updated_at=now(),synced_at=now(),synced_by=auth.uid()
 where code in ('1393','1394');

create or replace function public.erp_v761_reject_capitalization_journal_line()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_forbidden boolean;
begin
  if coalesce(new.is_deleted,false) then return new; end if;
  select exists(
    select 1 from public.erp_accounts a
     where a.organization_id=new.company_id
       and a.account_id=new.data->>'accountId'
       and (
         a.code in ('1391','1392')
         or lower(coalesce(a.name,'')) like '%capitalization%'
         or coalesce(a.name,'') like '%رسمل%'
       )
  ) into v_forbidden;
  if v_forbidden then raise exception 'capitalization_account_forbidden'; end if;
  return new;
end;
$$;

drop trigger if exists erp_journal_lines_no_capitalization on public.erp_journal_lines;
create trigger erp_journal_lines_no_capitalization
before insert or update of data,is_deleted on public.erp_journal_lines
for each row execute function public.erp_v761_reject_capitalization_journal_line();

create or replace function public.erp_cloud_account_balance_before(
  p_company_id uuid,p_account_id text,p_before_date timestamptz
) returns numeric language sql security definer set search_path=public as $$
  with account_data as (
    select coalesce(a.opening_balance,0) opening_balance,a.account_type
      from public.erp_accounts a
     where a.organization_id=p_company_id and a.account_id=p_account_id
       and a.is_active and public.is_active_company_member(p_company_id)
  ), movement as (
    select coalesce(sum(public.erp_try_numeric(jl.data->>'debit',0)),0) debit,
           coalesce(sum(public.erp_try_numeric(jl.data->>'credit',0)),0) credit
      from public.erp_journal_lines jl
      join public.erp_journal_entries je
        on je.company_id=jl.company_id and je.id=jl.data->>'entryId'
     where jl.company_id=p_company_id and not jl.is_deleted and not je.is_deleted
       and lower(coalesce(je.data->>'status',je.data->>'postingStatus','posted'))
           in ('posted','approved','confirmed')
       and jl.data->>'accountId'=p_account_id
       and coalesce(nullif(je.data->>'entryDate','')::timestamptz,je.created_at)<p_before_date
  )
  select public.erp_v761_normal_balance(
    a.account_type,a.opening_balance,m.debit,m.credit)
  from account_data a cross join movement m
$$;

create or replace function public.erp_cloud_trial_balance(p_company_id uuid,p_currency text)
returns jsonb language sql security definer set search_path=public as $$
  with line_totals as (
    select jl.data->>'accountId' account_id,
      coalesce(sum(public.erp_try_numeric(jl.data->>'debit',0)),0) movement_debit,
      coalesce(sum(public.erp_try_numeric(jl.data->>'credit',0)),0) movement_credit
    from public.erp_journal_lines jl
    join public.erp_journal_entries je
      on je.company_id=jl.company_id and je.id=jl.data->>'entryId'
     and not je.is_deleted
     and lower(coalesce(je.data->>'status',je.data->>'postingStatus','posted'))
         in ('posted','approved','confirmed')
    where jl.company_id=p_company_id and not jl.is_deleted
      and upper(coalesce(jl.data->>'currency',je.data->>'currency',''))=upper(p_currency)
    group by jl.data->>'accountId'
  ), balances as (
    select a.account_id,a.account_type,coalesce(a.opening_balance,0) opening_balance,
      coalesce(l.movement_debit,0) movement_debit,
      coalesce(l.movement_credit,0) movement_credit,
      public.erp_v761_normal_balance(a.account_type,a.opening_balance,
        l.movement_debit,l.movement_credit) natural_balance
    from public.erp_accounts a
    left join line_totals l on l.account_id=a.account_id
    where a.organization_id=p_company_id and a.is_active
      and upper(a.currency)=upper(p_currency)
      and public.is_active_company_member(p_company_id)
  ), sides as (
    select *,case when public.erp_v761_is_credit_nature(account_type)
      then greatest(-natural_balance,0) else greatest(natural_balance,0) end closing_debit,
      case when public.erp_v761_is_credit_nature(account_type)
      then greatest(natural_balance,0) else greatest(-natural_balance,0) end closing_credit
    from balances
  )
  select jsonb_build_object(
    'debit',coalesce(sum(closing_debit),0),
    'credit',coalesce(sum(closing_credit),0),
    'movementDebit',coalesce(sum(movement_debit),0),
    'movementCredit',coalesce(sum(movement_credit),0),
    'difference',coalesce(sum(closing_debit),0)-coalesce(sum(closing_credit),0),
    'absoluteDifference',abs(coalesce(sum(closing_debit),0)-coalesce(sum(closing_credit),0)),
    'movementDifference',coalesce(sum(movement_debit),0)-coalesce(sum(movement_credit),0)
  ) from sides
$$;

create or replace function public.erp_v761_accounting_integrity_audit(p_company_id uuid)
returns jsonb language sql security definer set search_path=public as $$
  with entries as (
    select je.id,upper(coalesce(je.data->>'currency','')) currency,
      public.erp_try_numeric(je.data->>'totalDebit',0) header_debit,
      public.erp_try_numeric(je.data->>'totalCredit',0) header_credit,
      coalesce(sum(public.erp_try_numeric(jl.data->>'debit',0)),0) lines_debit,
      coalesce(sum(public.erp_try_numeric(jl.data->>'credit',0)),0) lines_credit,
      count(*) filter(where public.erp_try_numeric(jl.data->>'debit',0)<0
        or public.erp_try_numeric(jl.data->>'credit',0)<0
        or (public.erp_try_numeric(jl.data->>'debit',0)>0
            and public.erp_try_numeric(jl.data->>'credit',0)>0)) invalid_lines,
      count(*) filter(where a.code in ('1391','1392')
        or lower(coalesce(a.name,'')) like '%capitalization%'
        or coalesce(a.name,'') like '%رسمل%') capitalization_lines,
      count(*) filter(where upper(coalesce(jl.data->>'currency',je.data->>'currency',''))
        <> upper(coalesce(a.currency,''))) currency_mismatch_lines
    from public.erp_journal_entries je
    left join public.erp_journal_lines jl
      on jl.company_id=je.company_id and jl.data->>'entryId'=je.id and not jl.is_deleted
    left join public.erp_accounts a
      on a.organization_id=jl.company_id and a.account_id=jl.data->>'accountId'
    where je.company_id=p_company_id and not je.is_deleted
      and lower(coalesce(je.data->>'status',je.data->>'postingStatus','posted'))
          in ('posted','approved','confirmed')
    group by je.id,je.data
  ), bad as (
    select * from entries where abs(lines_debit-lines_credit)>0.01
      or invalid_lines>0 or capitalization_lines>0 or currency_mismatch_lines>0
      or abs(header_debit-header_credit)>0.01
      or (header_debit>0 and abs(header_debit-lines_debit)>0.01)
      or (header_credit>0 and abs(header_credit-lines_credit)>0.01)
  )
  select jsonb_build_object(
    'balanced',not exists(select 1 from bad),
    'unbalancedEntryCount',(select count(*) from bad),
    'unbalancedEntryIds',coalesce((select jsonb_agg(id) from bad),'[]'::jsonb),
    'invalidLineCount',coalesce((select sum(invalid_lines) from entries),0),
    'capitalizationLineCount',coalesce((select sum(capitalization_lines) from entries),0),
    'currencyMismatchLineCount',coalesce((select sum(currency_mismatch_lines) from entries),0)
  )
$$;

-- Preserve the older audit entry point with the stricter implementation.
create or replace function public.erp_v759_accounting_integrity_audit(p_company_id uuid)
returns jsonb language sql security definer set search_path=public as $$
  select public.erp_v761_accounting_integrity_audit(p_company_id)
$$;

revoke all on function public.erp_v761_reject_capitalization_journal_line() from public,anon;
grant execute on function public.erp_v761_is_credit_nature(text) to authenticated,service_role;
grant execute on function public.erp_v761_normal_balance(text,numeric,numeric,numeric) to authenticated,service_role;
grant execute on function public.erp_v761_accounting_integrity_audit(uuid) to authenticated,service_role;
notify pgrst,'reload schema';
commit;
