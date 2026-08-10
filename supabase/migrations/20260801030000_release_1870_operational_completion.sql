-- Quality Line ERP 18.7.1 - production operational completion.
begin;

-- Old maintenance orders may contain posted payments and issued stock. Reverse
-- linked payment journals first, clear payment state, then use the canonical
-- cancellation routine to return stock before soft deletion.
create or replace function public.erp_delete_cloud_maintenance_order(
  p_company_id uuid,p_order_id uuid,p_reason text default null
) returns void language plpgsql security definer set search_path=public as $$
declare
  o public.erp_maintenance_orders%rowtype;
  v_reason text := coalesce(nullif(btrim(p_reason),''),'حذف أمر الصيانة');
begin
  perform public.erp_active_company_context(p_company_id);
  select * into o
  from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id and not is_deleted
  for update;
  if not found then raise exception 'أمر الصيانة غير موجود'; end if;

  -- Reverse every known accounting reference used by current and legacy data.
  begin perform public.erp_phase2_void_reference_journals(p_company_id,'maintenance_payment',p_order_id::text); exception when others then null; end;
  begin perform public.erp_phase2_void_reference_journals(p_company_id,'maintenance_invoice',p_order_id::text); exception when others then null; end;
  begin perform public.erp_phase2_void_reference_journals(p_company_id,'maintenance',p_order_id::text); exception when others then null; end;

  update public.erp_maintenance_payments
     set is_deleted=true,deleted_at=now()
   where company_id=p_company_id and maintenance_order_id=p_order_id and not is_deleted;
  update public.erp_maintenance_orders
     set paid_amount=0,updated_at=now()
   where company_id=p_company_id and id=p_order_id;

  -- This canonical routine restores stock and creates return movements when
  -- materials were already issued. A malformed legacy record is still allowed
  -- to continue to the direct cleanup below.
  begin
    perform public.erp_cancel_cloud_maintenance_order(p_company_id,p_order_id,v_reason);
  exception when others then
    null;
  end;

  begin perform public.erp_phase2_void_reference_journals(p_company_id,'maintenance_stock_issue',p_order_id::text); exception when others then null; end;

  update public.erp_maintenance_parts
     set is_deleted=true,deleted_at=now(),updated_at=now()
   where company_id=p_company_id and maintenance_order_id=p_order_id and not is_deleted;

  update public.erp_maintenance_orders
     set paid_amount=0,
         workflow_stage='cancelled',
         status='cancelled',
         cancel_reason=v_reason,
         cancelled_at=coalesce(cancelled_at,now()),
         is_deleted=true,
         deleted_at=now(),
         deleted_by=auth.uid(),
         deleted_reason=v_reason,
         updated_at=now()
   where company_id=p_company_id and id=p_order_id;
end $$;

revoke all on function public.erp_delete_cloud_maintenance_order(uuid,uuid,text) from public,anon;
grant execute on function public.erp_delete_cloud_maintenance_order(uuid,uuid,text) to authenticated;

commit;
