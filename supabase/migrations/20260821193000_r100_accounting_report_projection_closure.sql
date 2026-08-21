-- Quality Line ERP / KAJ ERP R100
-- Accounting report field-projection closure.
--
-- The detailed Trial Balance and General Ledger engines already calculate the
-- required opening/period/closing and running-balance values. Under
-- accounting.fields.restrict, however, the R9 result mapper did not recognize
-- those newer report JSON keys, so the security filter silently removed them
-- before Flutter received the rows. Preserve the mature mapper and extend only
-- the accounting report projection surface.
begin;

do $$
begin
  if to_regprocedure('public.erp_r9_result_field_for_key_pre_r100(text,text)') is null then
    alter function public.erp_r9_result_field_for_key(text,text)
      rename to erp_r9_result_field_for_key_pre_r100;
  end if;
end $$;

create or replace function public.erp_r9_result_field_for_key(
  p_resource text,
  p_key text
) returns text
language sql immutable
set search_path=public
as $$
  select case
    when trim(coalesce(p_resource,''))='accounting' then
      case trim(coalesce(p_key,''))
        -- Detailed Trial Balance split columns.
        when 'openingDebit' then 'debit'
        when 'openingCredit' then 'credit'
        when 'periodDebit' then 'debit'
        when 'periodCredit' then 'credit'
        when 'closingDebit' then 'debit'
        when 'closingCredit' then 'credit'

        -- General Ledger calculated balance and hierarchy projection.
        when 'runningBalance' then 'balances'
        when 'parentAccountId' then 'parentAccount'
        when 'rootAccountCode' then 'accountCode'
        when 'rootAccountName' then 'accountName'
        when 'hierarchyPath' then 'accountName'
        when 'hierarchyDepth' then 'parentAccount'
        when 'partyName' then 'reference'

        -- Delegate every established accounting key and every other resource to
        -- the complete pre-R100 mapping so no historical field contract changes.
        else public.erp_r9_result_field_for_key_pre_r100(p_resource,p_key)
      end
    else public.erp_r9_result_field_for_key_pre_r100(p_resource,p_key)
  end
$$;

revoke all on function public.erp_r9_result_field_for_key_pre_r100(text,text)
  from public,anon;
grant execute on function public.erp_r9_result_field_for_key_pre_r100(text,text)
  to authenticated,service_role;
revoke all on function public.erp_r9_result_field_for_key(text,text)
  from public,anon;
grant execute on function public.erp_r9_result_field_for_key(text,text)
  to authenticated,service_role;

notify pgrst,'reload schema';
commit;
