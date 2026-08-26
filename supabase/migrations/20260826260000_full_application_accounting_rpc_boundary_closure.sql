begin;

-- Independent audit continuation: V7.6.3 introduced authenticated
-- SECURITY DEFINER accounting readers without a complete tenant boundary.
-- The audit endpoint could inspect another company's journal state because it
-- trusted only the caller-supplied company id. The trial-balance endpoint
-- returned a zero/healthy-looking result for a non-member rather than denying
-- the request. Close both RPC boundaries without changing their signatures.

create or replace function public.erp_v763_accounting_integrity_audit(p_company_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_result jsonb;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;

  select jsonb_build_object(
    'balanced',not exists(
      select 1
      from (
        select je.id,
          public.erp_try_numeric(je.data->>'totalDebit',0) header_debit,
          public.erp_try_numeric(je.data->>'totalCredit',0) header_credit,
          coalesce(sum(public.erp_try_numeric(jl.data->>'debit',0)),0) lines_debit,
          coalesce(sum(public.erp_try_numeric(jl.data->>'credit',0)),0) lines_credit,
          count(*) filter(where jl.id is not null and (
            public.erp_try_numeric(jl.data->>'debit',0)<0
            or public.erp_try_numeric(jl.data->>'credit',0)<0
            or (public.erp_try_numeric(jl.data->>'debit',0)=0 and public.erp_try_numeric(jl.data->>'credit',0)=0)
            or (public.erp_try_numeric(jl.data->>'debit',0)>0 and public.erp_try_numeric(jl.data->>'credit',0)>0))) invalid_lines,
          count(*) filter(where jl.id is not null and a.account_id is null) orphan_account_lines,
          count(*) filter(where jl.id is not null and a.account_id is not null and not coalesce(a.is_active,false)) inactive_account_lines,
          count(*) filter(where jl.id is not null and public.erp_v763_forbidden_capitalization_account(a.code,a.name)) capitalization_lines,
          count(*) filter(where jl.id is not null and upper(coalesce(jl.data->>'currency',''))<>upper(coalesce(a.currency,''))) currency_mismatch_lines
        from public.erp_journal_entries je
        left join public.erp_journal_lines jl on jl.company_id=je.company_id and jl.data->>'entryId'=je.id and not jl.is_deleted
        left join public.erp_accounts a on a.organization_id=jl.company_id and a.account_id=jl.data->>'accountId'
        where je.company_id=p_company_id and not je.is_deleted
          and lower(coalesce(je.data->>'status',je.data->>'postingStatus','')) in ('posted','approved','confirmed')
        group by je.id,je.data
      ) entries
      where abs(lines_debit-lines_credit)>0.01
        or invalid_lines>0 or orphan_account_lines>0 or inactive_account_lines>0
        or capitalization_lines>0 or currency_mismatch_lines>0
        or abs(header_debit-header_credit)>0.01
        or (header_debit>0 and abs(header_debit-lines_debit)>0.01)
        or (header_credit>0 and abs(header_credit-lines_credit)>0.01)
    ),
    'companyId',p_company_id,
    'status','ok'
  ) into v_result;

  return v_result;
end;
$$;

-- The trial-balance result is already tenant-filtered, but a non-member must
-- receive an authorization error rather than an empty balanced report.
create or replace function public.erp_cloud_trial_balance(p_company_id uuid,p_currency text)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_result jsonb;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;

  with line_totals as (
    select jl.data->>'accountId' account_id,
      coalesce(sum(public.erp_try_numeric(jl.data->>'debit',0)),0) movement_debit,
      coalesce(sum(public.erp_try_numeric(jl.data->>'credit',0)),0) movement_credit
    from public.erp_journal_lines jl
    join public.erp_journal_entries je on je.company_id=jl.company_id and je.id=jl.data->>'entryId'
    where jl.company_id=p_company_id and not jl.is_deleted and not je.is_deleted
      and lower(coalesce(je.data->>'status',je.data->>'postingStatus','')) in ('posted','approved','confirmed')
      and upper(coalesce(jl.data->>'currency',je.data->>'currency',''))=upper(p_currency)
    group by jl.data->>'accountId'
  ), balances as (
    select a.account_id,a.account_type,coalesce(a.opening_balance,0) opening_balance,
      coalesce(l.movement_debit,0) movement_debit,coalesce(l.movement_credit,0) movement_credit,
      public.erp_v761_normal_balance(a.account_type,a.opening_balance,l.movement_debit,l.movement_credit) natural_balance
    from public.erp_accounts a
    left join line_totals l on l.account_id=a.account_id
    where a.organization_id=p_company_id and a.is_active and upper(a.currency)=upper(p_currency)
  ), sides as (
    select *,
      case when public.erp_v761_is_credit_nature(account_type) then greatest(-natural_balance,0) else greatest(natural_balance,0) end closing_debit,
      case when public.erp_v761_is_credit_nature(account_type) then greatest(natural_balance,0) else greatest(-natural_balance,0) end closing_credit
    from balances
  ), totals as (
    select coalesce(sum(closing_debit),0) debit,coalesce(sum(closing_credit),0) credit,
      coalesce(sum(movement_debit),0) movement_debit,coalesce(sum(movement_credit),0) movement_credit
    from sides
  )
  select jsonb_build_object(
    'currency',upper(p_currency),'debit',debit,'credit',credit,
    'movementDebit',movement_debit,'movementCredit',movement_credit,
    'difference',debit-credit,'absoluteDifference',abs(debit-credit),
    'movementDifference',movement_debit-movement_credit,
    'balanced',abs(debit-credit)<=0.01 and abs(movement_debit-movement_credit)<=0.01
  ) into v_result from totals;

  return v_result;
end;
$$;

revoke all on function public.erp_v763_accounting_integrity_audit(uuid) from public,anon;
grant execute on function public.erp_v763_accounting_integrity_audit(uuid) to authenticated,service_role;
revoke all on function public.erp_cloud_trial_balance(uuid,text) from public,anon;
grant execute on function public.erp_cloud_trial_balance(uuid,text) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
