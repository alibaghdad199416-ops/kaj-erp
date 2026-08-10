-- R23: one current cashbox ledger identity. Legacy accountId/account_id drift
-- may not alter reconciliation or future postings.
create or replace function public.erp_r23_cashbox_ledger_account_id(p_data jsonb)
returns text language sql immutable set search_path=public
as $$ select nullif(btrim(coalesce($1->>'account_id',$1->>'accountId','')),'') $$;

-- Normalize existing rows deterministically: current normalized account_id wins
-- when it resolves to an active ledger account in the cashbox currency.
do $$
declare r record; v_ledger text;
begin
  for r in
    select ca.company_id,ca.id,ca.data,
           nullif(btrim(ca.data->>'account_id'),'') snake_id,
           nullif(btrim(ca.data->>'accountId'),'') camel_id,
           upper(coalesce(ca.data->>'currency','')) cash_currency
    from public.erp_cash_accounts ca where not ca.is_deleted
  loop
    v_ledger:=null;
    if r.snake_id is not null and exists(
      select 1 from public.erp_accounts a where a.organization_id=r.company_id
        and a.account_id=r.snake_id and a.is_active
        and upper(coalesce(a.currency,'')) in (r.cash_currency,'MULTI')
    ) then v_ledger:=r.snake_id;
    elsif r.camel_id is not null and exists(
      select 1 from public.erp_accounts a where a.organization_id=r.company_id
        and a.account_id=r.camel_id and a.is_active
        and upper(coalesce(a.currency,'')) in (r.cash_currency,'MULTI')
    ) then v_ledger:=r.camel_id;
    end if;
    if v_ledger is not null then
      update public.erp_cash_accounts ca
      set data=jsonb_set(jsonb_set(ca.data,'{accountId}',to_jsonb(v_ledger),true),'{account_id}',to_jsonb(v_ledger),true),
          version=ca.version+1,updated_at=now(),updated_by=auth.uid()
      where ca.company_id=r.company_id and ca.id=r.id
        and (ca.data->>'accountId' is distinct from v_ledger or ca.data->>'account_id' is distinct from v_ledger);
    end if;
  end loop;
end $$;

create or replace function public.erp_r23_sync_cashbox_ledger_aliases()
returns trigger language plpgsql set search_path=public
as $$
declare
  v_snake text:=nullif(btrim(new.data->>'account_id'),'');
  v_camel text:=nullif(btrim(new.data->>'accountId'),'');
  v_old_snake text; v_old_camel text; v_ledger text;
begin
  if tg_op='UPDATE' then
    v_old_snake:=nullif(btrim(old.data->>'account_id'),'');
    v_old_camel:=nullif(btrim(old.data->>'accountId'),'');
    if v_snake is distinct from v_old_snake and v_camel is not distinct from v_old_camel then v_ledger:=v_snake;
    elsif v_camel is distinct from v_old_camel and v_snake is not distinct from v_old_snake then v_ledger:=v_camel;
    else v_ledger:=coalesce(v_snake,v_camel);
    end if;
  else v_ledger:=coalesce(v_snake,v_camel);
  end if;
  if v_ledger is not null then
    new.data:=jsonb_set(jsonb_set(new.data,'{accountId}',to_jsonb(v_ledger),true),'{account_id}',to_jsonb(v_ledger),true);
  end if;
  return new;
end $$;

drop trigger if exists trg_r23_sync_cashbox_ledger_aliases on public.erp_cash_accounts;
create trigger trg_r23_sync_cashbox_ledger_aliases
before insert or update of data on public.erp_cash_accounts
for each row execute function public.erp_r23_sync_cashbox_ledger_aliases();

create or replace function public.erp_cloud_cash_ledger_reconciliation(p_company_id uuid)
returns table(cash_account_id text,cash_account_name text,currency text,subledger_balance numeric,ledger_balance numeric,difference numeric)
language sql security definer set search_path=public
as $$
  with cash as (
    select ca.id,ca.data->>'name' name,upper(coalesce(ca.data->>'currency','')) currency,
      public.erp_r23_cashbox_ledger_account_id(ca.data) ledger_account_id,
      public.erp_try_numeric(coalesce(ca.data->>'openingBalance',ca.data->>'opening_balance'),0)
      +coalesce(sum(case
        when lower(coalesce(ct.data->>'type','')) in ('receipt','income','in','cash_in','customer_receipt','transfer_in') then abs(public.erp_try_numeric(ct.data->>'amount',0))
        when lower(coalesce(ct.data->>'type','')) in ('payment','expense','out','cash_out','supplier_payment','transfer_out') then -abs(public.erp_try_numeric(ct.data->>'amount',0))
        else 0 end),0) subledger_balance
    from public.erp_cash_accounts ca
    left join public.erp_cash_transactions ct on ct.company_id=ca.company_id and not ct.is_deleted
      and coalesce(ct.data->>'cashAccountId',ct.data->>'cash_account_id')=ca.id
    where ca.company_id=p_company_id and not ca.is_deleted and public.is_active_company_member(p_company_id)
    group by ca.id,ca.data
  ), ledger as (
    select a.account_id,coalesce(a.opening_balance,0)
      +coalesce(sum(case when je.id is not null then public.erp_try_numeric(jl.data->>'debit',0)-public.erp_try_numeric(jl.data->>'credit',0) else 0 end),0) ledger_balance
    from public.erp_accounts a
    left join public.erp_journal_lines jl on jl.company_id=a.organization_id and jl.data->>'accountId'=a.account_id and not jl.is_deleted
    left join public.erp_journal_entries je on je.company_id=jl.company_id and je.id=jl.data->>'entryId'
      and not je.is_deleted and lower(coalesce(je.data->>'status',je.data->>'postingStatus','posted')) in ('posted','approved','confirmed')
    where a.organization_id=p_company_id and a.is_active and public.is_active_company_member(p_company_id)
    group by a.account_id,a.opening_balance
  )
  select c.id,c.name,c.currency,c.subledger_balance,coalesce(l.ledger_balance,0),c.subledger_balance-coalesce(l.ledger_balance,0)
  from cash c left join ledger l on l.account_id=c.ledger_account_id
  order by c.currency,c.name;
$$;

grant execute on function public.erp_r23_cashbox_ledger_account_id(jsonb) to authenticated,service_role;
notify pgrst,'reload schema';
