begin;

-- R87.1 corrective closure:
-- R68/R86 financial-family maintenance may need to stamp durable linkage
-- metadata onto historical journal lines created before the current V7.6.3
-- posting schema existed. A metadata-only update must not be mistaken for a
-- new posting/edit of debit, credit, currency, or account identity.
--
-- Strict validation remains fail-closed for:
--   * every new live journal line;
--   * restoration of a deleted line;
--   * any change to accountId/account_id, debit, credit, or currency.
-- Deleting a line remains allowed by the existing soft-delete contract.

create or replace function public.erp_v763_validate_journal_line()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_debit numeric:=public.erp_try_numeric(new.data->>'debit',0);
  v_credit numeric:=public.erp_try_numeric(new.data->>'credit',0);
  v_account public.erp_accounts%rowtype;
  v_currency text;
begin
  if coalesce(new.is_deleted,false) then
    return new;
  end if;

  -- Historical rows may legitimately predate account/currency/side fields.
  -- Allow only a metadata-only update when the posting fingerprint is exactly
  -- unchanged. Any posting-field edit still falls through to full validation.
  if tg_op='UPDATE'
     and coalesce(old.is_deleted,false)=coalesce(new.is_deleted,false)
     and nullif(btrim(coalesce(old.data->>'accountId','')),'')
         is not distinct from nullif(btrim(coalesce(new.data->>'accountId','')),'')
     and coalesce(old.data->>'debit','') is not distinct from coalesce(new.data->>'debit','')
     and coalesce(old.data->>'credit','') is not distinct from coalesce(new.data->>'credit','')
     and upper(btrim(coalesce(old.data->>'currency','')))
         is not distinct from upper(btrim(coalesce(new.data->>'currency',''))) then
    return new;
  end if;

  if v_debit<0 or v_credit<0 or (v_debit=0 and v_credit=0)
     or (v_debit>0 and v_credit>0) then
    raise exception 'invalid_journal_line_sides';
  end if;

  select * into v_account
  from public.erp_accounts a
  where a.organization_id=new.company_id
    and a.account_id=new.data->>'accountId';

  if not found or not coalesce(v_account.is_active,false) then
    raise exception 'journal_account_inactive_or_missing';
  end if;
  if public.erp_v763_forbidden_capitalization_account(v_account.code,v_account.name) then
    raise exception 'capitalization_account_forbidden';
  end if;

  v_currency:=upper(btrim(coalesce(new.data->>'currency','')));
  if v_currency='' then
    raise exception 'journal_line_currency_required';
  end if;
  if v_currency<>upper(btrim(coalesce(v_account.currency,''))) then
    raise exception 'journal_line_account_currency_mismatch';
  end if;
  return new;
end;
$$;

create or replace function public.erp_r87_journal_line_postable_guard()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_account_id text;
begin
  if new.is_deleted then
    return new;
  end if;

  -- Keep header/control-account enforcement strict for every posting mutation,
  -- while allowing linkage/audit metadata to be stamped onto immutable legacy
  -- journal evidence without reclassifying that operation as a new posting.
  if tg_op='UPDATE'
     and coalesce(old.is_deleted,false)=coalesce(new.is_deleted,false)
     and nullif(btrim(coalesce(old.data->>'accountId',old.data->>'account_id','')),'')
         is not distinct from
         nullif(btrim(coalesce(new.data->>'accountId',new.data->>'account_id','')),'')
     and coalesce(old.data->>'debit','') is not distinct from coalesce(new.data->>'debit','')
     and coalesce(old.data->>'credit','') is not distinct from coalesce(new.data->>'credit','')
     and upper(btrim(coalesce(old.data->>'currency','')))
         is not distinct from upper(btrim(coalesce(new.data->>'currency',''))) then
    return new;
  end if;

  v_account_id:=nullif(
    btrim(coalesce(new.data->>'accountId',new.data->>'account_id','')),
    ''
  );
  if v_account_id is not null then
    perform public.erp_assert_postable_account(new.company_id,v_account_id);
  end if;
  return new;
end;
$$;

comment on function public.erp_v763_validate_journal_line() is
'Validates live journal posting fields while permitting metadata-only updates on immutable legacy journal evidence.';

comment on function public.erp_r87_journal_line_postable_guard() is
'Prevents header/control-account postings while permitting metadata-only updates that do not change the journal posting fingerprint.';

commit;
