-- Quality Line ERP / KAJ ERP R99
-- Maintenance browser-write authorization closure.
-- Forward-only: preserve the proven R90/V2300 engines behind guarded wrappers.
begin;

create or replace function public.erp_r99_require_maintenance_action(
  p_company_id uuid,
  p_order_id uuid,
  p_action text,
  p_legacy_permissions text[]
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_action text:=nullif(btrim(coalesce(p_action,'')),'');
begin
  perform public.erp_active_company_context(p_company_id);
  perform public.erp_r98_require_maintenance_order_visible(p_company_id,p_order_id);

  if v_action is null or not public.erp_r95_user_can_perform_action(
    p_company_id,
    'maintenance.actions.restrict',
    'maintenance.'||v_action,
    coalesce(p_legacy_permissions,array[]::text[])
  ) then
    raise exception 'permission_denied:maintenance.%',coalesce(v_action,'unknown')
      using errcode='42501';
  end if;
end;
$$;

revoke all on function public.erp_r99_require_maintenance_action(uuid,uuid,text,text[])
  from public,anon,authenticated;
grant execute on function public.erp_r99_require_maintenance_action(uuid,uuid,text,text[])
  to service_role;

-- Keep the mature mutation bodies internal. Browser callers retain the stable
-- RPC names, but record scope and granular action authorization now execute
-- before the first locking/mutation side effect in those bodies.
alter function public.erp_r90_save_maintenance_issue_draft_line(
  uuid,uuid,uuid,text,numeric
) rename to erp_r90_save_maintenance_issue_draft_line_pre_r99;
alter function public.erp_r90_delete_maintenance_issue_draft_line(
  uuid,uuid
) rename to erp_r90_delete_maintenance_issue_draft_line_pre_r99;
alter function public.erp_r37_advance_maintenance_workflow(
  uuid,uuid
) rename to erp_r37_advance_maintenance_workflow_pre_r99;
alter function public.erp_v2300_record_maintenance_payment_batch(
  uuid,uuid,jsonb
) rename to erp_v2300_record_maintenance_payment_batch_pre_r99;

revoke all on function public.erp_r90_save_maintenance_issue_draft_line_pre_r99(
  uuid,uuid,uuid,text,numeric
) from public,anon,authenticated;
revoke all on function public.erp_r90_delete_maintenance_issue_draft_line_pre_r99(
  uuid,uuid
) from public,anon,authenticated;
revoke all on function public.erp_r37_advance_maintenance_workflow_pre_r99(
  uuid,uuid
) from public,anon,authenticated;
revoke all on function public.erp_v2300_record_maintenance_payment_batch_pre_r99(
  uuid,uuid,jsonb
) from public,anon,authenticated;

grant execute on function public.erp_r90_save_maintenance_issue_draft_line_pre_r99(
  uuid,uuid,uuid,text,numeric
) to service_role;
grant execute on function public.erp_r90_delete_maintenance_issue_draft_line_pre_r99(
  uuid,uuid
) to service_role;
grant execute on function public.erp_r37_advance_maintenance_workflow_pre_r99(
  uuid,uuid
) to service_role;
grant execute on function public.erp_v2300_record_maintenance_payment_batch_pre_r99(
  uuid,uuid,jsonb
) to service_role;

create or replace function public.erp_r90_save_maintenance_issue_draft_line(
  p_company_id uuid,p_order_id uuid,p_part_id uuid,
  p_warehouse_id text,p_quantity numeric
) returns jsonb
language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_r99_require_maintenance_action(
    p_company_id,p_order_id,'material_issue.create',array['maintenance.approve']
  );
  return public.erp_r90_save_maintenance_issue_draft_line_pre_r99(
    p_company_id,p_order_id,p_part_id,p_warehouse_id,p_quantity
  );
end;
$$;

create or replace function public.erp_r90_delete_maintenance_issue_draft_line(
  p_company_id uuid,p_line_id uuid
) returns void
language plpgsql security definer set search_path=public as $$
declare v_order_id uuid;
begin
  select maintenance_order_id into v_order_id
  from public.erp_r90_maintenance_issue_draft_lines
  where company_id=p_company_id and id=p_line_id;
  if v_order_id is null then
    raise exception 'maintenance_issue_draft_line_not_found' using errcode='P0002';
  end if;

  perform public.erp_r99_require_maintenance_action(
    p_company_id,v_order_id,'material_issue.create',array['maintenance.approve']
  );
  perform public.erp_r90_delete_maintenance_issue_draft_line_pre_r99(
    p_company_id,p_line_id
  );
end;
$$;

create or replace function public.erp_r37_advance_maintenance_workflow(
  p_company_id uuid,p_order_id uuid
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_stage text;
  v_pricing_type text;
  v_action text;
begin
  perform public.erp_active_company_context(p_company_id);
  perform public.erp_r98_require_maintenance_order_visible(p_company_id,p_order_id);

  select workflow_stage,pricing_type
    into v_stage,v_pricing_type
  from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id and not is_deleted;
  if not found then
    raise exception 'maintenance_order_not_found' using errcode='P0002';
  end if;

  v_action:=case v_stage
    when 'order_draft' then 'order.approve'
    when 'order_approved' then 'material_issue.create'
    when 'stock_issue_draft' then 'material_issue.approve'
    when 'stock_issue_approved' then
      case when v_pricing_type='paid' then 'invoice.create' else 'order.approve' end
    when 'invoice_draft' then 'invoice.approve'
    else null
  end;
  if v_action is null then
    raise exception 'maintenance_no_next_stage' using errcode='P0001';
  end if;

  perform public.erp_r99_require_maintenance_action(
    p_company_id,p_order_id,v_action,array['maintenance.approve']
  );
  return public.erp_r37_advance_maintenance_workflow_pre_r99(
    p_company_id,p_order_id
  );
end;
$$;

create or replace function public.erp_v2300_record_maintenance_payment_batch(
  p_company_id uuid,p_order_id uuid,p_payments jsonb
) returns jsonb
language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_r99_require_maintenance_action(
    p_company_id,p_order_id,'payment',array['cashbox.receipt']
  );
  return public.erp_v2300_record_maintenance_payment_batch_pre_r99(
    p_company_id,p_order_id,p_payments
  );
end;
$$;

revoke all on function public.erp_r90_save_maintenance_issue_draft_line(
  uuid,uuid,uuid,text,numeric
) from public,anon;
revoke all on function public.erp_r90_delete_maintenance_issue_draft_line(
  uuid,uuid
) from public,anon;
revoke all on function public.erp_r37_advance_maintenance_workflow(
  uuid,uuid
) from public,anon;
revoke all on function public.erp_v2300_record_maintenance_payment_batch(
  uuid,uuid,jsonb
) from public,anon;

grant execute on function public.erp_r90_save_maintenance_issue_draft_line(
  uuid,uuid,uuid,text,numeric
) to authenticated,service_role;
grant execute on function public.erp_r90_delete_maintenance_issue_draft_line(
  uuid,uuid
) to authenticated,service_role;
grant execute on function public.erp_r37_advance_maintenance_workflow(
  uuid,uuid
) to authenticated,service_role;
grant execute on function public.erp_v2300_record_maintenance_payment_batch(
  uuid,uuid,jsonb
) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
