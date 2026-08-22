begin;

-- R37 is the privileged implementation used by database triggers. It was
-- historically exposed to every authenticated user even though it performs
-- cross-table writes for the caller-supplied company. Keep the implementation
-- internal and expose only the permission-checked R43 entry point.
revoke all on function public.erp_r37_reconcile_opportunity_sales_links(uuid)
  from public, anon, authenticated;
grant execute on function public.erp_r37_reconcile_opportunity_sales_links(uuid)
  to service_role;

revoke all on function public.erp_r37_opportunity_record_link_trigger()
  from public, anon, authenticated;
revoke all on function public.erp_r37_sales_order_opportunity_trigger()
  from public, anon, authenticated;

create or replace function public.erp_r43_reconcile_opportunity_sales_links(
  p_company_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.erp_active_company_context(p_company_id);

  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(
       p_company_id,
       'customer_service.update'
     ) then
    raise exception 'permission_denied:customer_service.update'
      using errcode = '42501';
  end if;

  perform public.erp_r37_reconcile_opportunity_sales_links(p_company_id);
  return jsonb_build_object(
    'ok', true,
    'companyId', p_company_id,
    'reconciledAt', now()
  );
end
$$;

revoke all on function public.erp_r43_reconcile_opportunity_sales_links(uuid)
  from public, anon, authenticated;
grant execute on function public.erp_r43_reconcile_opportunity_sales_links(uuid)
  to authenticated, service_role;

notify pgrst, 'reload schema';

commit;
