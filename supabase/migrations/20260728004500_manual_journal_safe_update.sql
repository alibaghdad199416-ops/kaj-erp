-- Atomic and validated editing for manual journal entries.
begin;

create or replace function public.erp_update_cloud_manual_journal(
  p_company_id uuid,
  p_entry jsonb,
  p_lines jsonb
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_entry_id text := nullif(btrim(p_entry->>'id'), '');
  v_currency text := upper(coalesce(nullif(btrim(p_entry->>'currency'), ''), ''));
  v_debit numeric := 0;
  v_credit numeric := 0;
  v_line jsonb;
  v_account_id text;
  v_account_currency text;
begin
  if not public.erp_is_company_member(p_company_id) then
    raise exception 'tenant denied';
  end if;
  if v_entry_id is null then raise exception 'entry id required'; end if;
  if v_currency not in ('USD','IQD') then raise exception 'invalid currency'; end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) < 2 then
    raise exception 'journal requires at least two lines';
  end if;
  if not exists (
    select 1 from public.erp_journal_entries
    where company_id=p_company_id and not is_deleted and data->>'id'=v_entry_id
  ) then raise exception 'journal entry not found'; end if;
  if coalesce(p_entry->>'referenceType','') <> '' then
    raise exception 'system generated journal cannot be edited manually';
  end if;

  for v_line in select value from jsonb_array_elements(p_lines) loop
    if v_line->>'entryId' <> v_entry_id then raise exception 'line entry mismatch'; end if;
    v_account_id := nullif(btrim(v_line->>'accountId'), '');
    if v_account_id is null then raise exception 'account required'; end if;
    select upper(coalesce(data->>'currency','')) into v_account_currency
    from public.erp_ledger_accounts
    where company_id=p_company_id and not is_deleted and data->>'id'=v_account_id
    limit 1;
    if v_account_currency is null then raise exception 'account not found'; end if;
    if v_account_currency not in (v_currency,'MULTI') then raise exception 'account currency mismatch'; end if;
    if coalesce((v_line->>'debit')::numeric,0) < 0 or coalesce((v_line->>'credit')::numeric,0) < 0 then
      raise exception 'negative journal amount';
    end if;
    if (coalesce((v_line->>'debit')::numeric,0) > 0) = (coalesce((v_line->>'credit')::numeric,0) > 0) then
      raise exception 'each line must have debit xor credit';
    end if;
    v_debit := v_debit + coalesce((v_line->>'debit')::numeric,0);
    v_credit := v_credit + coalesce((v_line->>'credit')::numeric,0);
  end loop;
  if v_debit <= 0 or abs(v_debit-v_credit) > 0.01 then raise exception 'journal is not balanced'; end if;

  update public.erp_journal_entries
  set data = p_entry || jsonb_build_object(
        'totalDebit', v_debit,
        'totalCredit', v_credit,
        'updatedAt', now()
      ), updated_at=now()
  where company_id=p_company_id and not is_deleted and data->>'id'=v_entry_id;

  update public.erp_journal_lines
  set is_deleted=true, updated_at=now()
  where company_id=p_company_id and not is_deleted and data->>'entryId'=v_entry_id;

  for v_line in select value from jsonb_array_elements(p_lines) loop
    insert into public.erp_journal_lines(company_id,id,data,is_deleted)
    values(
      p_company_id,
      coalesce(nullif(v_line->>'id','')::uuid, gen_random_uuid()),
      v_line,
      false
    );
  end loop;
end $$;

grant execute on function public.erp_update_cloud_manual_journal(uuid,jsonb,jsonb) to authenticated;
commit;
