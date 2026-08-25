-- 17.70.0: authoritative accounting integrity and reconciliation diagnostics.
begin;

create or replace function public.erp_assert_cloud_journal_balanced(
  p_company_id uuid,
  p_entry_id text
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_header public.erp_journal_entries%rowtype;
  v_lines integer;
  v_debit numeric;
  v_credit numeric;
  v_invalid integer;
begin
  select * into v_header
  from public.erp_journal_entries
  where company_id=p_company_id and id=p_entry_id and not is_deleted;

  -- Deleted/nonexistent headers are handled by the document deletion workflow.
  if not found then return; end if;
  if lower(coalesce(v_header.data->>'status','posted')) <> 'posted' then return; end if;

  select count(*),
         coalesce(sum(public.erp_try_numeric(data->>'debit',0)),0),
         coalesce(sum(public.erp_try_numeric(data->>'credit',0)),0),
         count(*) filter (
           where public.erp_try_numeric(data->>'debit',0) < 0
              or public.erp_try_numeric(data->>'credit',0) < 0
              or (public.erp_try_numeric(data->>'debit',0) > 0 and public.erp_try_numeric(data->>'credit',0) > 0)
              or (public.erp_try_numeric(data->>'debit',0) = 0 and public.erp_try_numeric(data->>'credit',0) = 0)
         )
    into v_lines,v_debit,v_credit,v_invalid
  from public.erp_journal_lines
  where company_id=p_company_id and not is_deleted and data->>'entryId'=p_entry_id;

  if v_lines < 2 then raise exception 'القيد المرحل يجب أن يحتوي على سطرين على الأقل'; end if;
  if v_invalid > 0 then raise exception 'أحد أسطر القيد يحتوي على قيم مدينة أو دائنة غير صحيحة'; end if;
  if v_debit <= 0 or abs(v_debit-v_credit) > 0.01 then
    raise exception 'القيد المرحل غير متوازن: المدين % والدائن %',v_debit,v_credit;
  end if;
end
$$;

create or replace function public.erp_deferred_journal_integrity_trigger()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if tg_table_name='erp_journal_lines' then
    if tg_op in ('UPDATE','DELETE') and nullif(old.data->>'entryId','') is not null then
      perform public.erp_assert_cloud_journal_balanced(old.company_id,old.data->>'entryId');
    end if;
    if tg_op in ('INSERT','UPDATE') and nullif(new.data->>'entryId','') is not null then
      perform public.erp_assert_cloud_journal_balanced(new.company_id,new.data->>'entryId');
    end if;
  else
    if tg_op in ('INSERT','UPDATE') then
      perform public.erp_assert_cloud_journal_balanced(new.company_id,new.id);
    end if;
  end if;
  return null;
end
$$;

drop trigger if exists erp_journal_lines_balanced_deferred on public.erp_journal_lines;
create constraint trigger erp_journal_lines_balanced_deferred
after insert or update or delete on public.erp_journal_lines
deferrable initially deferred
for each row execute function public.erp_deferred_journal_integrity_trigger();

drop trigger if exists erp_journal_entries_balanced_deferred on public.erp_journal_entries;
create constraint trigger erp_journal_entries_balanced_deferred
after insert or update on public.erp_journal_entries
deferrable initially deferred
for each row execute function public.erp_deferred_journal_integrity_trigger();

create or replace function public.erp_accounting_integrity_health(p_company_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_unbalanced integer;
  v_orphan_lines integer;
  v_missing_accounts integer;
  v_duplicate_numbers integer;
  v_unlinked_sales integer:=0;
  v_unlinked_purchases integer:=0;
begin
  if not public.is_active_company_member(p_company_id) then raise exception 'access denied'; end if;

  with totals as (
    select je.id,
      count(jl.id) as line_count,
      coalesce(sum(public.erp_try_numeric(jl.data->>'debit',0)),0) debit,
      coalesce(sum(public.erp_try_numeric(jl.data->>'credit',0)),0) credit
    from public.erp_journal_entries je
    left join public.erp_journal_lines jl on jl.company_id=je.company_id
      and jl.data->>'entryId'=je.id and not jl.is_deleted
    where je.company_id=p_company_id and not je.is_deleted
      and lower(coalesce(je.data->>'status','posted'))='posted'
    group by je.id
  ) select count(*) into v_unbalanced from totals
    where line_count<2 or debit<=0 or abs(debit-credit)>0.01;

  select count(*) into v_orphan_lines
  from public.erp_journal_lines jl
  where jl.company_id=p_company_id and not jl.is_deleted
    and not exists(select 1 from public.erp_journal_entries je
      where je.company_id=jl.company_id and je.id=jl.data->>'entryId' and not je.is_deleted);

  select count(*) into v_missing_accounts
  from public.erp_journal_lines jl
  where jl.company_id=p_company_id and not jl.is_deleted
    and not exists(select 1 from public.erp_accounts a
      where a.organization_id=jl.company_id and a.account_id=jl.data->>'accountId');

  select count(*) into v_duplicate_numbers from (
    select lower(data->>'entryNumber')
    from public.erp_journal_entries
    where company_id=p_company_id and not is_deleted
      and nullif(trim(data->>'entryNumber'),'') is not null
    group by lower(data->>'entryNumber') having count(*)>1
  ) d;

  if to_regclass('public.erp_sales') is not null then
    execute $q$select count(*) from public.erp_sales
      where company_id=$1 and not is_deleted
        and lower(coalesce(data->>'status','')) in ('posted','approved','completed')
        and nullif(coalesce(data->>'journalEntryId',data->>'journal_entry_id'),'') is null$q$
      into v_unlinked_sales using p_company_id;
  end if;
  if to_regclass('public.erp_purchases') is not null then
    execute $q$select count(*) from public.erp_purchases
      where company_id=$1 and not is_deleted
        and lower(coalesce(data->>'status','')) in ('posted','approved','completed')
        and nullif(coalesce(data->>'journalEntryId',data->>'journal_entry_id'),'') is null$q$
      into v_unlinked_purchases using p_company_id;
  end if;

  return jsonb_build_object(
    'ok',(v_unbalanced+v_orphan_lines+v_missing_accounts+v_duplicate_numbers+v_unlinked_sales+v_unlinked_purchases)=0,
    'company_id',p_company_id,
    'checked_at',now(),
    'unbalanced_entries',v_unbalanced,
    'orphan_lines',v_orphan_lines,
    'missing_accounts',v_missing_accounts,
    'duplicate_entry_numbers',v_duplicate_numbers,
    'posted_sales_without_journal',v_unlinked_sales,
    'posted_purchases_without_journal',v_unlinked_purchases
  );
end
$$;

grant execute on function public.erp_assert_cloud_journal_balanced(uuid,text) to authenticated;
grant execute on function public.erp_accounting_integrity_health(uuid) to authenticated;

commit;
