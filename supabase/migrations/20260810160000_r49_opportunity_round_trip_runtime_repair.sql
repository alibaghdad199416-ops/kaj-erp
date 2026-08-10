-- R49 forward-only repair: preserve every production Opportunity model field
-- through restricted-field save/list round trips. Historical R9/R49 migrations
-- remain byte-for-byte immutable.
begin;

do $$
begin
  if to_regprocedure('public.erp_r9_logical_field_for_json_key_pre_r49_roundtrip(text,text)') is null
     and to_regprocedure('public.erp_r9_logical_field_for_json_key(text,text)') is not null then
    alter function public.erp_r9_logical_field_for_json_key(text,text)
      rename to erp_r9_logical_field_for_json_key_pre_r49_roundtrip;
  end if;
end $$;

create or replace function public.erp_r9_logical_field_for_json_key(
  p_resource text,
  p_key text
) returns text
language sql
immutable
set search_path=public
as $$
  select case
    when lower(trim(coalesce(p_resource,'')))='opportunities' then
      case trim(coalesce(p_key,''))
        when 'currency' then 'currency'
        when 'currencyCode' then 'currency'
        when 'currency_code' then 'currency'
        when 'stage' then 'stage'
        when 'probability' then 'probability'
        when 'description' then 'description'
        when 'expectedCloseDate' then 'expectedCloseDate'
        when 'expected_close_date' then 'expectedCloseDate'
        when 'winLossReason' then 'winLossReason'
        when 'win_loss_reason' then 'winLossReason'
        else public.erp_r9_logical_field_for_json_key_pre_r49_roundtrip(p_resource,p_key)
      end
    else public.erp_r9_logical_field_for_json_key_pre_r49_roundtrip(p_resource,p_key)
  end
$$;

revoke all on function public.erp_r9_logical_field_for_json_key(text,text)
  from public,anon;
grant execute on function public.erp_r9_logical_field_for_json_key(text,text)
  to authenticated,service_role;

notify pgrst,'reload schema';
commit;
