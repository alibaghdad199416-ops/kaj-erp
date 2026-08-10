begin;

-- Batch one thumbnail per visible vehicle to eliminate the N+1 image RPC pattern.
create or replace function public.erp_r43_list_car_thumbnails(
  p_company_id uuid,p_car_ids text[]
) returns setof jsonb language sql stable security definer set search_path=public as $$
  with ranked as (
    select i.id,
           coalesce(i.data->>'carId',i.data->>'car_id') as car_id,
           i.data,
           row_number() over (
             partition by coalesce(i.data->>'carId',i.data->>'car_id')
             order by public.erp_try_numeric(coalesce(i.data->>'sortOrder',i.data->>'sort_order'),0),i.created_at,i.id
           ) as rn
    from public.erp_car_images i
    where i.company_id=p_company_id
      and not i.is_deleted
      and coalesce(i.data->>'carId',i.data->>'car_id')=any(coalesce(p_car_ids,array[]::text[]))
      and not public.erp_r15_pending_delete_exists(p_company_id,'erp_car_images',i.id)
      and public.is_active_company_member(p_company_id)
      and (public.erp_cloud_user_has_permission(p_company_id,'cars.view') or public.is_company_admin(p_company_id))
  )
  select jsonb_build_object(
    'carId',car_id,
    'imageBase64',coalesce(data->>'imageBase64',data->>'image_base64','')
  )
  from ranked where rn=1
$$;

grant execute on function public.erp_r43_list_car_thumbnails(uuid,text[]) to authenticated,service_role;

-- Explicit post-sales reconciliation entry point used by runtime verification.
create or replace function public.erp_r43_reconcile_opportunity_sales_links(p_company_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_r37_reconcile_opportunity_sales_links(p_company_id);
  return jsonb_build_object('ok',true,'companyId',p_company_id,'reconciledAt',now());
end $$;
grant execute on function public.erp_r43_reconcile_opportunity_sales_links(uuid) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
