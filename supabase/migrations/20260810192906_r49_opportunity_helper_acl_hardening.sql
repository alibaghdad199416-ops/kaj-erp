-- R49 forward-only ACL hardening for the internal compatibility helper
-- retained by the Opportunity field-mapping wrapper.
begin;

revoke all on function public.erp_r9_logical_field_for_json_key_pre_r49_roundtrip(text,text)
  from public,anon;
grant execute on function public.erp_r9_logical_field_for_json_key_pre_r49_roundtrip(text,text)
  to authenticated,service_role;

notify pgrst,'reload schema';
commit;
