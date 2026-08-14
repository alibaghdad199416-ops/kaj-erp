begin;

create or replace function public.erp_v758_active_logistics(
  p_company_id uuid,p_order_id uuid,p_module text
) returns jsonb language sql stable security definer set search_path=public as $$
  select public.erp_v736_active_logistics(p_company_id,p_order_id,p_module)
$$;

revoke all on function public.erp_v758_active_logistics(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.erp_v758_active_logistics(uuid,uuid,text) to service_role;

commit;
