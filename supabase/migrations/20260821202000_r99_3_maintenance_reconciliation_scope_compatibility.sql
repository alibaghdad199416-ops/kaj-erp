-- Quality Line ERP / KAJ ERP R99.3
-- Keep R98 assigned/team record scope while preserving the direct R84 fallback
-- proof required by the R89 maintenance-detail boundary.
begin;

create or replace function public.erp_r89_maintenance_cost_reconciliation(
  p_company_id uuid,p_order_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_payload jsonb;
  v_creator uuid;
  v_has_extended_scope boolean;
begin
  perform public.erp_r98_require_maintenance_order_visible(
    p_company_id,p_order_id
  );

  -- R98 delegates to the R84 contract whenever neither assigned nor team scope
  -- is configured. Keep that compatibility predicate explicit at the current
  -- browser boundary without denying users admitted by the new union scopes.
  v_has_extended_scope:=
    public.erp_cloud_user_has_permission(
      p_company_id,'maintenance.records.assigned'
    )
    or public.erp_cloud_user_has_permission(
      p_company_id,'maintenance.records.team'
    );
  if not v_has_extended_scope then
    select m.created_by into v_creator
    from public.erp_maintenance_orders m
    where m.company_id=p_company_id and m.id=p_order_id and not m.is_deleted;
    if not found or not public.erp_r84_record_visible(
      p_company_id,'maintenance',v_creator,null
    ) then
      raise exception 'maintenance_order_not_found' using errcode='P0002';
    end if;
  end if;

  v_payload:=public.erp_r57_maintenance_cost_reconciliation(
    p_company_id,p_order_id
  );
  return public.erp_r89_filter_maintenance_cost_payload(
    p_company_id,v_payload
  );
end;
$$;

revoke all on function public.erp_r89_maintenance_cost_reconciliation(
  uuid,uuid
) from public,anon;
grant execute on function public.erp_r89_maintenance_cost_reconciliation(
  uuid,uuid
) to authenticated,service_role;

commit;
