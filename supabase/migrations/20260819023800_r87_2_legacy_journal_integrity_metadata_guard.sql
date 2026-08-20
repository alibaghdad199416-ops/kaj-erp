begin;

-- R87.2 corrective closure:
-- The older accounting-final-integrity trigger predates R68/R86 durable
-- financial-family metadata. R68 must be able to stamp linkage/audit metadata
-- onto immutable historical journal evidence without re-validating that row as
-- a brand-new posting under a later schema generation.
--
-- Keep the legacy integrity guard fail-closed for every accounting mutation:
--   * inserts;
--   * restore of a soft-deleted row;
--   * entry identity changes;
--   * account identity changes;
--   * debit/credit changes.
-- Metadata-only UPDATEs whose accounting fingerprint is unchanged are allowed.

create or replace function public.erp_validate_journal_line_integrity()
returns trigger
language plpgsql
set search_path=public
as $$
declare
  v_debit numeric := coalesce(nullif(new.data->>'debit','')::numeric,0);
  v_credit numeric := coalesce(nullif(new.data->>'credit','')::numeric,0);
begin
  if coalesce(new.is_deleted,false) then
    return new;
  end if;

  -- A live historical row may predate fields required by the current posting
  -- contract. If this UPDATE changes no accounting identity/amount field, it is
  -- linkage/audit metadata maintenance rather than a new posting mutation.
  if tg_op='UPDATE'
     and coalesce(old.is_deleted,false)=coalesce(new.is_deleted,false)
     and nullif(btrim(coalesce(old.data->>'entryId',old.data->>'entry_id','')),'')
         is not distinct from
         nullif(btrim(coalesce(new.data->>'entryId',new.data->>'entry_id','')),'')
     and nullif(btrim(coalesce(old.data->>'accountId',old.data->>'account_id','')),'')
         is not distinct from
         nullif(btrim(coalesce(new.data->>'accountId',new.data->>'account_id','')),'')
     and coalesce(old.data->>'debit','') is not distinct from coalesce(new.data->>'debit','')
     and coalesce(old.data->>'credit','') is not distinct from coalesce(new.data->>'credit','') then
    return new;
  end if;

  if coalesce(new.data->>'entryId','')='' or coalesce(new.data->>'accountId','')='' then
    raise exception 'بيانات سطر القيد غير مكتملة';
  end if;
  if v_debit < 0 or v_credit < 0
     or (v_debit > 0 and v_credit > 0)
     or (v_debit = 0 and v_credit = 0) then
    raise exception 'يجب أن يحتوي سطر القيد على مدين أو دائن موجب واحد فقط';
  end if;
  if not exists (
    select 1
    from public.erp_accounts a
    where a.organization_id=new.company_id
      and a.account_id=new.data->>'accountId'
      and a.is_active
  ) then
    raise exception 'حساب سطر القيد غير موجود أو غير فعال';
  end if;
  return new;
end
$$;

comment on function public.erp_validate_journal_line_integrity() is
'Legacy journal integrity guard: strict for posting mutations; permits metadata-only updates whose entry/account/debit/credit fingerprint is unchanged.';

commit;
