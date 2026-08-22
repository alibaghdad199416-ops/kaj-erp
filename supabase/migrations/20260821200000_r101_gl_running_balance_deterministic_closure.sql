-- Quality Line ERP / KAJ ERP R101
-- Deterministic General Ledger running-balance closure.
--
-- Journal line created_at uses transaction time, so multiple lines written in
-- one journal transaction can share entry_date, entry.created_at and
-- line.created_at. The legacy window therefore had an incomplete ORDER BY and
-- could assign different intermediate running balances to tied lines. Preserve
-- every existing report path, but route General Ledger through a dedicated
-- engine with entry_id + line_id as stable final tie-breakers.
begin;

create or replace function public.erp_r101_cloud_general_ledger(
  p_company_id uuid,
  p_currency text default 'ALL',
  p_branch_id text default null,
  p_cost_center_id text default null,
  p_from_date timestamptz default null,
  p_to_date timestamptz default null
) returns setof jsonb
language plpgsql stable security definer
set search_path=public
as $$
begin
  if not public.is_active_company_member(p_company_id) then
    raise exception 'access denied' using errcode='42501';
  end if;

  return query
  with recursive account_tree as (
    select
      a.account_id,a.parent_account_id,a.code,a.name,a.account_type,
      a.currency,a.opening_balance,
      array[a.account_id]::text[] id_path,
      array[coalesce(a.name,'')]::text[] name_path,
      0 hierarchy_depth,
      a.code root_account_code,a.name root_account_name
    from public.erp_accounts a
    where a.organization_id=p_company_id and a.is_active
      and (
        a.parent_account_id is null
        or not exists(
          select 1 from public.erp_accounts parent
          where parent.organization_id=a.organization_id
            and parent.account_id=a.parent_account_id
            and parent.is_active
        )
      )
    union all
    select
      child.account_id,child.parent_account_id,child.code,child.name,
      child.account_type,child.currency,child.opening_balance,
      tree.id_path||child.account_id,
      tree.name_path||coalesce(child.name,''),
      tree.hierarchy_depth+1,
      tree.root_account_code,tree.root_account_name
    from public.erp_accounts child
    join account_tree tree
      on child.organization_id=p_company_id
     and child.parent_account_id=tree.account_id
    where child.is_active and not child.account_id=any(tree.id_path)
  ), all_lines as (
    select
      tree.*,
      je.id entry_id,
      jl.id line_id,
      upper(coalesce(nullif(je.data->>'currency',''),tree.currency)) line_currency,
      public.erp_try_timestamptz(je.data->>'entryDate',je.created_at) entry_date,
      coalesce(je.data->>'entryNumber',je.id) entry_number,
      coalesce(jl.data->>'description',je.data->>'description','') description,
      coalesce(je.data->>'partyName',je.data->>'counterpartyName','') party_name,
      coalesce(je.data->>'referenceType',je.data->>'sourceType','') reference_type,
      coalesce(je.data->>'referenceId',je.data->>'sourceId','') reference_id,
      public.erp_try_numeric(jl.data->>'debit',0::numeric) debit,
      public.erp_try_numeric(jl.data->>'credit',0::numeric) credit,
      case when tree.account_type in ('liability','equity','revenue')
        then public.erp_try_numeric(jl.data->>'credit',0::numeric)
           - public.erp_try_numeric(jl.data->>'debit',0::numeric)
        else public.erp_try_numeric(jl.data->>'debit',0::numeric)
           - public.erp_try_numeric(jl.data->>'credit',0::numeric)
      end natural_delta,
      je.created_at,
      jl.created_at line_created_at
    from public.erp_journal_lines jl
    join public.erp_journal_entries je
      on je.company_id=jl.company_id and je.id=jl.data->>'entryId'
    join account_tree tree on tree.account_id=jl.data->>'accountId'
    where jl.company_id=p_company_id
      and not jl.is_deleted and not je.is_deleted
      and lower(coalesce(je.data->>'status',je.data->>'postingStatus','posted'))
        in ('posted','approved','confirmed')
      and (
        upper(p_currency)='ALL'
        or upper(coalesce(nullif(je.data->>'currency',''),tree.currency))=upper(p_currency)
      )
      and (
        p_branch_id is null
        or coalesce(je.data->>'branchId',je.data->>'branch_id')=p_branch_id
      )
      and (
        p_cost_center_id is null
        or coalesce(
          jl.data->>'costCenterId',jl.data->>'cost_center_id',
          je.data->>'costCenterId',je.data->>'cost_center_id'
        )=p_cost_center_id
      )
      and (
        p_to_date is null
        or public.erp_try_timestamptz(je.data->>'entryDate',je.created_at)<=p_to_date
      )
  ), openings as (
    select
      account_id,line_currency,
      max(opening_balance)+coalesce(sum(natural_delta) filter(
        where p_from_date is not null and entry_date<p_from_date
      ),0) opening_natural
    from all_lines
    group by account_id,line_currency
  ), period_lines as (
    select
      line.*,
      coalesce(opening.opening_natural,line.opening_balance)
        + sum(line.natural_delta) over(
            partition by line.account_id,line.line_currency
            order by
              line.entry_date,
              line.created_at,
              line.line_created_at,
              line.entry_id,
              line.line_id
            rows between unbounded preceding and current row
          ) running_balance,
      coalesce(opening.opening_natural,line.opening_balance)
        opening_balance_for_period
    from all_lines line
    left join openings opening
      on opening.account_id=line.account_id
     and opening.line_currency=line.line_currency
    where p_from_date is null or line.entry_date>=p_from_date
  )
  select jsonb_build_object(
    'entryDate',entry_date,
    'entryNumber',entry_number,
    'accountId',account_id,
    'accountCode',code,
    'accountName',name,
    'accountType',account_type,
    'parentAccountId',parent_account_id,
    'rootAccountCode',coalesce(root_account_code,''),
    'rootAccountName',coalesce(root_account_name,''),
    'hierarchyPath',array_to_string(name_path,' / '),
    'hierarchyDepth',hierarchy_depth,
    'description',description,
    'partyName',party_name,
    'referenceType',reference_type,
    'referenceId',reference_id,
    'currency',line_currency,
    'openingBalance',opening_balance_for_period,
    'debit',debit,
    'credit',credit,
    'runningBalance',running_balance
  )
  from period_lines
  order by
    account_type,name_path,entry_date,created_at,line_created_at,entry_id,line_id;
