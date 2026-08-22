-- Quality Line ERP R70.5 — make the Maintenance dialog's existing Cancel action
-- a real, independent lifecycle operation for Drafts as well as executed orders.
-- Draft cancellation preserves the document/lines and has no downstream effects
-- to reverse. Delete remains a separate maintenance.delete operation.
begin;

alter function public.erp_r67_cancel_maintenance_order(uuid,uuid,text)
  rename to erp_r67_cancel_maintenance_order_pre_r70_5;

revoke all on function public.erp_r67_cancel_maintenance_order_pre_r70_5(uuid,uuid,text)
  from public,anon,authenticated;
grant execute on function public.erp_r67_cancel_maintenance_order_pre_r70_5(uuid,uuid,text)
  to service_role;

create or replace function public.erp_r67_cancel_maintenance_order(
  p_company_id uuid,p_order_id uuid,p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_stage text;
  v_reason text:=coalesce(nullif(btrim(p_reason),''),'Maintenance order cancelled');
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_cloud_user_has_permission(p_company_id,'maintenance.cancel')
    and not public.is_company_admin(p_company_id) then
    raise exception 'permission_denied:maintenance.cancel' using errcode='42501';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_company_id::text||':maintenance:cancel-order:'||p_order_id::text,0));

  select lower(coalesce(workflow_stage,status))
  into v_stage
  from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id and not is_deleted
  for update;

  if not found then
    raise exception 'maintenance_order_not_found' using errcode='P0001';
  end if;

  if v_stage='cancelled' then
    return jsonb_build_object(
      'ok',true,'status','cancelled','idempotent',true,
      'orderPreserved',true,'paymentsPreserved',true
    );
  end if;

  if v_stage in ('draft','order_draft') then
    -- No inventory/accounting/invoice/payment effect exists at the Draft
    -- boundary. Preserve the draft and its lines as a cancelled historical
    -- document. A later physical purge is separately governed by
    -- maintenance.delete.
    update public.erp_maintenance_orders
    set workflow_stage='cancelled',
        status='cancelled',
        cancelled_at=coalesce(cancelled_at,now()),
        cancel_reason=v_reason,
        is_deleted=false,
        deleted_at=null,
        updated_at=now()
    where company_id=p_company_id and id=p_order_id;

    return jsonb_build_object(
      'ok',true,'status','cancelled','draftCancellation',true,
      'orderPreserved',true,'paymentsPreserved',true,'reason',v_reason
    );
  end if;

  -- Executed stages retain the fully verified R67 reversal contract.
  return public.erp_r67_cancel_maintenance_order_pre_r70_5(
    p_company_id,p_order_id,v_reason
  );
end $$;

revoke all on function public.erp_r67_cancel_maintenance_order(uuid,uuid,text)
  from public,anon;
grant execute on function public.erp_r67_cancel_maintenance_order(uuid,uuid,text)
  to authenticated,service_role;

notify pgrst,'reload schema';
commit;
