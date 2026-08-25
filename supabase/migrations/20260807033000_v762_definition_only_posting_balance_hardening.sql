begin;

-- V7.6.2: final definition-only operational posting and ledger balance hardening.
-- No sales, purchase, maintenance, or expense workflow may post to a
-- capitalization account. Debit/credit validation is enforced at line level,
-- and report account natures are normalized consistently.

create or replace function public.erp_v762_account_family(p_account_type text)
returns text language sql immutable as $$
  select case lower(btrim(coalesce(p_account_type,'')))
    when 'receivable' then 'asset'
    when 'cash' then 'asset'
    when 'bank' then 'asset'
    when 'inventory' then 'asset'
    when 'fixed_asset' then 'asset'
    when 'clearing' then 'asset'
    when 'cost' then 'expense'
    when 'cogs' then 'expense'
    when 'payable' then 'liability'
    when 'income' then 'revenue'
    else case when lower(btrim(coalesce(p_account_type,''))) in
      ('asset','liability','equity','revenue','expense')
      then lower(btrim(p_account_type)) else 'asset' end
  end
$$;

create or replace function public.erp_v761_is_credit_nature(p_account_type text)
returns boolean language sql immutable as $$
  select public.erp_v762_account_family(p_account_type) in
    ('liability','equity','revenue')
$$;

create or replace function public.erp_v761_normal_balance(
  p_account_type text,p_opening numeric,p_debit numeric,p_credit numeric
) returns numeric language sql immutable as $$
  select case when public.erp_v761_is_credit_nature(p_account_type)
    then coalesce(p_opening,0)+coalesce(p_credit,0)-coalesce(p_debit,0)
    else coalesce(p_opening,0)+coalesce(p_debit,0)-coalesce(p_credit,0)
  end
$$;

create or replace function public.erp_v762_validate_journal_line()
returns trigger language plpgsql security definer set search_path=public as $$
declare
  v_debit numeric:=public.erp_try_numeric(new.data->>'debit',0);
  v_credit numeric:=public.erp_try_numeric(new.data->>'credit',0);
  v_account public.erp_accounts%rowtype;
  v_currency text;
begin
  if coalesce(new.is_deleted,false) then return new; end if;
  if v_debit<0 or v_credit<0 or (v_debit=0 and v_credit=0)
     or (v_debit>0 and v_credit>0) then
    raise exception 'invalid_journal_line_sides';
  end if;

  select * into v_account from public.erp_accounts a
   where a.organization_id=new.company_id
     and a.account_id=new.data->>'accountId';
  if not found or not coalesce(v_account.is_active,false) then
    raise exception 'journal_account_inactive_or_missing';
  end if;
  if v_account.code in ('1391','1392')
     or lower(coalesce(v_account.name,'')) like '%capitalization%'
     or coalesce(v_account.name,'') like '%رسمل%' then
    raise exception 'capitalization_account_forbidden';
  end if;

  v_currency:=upper(coalesce(new.data->>'currency',''));
  if v_currency='' then raise exception 'journal_line_currency_required'; end if;
  if v_currency<>upper(coalesce(v_account.currency,'')) then
    raise exception 'journal_line_account_currency_mismatch';
  end if;
  return new;
end;
$$;

drop trigger if exists erp_journal_lines_no_capitalization on public.erp_journal_lines;
drop trigger if exists erp_journal_lines_validate_sides_currency on public.erp_journal_lines;
create trigger erp_journal_lines_validate_sides_currency
before insert or update of data,is_deleted on public.erp_journal_lines
for each row execute function public.erp_v762_validate_journal_line();

-- Ensure obsolete capitalization accounts are either deleted (unused) or
-- retained only as inactive historical masters.
delete from public.erp_accounts a
 where (a.code in ('1391','1392')
    or lower(coalesce(a.name,'')) like '%capitalization%'
    or coalesce(a.name,'') like '%رسمل%')
   and not exists (
     select 1 from public.erp_journal_lines jl
      where jl.company_id=a.organization_id
        and jl.data->>'accountId'=a.account_id
        and not jl.is_deleted
   );