end;
$$;

revoke all on function public.erp_r101_cloud_general_ledger(
  uuid,text,text,text,timestamptz,timestamptz
) from public,anon,authenticated;
grant execute on function public.erp_r101_cloud_general_ledger(
  uuid,text,text,text,timestamptz,timestamptz
) to service_role;

-- Browser keeps the stable R22 RPC. Trial Balance and every non-GL report still
-- flow through the existing R9-protected implementation. Only GL uses R101.
create or replace function public.erp_r22_cloud_detailed_accounting_report(
  p_company_id uuid,
  p_report_type text,
  p_currency text default 'ALL',
  p_branch_id text default null,
  p_cost_center_id text default null,
  p_from_date timestamptz default null,
  p_to_date timestamptz default null
) returns setof jsonb
language plpgsql stable security definer
set search_path=public
as $$
begin
  if lower(coalesce(p_report_type,''))='generalledger' then
    if not public.erp_cloud_user_can_view_field(
      p_company_id,'accounting','generalLedger','accounting.view'
    ) then
      raise exception 'field_permission_denied:accounting.generalLedger'
        using errcode='42501';
    end if;

    return query
      select public.erp_r9_filter_result_json(
        p_company_id,'accounting',row_data,null
      )
      from public.erp_r101_cloud_general_ledger(
        p_company_id,p_currency,p_branch_id,p_cost_center_id,p_from_date,p_to_date
      ) row_data;
    return;
  end if;

  return query
    select * from public.erp_r9_cloud_detailed_accounting_report(
      p_company_id,p_report_type,p_currency,p_branch_id,p_cost_center_id,
      p_from_date,p_to_date
    );
end;
$$;

revoke all on function public.erp_r22_cloud_detailed_accounting_report(
  uuid,text,text,text,text,timestamptz,timestamptz
) from public,anon;
grant execute on function public.erp_r22_cloud_detailed_accounting_report(
  uuid,text,text,text,text,timestamptz,timestamptz
) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
