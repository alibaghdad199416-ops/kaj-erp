begin;

create or replace function public.erp_r66_delete_maintenance_draft(
  p_company_id uuid,p_order_id uuid,p_reason text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_stage text; v_invoice_journal_entry_id text;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_cloud_user_has_permission(p_company_id,'maintenance.delete')
    and not public.is_company_admin(p_company_id) then
    raise exception 'permission_denied:maintenance.delete' using errcode='42501';
  end if;
  select lower(coalesce(workflow_stage,status)),invoice_journal_entry_id
    into v_stage,v_invoice_journal_entry_id
  from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found then raise exception 'maintenance_order_not_found' using errcode='P0001'; end if;
  if v_stage not in ('draft','order_draft') then
    raise exception 'draft_delete_only:use_cancel_reverse' using errcode='P0001';
  end if;
  if nullif(btrim(coalesce(v_invoice_journal_entry_id,'')),'') is not null
    or exists(select 1 from public.erp_maintenance_payments p
      where p.company_id=p_company_id and p.maintenance_order_id=p_order_id and not p.is_deleted)
    or exists(select 1 from public.erp_maintenance_material_issues d
      where d.company_id=p_company_id and d.maintenance_order_id=p_order_id and d.status='executed') then
    raise exception 'draft_has_linked_business_history:use_cancel_reverse' using errcode='P0001';
  end if;
  return public.erp_delete_cloud_maintenance_order_v3(p_company_id,p_order_id,p_reason);
end $$;

revoke all on function public.erp_r66_delete_maintenance_draft(uuid,uuid,text)
  from public,anon,authenticated;
grant execute on function public.erp_r66_delete_maintenance_draft(uuid,uuid,text)
  to authenticated,service_role;

commit;