update public.erp_accounts
   set is_active=false,
       name='حساب تاريخي متوقف - ممنوع الاستخدام',
       source_updated_at=now(),synced_at=now(),synced_by=auth.uid()
 where code in ('1391','1392')
    or lower(coalesce(name,'')) like '%capitalization%'
    or coalesce(name,'') like '%رسمل%';

create or replace function public.erp_cloud_account_statement(
  p_company_id uuid,p_account_id text,p_from_date timestamptz,p_to_date timestamptz
) returns table(
  "entryId" text,"entryNumber" text,"entryDate" text,
  "entryDescription" text,currency text,"lineDescription" text,
  debit numeric,credit numeric
) language sql security definer set search_path=public as $$
 select je.id,je.data->>'entryNumber',je.data->>'entryDate',
        je.data->>'description',
        upper(coalesce(jl.data->>'currency',je.data->>'currency','')),
        jl.data->>'description',
        public.erp_try_numeric(jl.data->>'debit',0),
        public.erp_try_numeric(jl.data->>'credit',0)
 from public.erp_journal_lines jl
 join public.erp_journal_entries je
   on je.company_id=jl.company_id and je.id=jl.data->>'entryId'
 where jl.company_id=p_company_id
   and public.is_active_company_member(p_company_id)
   and not jl.is_deleted and not je.is_deleted
   and lower(coalesce(je.data->>'status',je.data->>'postingStatus',''))
       in ('posted','approved','confirmed')
   and jl.data->>'accountId'=p_account_id
   and coalesce(nullif(je.data->>'entryDate','')::timestamptz,je.created_at)
       between p_from_date and p_to_date
 order by coalesce(nullif(je.data->>'entryDate','')::timestamptz,je.created_at),
          je.created_at,jl.created_at
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
    where jl.company_id=p_company_id
      and not jl.is_deleted and not je.is_deleted
      and lower(coalesce(je.data->>'status',je.data->>'postingStatus',''))
          in ('posted','approved','confirmed')
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

create or replace function public.erp_v762_accounting_integrity_audit(p_company_id uuid)
returns jsonb language sql security definer set search_path=public as $$
  with entries as (
    select je.id,
      public.erp_try_numeric(je.data->>'totalDebit',0) header_debit,
      public.erp_try_numeric(je.data->>'totalCredit',0) header_credit,
      coalesce(sum(public.erp_try_numeric(jl.data->>'debit',0)),0) lines_debit,
      coalesce(sum(public.erp_try_numeric(jl.data->>'credit',0)),0) lines_credit,
      count(*) filter(where public.erp_try_numeric(jl.data->>'debit',0)<0
        or public.erp_try_numeric(jl.data->>'credit',0)<0
        or (public.erp_try_numeric(jl.data->>'debit',0)=0
            and public.erp_try_numeric(jl.data->>'credit',0)=0)
        or (public.erp_try_numeric(jl.data->>'debit',0)>0
            and public.erp_try_numeric(jl.data->>'credit',0)>0)) invalid_lines,
      count(*) filter(where a.code in ('1391','1392')
        or lower(coalesce(a.name,'')) like '%capitalization%'
        or coalesce(a.name,'') like '%رسمل%') capitalization_lines,
      count(*) filter(where upper(coalesce(jl.data->>'currency',''))
        <> upper(coalesce(a.currency,''))) currency_mismatch_lines
    from public.erp_journal_entries je
    left join public.erp_journal_lines jl
      on jl.company_id=je.company_id and jl.data->>'entryId'=je.id and not jl.is_deleted
    left join public.erp_accounts a
      on a.organization_id=jl.company_id and a.account_id=jl.data->>'accountId'
    where je.company_id=p_company_id and not je.is_deleted
      and lower(coalesce(je.data->>'status',je.data->>'postingStatus',''))
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

revoke all on function public.erp_v762_validate_journal_line() from public,anon;
grant execute on function public.erp_v762_account_family(text) to authenticated,service_role;
grant execute on function public.erp_v762_accounting_integrity_audit(uuid) to authenticated,service_role;
grant execute on function public.erp_cloud_account_statement(uuid,text,timestamptz,timestamptz) to authenticated,service_role;
grant execute on function public.erp_cloud_trial_balance(uuid,text) to authenticated,service_role;
notify pgrst,'reload schema';
commit;
