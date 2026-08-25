begin;

-- V7.5.9: operational workflows never use capitalization accounts.
-- Historical accounts cannot be deleted safely when journal lines reference them;
-- they are converted to hidden FX bridge accounts and excluded from ordinary UI use.

create or replace function public.erp_v759_normal_balance(
  p_account_type text,
  p_opening numeric,
  p_debit numeric,
  p_credit numeric
) returns numeric
language sql immutable as $$
  select case
    when lower(coalesce(p_account_type,'')) in ('liability','equity','revenue')
      then coalesce(p_opening,0)+coalesce(p_credit,0)-coalesce(p_debit,0)
    else coalesce(p_opening,0)+coalesce(p_debit,0)-coalesce(p_credit,0)
  end
$$;

create or replace function public.erp_cloud_trial_balance(
  p_company_id uuid,
  p_currency text
) returns jsonb
language sql security definer set search_path=public as $$
  with totals as (
    select a.account_id,a.account_type,coalesce(a.opening_balance,0) opening_balance,
      coalesce(sum(public.erp_try_numeric(jl.data->>'debit',0)) filter(where je.id is not null),0) movement_debit,
      coalesce(sum(public.erp_try_numeric(jl.data->>'credit',0)) filter(where je.id is not null),0) movement_credit
    from public.erp_accounts a
    left join public.erp_journal_lines jl on jl.company_id=a.organization_id
      and jl.data->>'accountId'=a.account_id and not jl.is_deleted
    left join public.erp_journal_entries je on je.company_id=jl.company_id
      and je.id=jl.data->>'entryId' and not je.is_deleted
      and lower(coalesce(je.data->>'status',je.data->>'postingStatus','posted')) in ('posted','approved','confirmed')
      and upper(coalesce(je.data->>'currency',a.currency))=upper(p_currency)
    where a.organization_id=p_company_id and a.is_active
      and upper(a.currency)=upper(p_currency)
      and public.is_active_company_member(p_company_id)
    group by a.account_id,a.account_type,a.opening_balance
  ), balances as (
    select *,public.erp_v759_normal_balance(account_type,opening_balance,movement_debit,movement_credit) normal_balance
    from totals
  )
  select jsonb_build_object(
    'debit',coalesce(sum(case when account_type not in ('liability','equity','revenue') then greatest(normal_balance,0) else greatest(-normal_balance,0) end),0),
    'credit',coalesce(sum(case when account_type in ('liability','equity','revenue') then greatest(normal_balance,0) else greatest(-normal_balance,0) end),0),
    'movementDebit',coalesce(sum(movement_debit),0),
    'movementCredit',coalesce(sum(movement_credit),0),
    'difference',abs(
      coalesce(sum(case when account_type not in ('liability','equity','revenue') then greatest(normal_balance,0) else greatest(-normal_balance,0) end),0)
      -coalesce(sum(case when account_type in ('liability','equity','revenue') then greatest(normal_balance,0) else greatest(-normal_balance,0) end),0)
    )
  ) from balances;
$$;

create or replace function public.erp_v759_accounting_integrity_audit(p_company_id uuid)
returns jsonb language sql security definer set search_path=public as $$
  with entries as (
    select je.id,
      public.erp_try_numeric(je.data->>'totalDebit',0) header_debit,
      public.erp_try_numeric(je.data->>'totalCredit',0) header_credit,
      coalesce(sum(public.erp_try_numeric(jl.data->>'debit',0)),0) lines_debit,
      coalesce(sum(public.erp_try_numeric(jl.data->>'credit',0)),0) lines_credit
    from public.erp_journal_entries je
    left join public.erp_journal_lines jl on jl.company_id=je.company_id
      and jl.data->>'entryId'=je.id and not jl.is_deleted
    where je.company_id=p_company_id and not je.is_deleted
      and lower(coalesce(je.data->>'status',je.data->>'postingStatus','posted')) in ('posted','approved','confirmed')
    group by je.id,je.data
  ), bad as (
    select * from entries where abs(lines_debit-lines_credit)>0.01
      or (header_debit>0 and abs(header_debit-lines_debit)>0.01)
      or (header_credit>0 and abs(header_credit-lines_credit)>0.01)
  )
  select jsonb_build_object(
    'balanced',not exists(select 1 from bad),
    'unbalancedEntryCount',(select count(*) from bad),
    'unbalancedEntryIds',coalesce((select jsonb_agg(id) from bad),'[]'::jsonb)
  )
$$;

grant execute on function public.erp_v759_normal_balance(text,numeric,numeric,numeric) to authenticated;
grant execute on function public.erp_cloud_trial_balance(uuid,text) to authenticated;
grant execute on function public.erp_v759_accounting_integrity_audit(uuid) to authenticated;

-- Retire capitalization nomenclature. Referenced historical accounts are retained
-- only as hidden technical FX bridge accounts; no automatic asset capitalization is performed.
update public.erp_accounts
set name=case upper(currency)
  when 'USD' then 'جسر تحويل مشتريات متعدد العملات - دولار'
  else 'جسر تحويل مشتريات متعدد العملات - دينار' end,
  is_active=true,
  source_updated_at=now()
where code in ('1391','1392')
  and (lower(name) like '%capital%' or name like '%رسمل%');

-- Remove capitalization labels from live master-data JSON without changing historical journal text.
update public.erp_accounts
set name=replace(replace(name,'رسملة','ربط عملات'),'Capitalization','FX Bridge'),source_updated_at=now()
where name like '%رسملة%' or lower(name) like '%capitalization%';

notify pgrst,'reload schema';
commit;
