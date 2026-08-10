begin;

-- Repair reciprocal links from both the link table and cashbox JSON aliases.
insert into public.erp_cash_account_links(company_id,source_cash_account_id,target_cash_account_id,created_by,updated_by)
select c.company_id,c.id,nullif(coalesce(c.data->>'linked_cash_account_id',c.data->>'linkedCashAccountId'),'')::text,c.updated_by,c.updated_by
from public.erp_cash_accounts c
where not c.is_deleted and nullif(coalesce(c.data->>'linked_cash_account_id',c.data->>'linkedCashAccountId'),'') is not null
on conflict(company_id,source_cash_account_id) do update set target_cash_account_id=excluded.target_cash_account_id,updated_at=now(),updated_by=excluded.updated_by;

insert into public.erp_cash_account_links(company_id,source_cash_account_id,target_cash_account_id,created_by,updated_by)
select l.company_id,l.target_cash_account_id,l.source_cash_account_id,l.created_by,l.updated_by
from public.erp_cash_account_links l
join public.erp_cash_accounts s on s.company_id=l.company_id and s.id=l.source_cash_account_id and not s.is_deleted
join public.erp_cash_accounts t on t.company_id=l.company_id and t.id=l.target_cash_account_id and not t.is_deleted
where upper(coalesce(s.data->>'currency',''))<>upper(coalesce(t.data->>'currency',''))
on conflict(company_id,source_cash_account_id) do update set target_cash_account_id=excluded.target_cash_account_id,updated_at=now(),updated_by=excluded.updated_by;

update public.erp_cash_accounts c set data=jsonb_set(jsonb_set(c.data,'{linkedCashAccountId}',to_jsonb(l.target_cash_account_id),true),'{linked_cash_account_id}',to_jsonb(l.target_cash_account_id),true),version=c.version+1,updated_at=now()
from public.erp_cash_account_links l where c.company_id=l.company_id and c.id=l.source_cash_account_id and not c.is_deleted
  and nullif(coalesce(c.data->>'linked_cash_account_id',c.data->>'linkedCashAccountId'),'') is distinct from l.target_cash_account_id;

create or replace function public.erp_resolve_linked_cash_account(p_company_id uuid,p_source_cash_account_id text,p_target_currency text)
returns text language plpgsql security definer set search_path=public as $$
declare v_target text; v_currency text:=upper(p_target_currency);
begin
  select candidate.id into v_target from (
    select l.target_cash_account_id id,1 priority from public.erp_cash_account_links l
      where l.company_id=p_company_id and l.source_cash_account_id=p_source_cash_account_id
    union all
    select l.source_cash_account_id id,2 priority from public.erp_cash_account_links l
      where l.company_id=p_company_id and l.target_cash_account_id=p_source_cash_account_id
    union all
    select nullif(coalesce(s.data->>'linked_cash_account_id',s.data->>'linkedCashAccountId'),'') id,3 priority
      from public.erp_cash_accounts s where s.company_id=p_company_id and s.id=p_source_cash_account_id and not s.is_deleted
    union all
    select t.id,4 priority from public.erp_cash_accounts t
      where t.company_id=p_company_id and not t.is_deleted
        and nullif(coalesce(t.data->>'linked_cash_account_id',t.data->>'linkedCashAccountId'),'')=p_source_cash_account_id
  ) candidate
  join public.erp_cash_accounts c on c.company_id=p_company_id and c.id=candidate.id and not c.is_deleted
  where candidate.id is not null
    and public.erp_try_boolean(coalesce(c.data->>'isActive',c.data->>'is_active'),'true')
    and upper(coalesce(c.data->>'currency',''))=v_currency
  order by candidate.priority limit 1;
  return v_target;
end $$;

grant execute on function public.erp_resolve_linked_cash_account(uuid,text,text) to authenticated,service_role;
commit;
