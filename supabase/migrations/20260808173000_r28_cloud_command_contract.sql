begin;

create or replace function public.erp_r28_cloud_command(
  p_area text,
  p_action text,
  p_payload jsonb
) returns jsonb
language sql
security definer
set search_path=public
as $$
  select public.erp_r27_cloud_command($1,$2,coalesce($3,'{}'::jsonb))
$$;

revoke all on function public.erp_r28_cloud_command(text,text,jsonb) from public,anon;
grant execute on function public.erp_r28_cloud_command(text,text,jsonb) to authenticated,service_role;
grant usage on schema public to authenticated,service_role;
notify pgrst,'reload schema';
commit;
