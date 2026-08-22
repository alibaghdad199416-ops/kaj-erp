begin;

-- R50 correctly restricted the reconciliation entry point to active company
-- members with customer_service.update, but the internal R37 backfill changes
-- erp_sales_orders_cloud.opportunity_id. The R9 field guard consequently
-- required the unrelated sales.update permission after the R50 check passed.
--
-- Keep that guard intact for every ordinary sales write. This bridge is valid
-- only for the transaction-local R51 marker, only for an UPDATE of the sales
-- resource, and only when opportunity_id is the sole user-editable field that
-- changed. The caller's real customer_service.update permission is rechecked
-- inside the guard, so setting the marker alone cannot grant access.
create or replace function public.erp_r9_guard_input_fields()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_company_id uuid;
  v_resource text:=coalesce(TG_ARGV[0],'');
  v_insert_permission text:=nullif(coalesce(TG_ARGV[1],''),'');
  v_update_permission text:=nullif(coalesce(TG_ARGV[2],''),'');
  v_base_permission text;
  v_new jsonb:=to_jsonb(new);
  v_old jsonb:=case when TG_OP='UPDATE' then to_jsonb(old) else '{}'::jsonb end;
  v_pair text;
  v_column text;
  v_field text;
  v_index integer;
  v_changed boolean;
  v_any_user_field_changed boolean:=false;
  v_reconciliation_bridge_eligible boolean:=true;
begin
  if coalesce(current_setting('request.jwt.claim.role',true),'')='service_role' then return new; end if;

  v_company_id:=nullif(v_new->>'company_id','')::uuid;
  if v_company_id is null then raise exception 'field_permission_company_required' using errcode='22023'; end if;

  if TG_NARGS>3 then
    for v_index in 3..TG_NARGS-1 loop
      v_pair:=TG_ARGV[v_index];
      v_column:=split_part(v_pair,'=',1);
      v_field:=split_part(v_pair,'=',2);
      if v_column='' or v_field='' then continue; end if;
      if TG_OP='INSERT' then
        v_changed:=v_new ? v_column and jsonb_typeof(v_new->v_column) is distinct from 'null';
      else
        v_changed:=(v_old->v_column) is distinct from (v_new->v_column);
      end if;
      if not v_changed then continue; end if;
      v_any_user_field_changed:=true;
      if v_column<>'opportunity_id' then
        v_reconciliation_bridge_eligible:=false;
      end if;
      if not public.erp_cloud_user_can_edit_field(v_company_id,v_resource,v_field,null) then
        raise exception 'field_permission_denied:%.%',v_resource,v_field using errcode='42501';
      end if;
    end loop;
  end if;

  if not v_any_user_field_changed then return new; end if;

  v_base_permission:=case when TG_OP='INSERT' then v_insert_permission else v_update_permission end;
  if v_base_permission is not null
     and not public.erp_cloud_user_has_permission(v_company_id,v_base_permission)
     and not (
       TG_OP='UPDATE'
       and v_resource='sales'
       and v_reconciliation_bridge_eligible
       and current_setting('qualityline.r51_reconciliation_permission',true)='customer_service.update'
       and public.erp_cloud_user_has_permission(v_company_id,'customer_service.update')
     ) then
    raise exception 'permission_denied:%',v_base_permission using errcode='42501';
  end if;
  return new;
end;
$$;

create or replace function public.erp_r43_reconcile_opportunity_sales_links(
  p_company_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_previous_bridge text:=current_setting('qualityline.r51_reconciliation_permission',true);
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

  perform set_config(
    'qualityline.r51_reconciliation_permission',
    'customer_service.update',
    true
  );
  begin
    perform public.erp_r37_reconcile_opportunity_sales_links(p_company_id);
  exception when others then
    perform set_config(
      'qualityline.r51_reconciliation_permission',
      coalesce(v_previous_bridge,''),
      true
    );
    raise;
  end;
  perform set_config(
    'qualityline.r51_reconciliation_permission',
    coalesce(v_previous_bridge,''),
    true
  );

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
