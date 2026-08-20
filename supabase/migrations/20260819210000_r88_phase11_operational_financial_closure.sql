-- Quality Line ERP / KAJ ERP R88 Phase 11
-- Operational document, financial reporting, maintenance scheduling and
-- detailed notification closure. Forward-only: no historical migration edits.
begin;

-- ---------------------------------------------------------------------------
-- 1. Granular action permission compatibility boundary.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r88_action_allowed(
  p_company_id uuid,
  p_resource text,
  p_action text,
  p_legacy_permission text
) returns boolean
language sql stable security definer set search_path=public as $$
  select case
    when public.erp_cloud_user_has_permission(
      p_company_id,trim(p_resource)||'.actions.restrict'
    ) then public.erp_cloud_user_has_permission(
      p_company_id,p_legacy_permission
    ) and public.erp_cloud_user_has_permission(
      p_company_id,trim(p_resource)||'.'||trim(p_action)
    )
    else public.erp_cloud_user_has_permission(p_company_id,p_legacy_permission)
  end
$$;

revoke all on function public.erp_r88_action_allowed(uuid,text,text,text)
  from public,anon;
grant execute on function public.erp_r88_action_allowed(uuid,text,text,text)
  to authenticated,service_role;

-- When a module has not opted into granular action restriction, the original
-- endpoint remains the source of truth for legacy permission semantics. Once
-- `<module>.actions.restrict` is enabled, this helper adds the exact action
-- gate before delegating to the untouched pre-R88 implementation.
create or replace function public.erp_r88_require_restricted_action(
  p_company_id uuid,p_resource text,p_action text
) returns void
language plpgsql stable security definer set search_path=public as $$
begin
  if public.erp_cloud_user_has_permission(
       p_company_id,trim(p_resource)||'.actions.restrict'
     ) and not public.erp_cloud_user_has_permission(
       p_company_id,trim(p_resource)||'.'||trim(p_action)
     ) then
    raise exception 'permission_denied:%.%',p_resource,p_action using errcode='42501';
  end if;
end;
$$;
revoke all on function public.erp_r88_require_restricted_action(uuid,text,text)
  from public,anon;
grant execute on function public.erp_r88_require_restricted_action(uuid,text,text)
  to authenticated,service_role;

-- Preserve the mature implementations under private aliases, then expose the
-- same RPC signatures with granular action guards. ALTER FUNCTION keeps all
-- dependent internal calls bound to the original OIDs while client calls use
-- the guarded names created immediately afterwards.
do $$
begin
  if to_regprocedure('public.erp_r49_approve_sales_order_pre_r88(uuid,uuid)') is null then
    alter function public.erp_r49_approve_sales_order(uuid,uuid)
      rename to erp_r49_approve_sales_order_pre_r88;
  end if;
  if to_regprocedure('public.erp_r49_approve_purchase_order_pre_r88(uuid,uuid)') is null then
    alter function public.erp_r49_approve_purchase_order(uuid,uuid)
      rename to erp_r49_approve_purchase_order_pre_r88;
  end if;
  if to_regprocedure('public.erp_r49_create_sales_delivery_pre_r88(uuid,uuid,text,text)') is null then
    alter function public.erp_r49_create_sales_delivery(uuid,uuid,text,text)
      rename to erp_r49_create_sales_delivery_pre_r88;
  end if;
  if to_regprocedure('public.erp_r49_create_sales_delivery_multi_pre_r88(uuid,uuid,jsonb,text)') is null then
    alter function public.erp_r49_create_sales_delivery_multi(uuid,uuid,jsonb,text)
      rename to erp_r49_create_sales_delivery_multi_pre_r88;
  end if;
  if to_regprocedure('public.erp_r49_create_purchase_receipt_pre_r88(uuid,uuid,text,text)') is null then
    alter function public.erp_r49_create_purchase_receipt(uuid,uuid,text,text)
      rename to erp_r49_create_purchase_receipt_pre_r88;
  end if;
  if to_regprocedure('public.erp_r49_create_purchase_receipt_multi_pre_r88(uuid,uuid,jsonb,text)') is null then
    alter function public.erp_r49_create_purchase_receipt_multi(uuid,uuid,jsonb,text)
      rename to erp_r49_create_purchase_receipt_multi_pre_r88;
  end if;
  if to_regprocedure('public.erp_phase2_approve_sales_delivery_pre_r88(uuid,uuid)') is null then
    alter function public.erp_phase2_approve_sales_delivery(uuid,uuid)
      rename to erp_phase2_approve_sales_delivery_pre_r88;
  end if;
  if to_regprocedure('public.erp_phase2_approve_purchase_receipt_pre_r88(uuid,uuid)') is null then
    alter function public.erp_phase2_approve_purchase_receipt(uuid,uuid)
      rename to erp_phase2_approve_purchase_receipt_pre_r88;
  end if;
  if to_regprocedure('public.erp_create_cloud_sales_workflow_invoice_pre_r88(uuid,uuid)') is null then
    alter function public.erp_create_cloud_sales_workflow_invoice(uuid,uuid)
      rename to erp_create_cloud_sales_workflow_invoice_pre_r88;
  end if;
  if to_regprocedure('public.erp_create_cloud_purchase_workflow_invoice_pre_r88(uuid,uuid)') is null then
    alter function public.erp_create_cloud_purchase_workflow_invoice(uuid,uuid)
      rename to erp_create_cloud_purchase_workflow_invoice_pre_r88;
  end if;
  if to_regprocedure('public.erp_r22_approve_sales_invoice_pre_r88(uuid,uuid)') is null then
    alter function public.erp_r22_approve_sales_invoice(uuid,uuid)
      rename to erp_r22_approve_sales_invoice_pre_r88;
  end if;
  if to_regprocedure('public.erp_r22_approve_purchase_invoice_pre_r88(uuid,uuid)') is null then
    alter function public.erp_r22_approve_purchase_invoice(uuid,uuid)
      rename to erp_r22_approve_purchase_invoice_pre_r88;
  end if;
  if to_regprocedure('public.erp_v2300_pay_cloud_workflow_invoice_batch_pre_r88(uuid,uuid,text,jsonb)') is null then
    alter function public.erp_v2300_pay_cloud_workflow_invoice_batch(uuid,uuid,text,jsonb)
      rename to erp_v2300_pay_cloud_workflow_invoice_batch_pre_r88;
  end if;
  if to_regprocedure('public.erp_cancel_cloud_sales_delivery_pre_r88(uuid,uuid)') is null then
    alter function public.erp_cancel_cloud_sales_delivery(uuid,uuid)
      rename to erp_cancel_cloud_sales_delivery_pre_r88;
  end if;
  if to_regprocedure('public.erp_cancel_cloud_purchase_receipt_pre_r88(uuid,uuid)') is null then
    alter function public.erp_cancel_cloud_purchase_receipt(uuid,uuid)
      rename to erp_cancel_cloud_purchase_receipt_pre_r88;
  end if;
  if to_regprocedure('public.erp_cancel_cloud_sales_workflow_invoice_pre_r88(uuid,uuid,text)') is null then
    alter function public.erp_cancel_cloud_sales_workflow_invoice(uuid,uuid,text)
      rename to erp_cancel_cloud_sales_workflow_invoice_pre_r88;
  end if;
  if to_regprocedure('public.erp_cancel_cloud_purchase_workflow_invoice_pre_r88(uuid,uuid,text)') is null then
    alter function public.erp_cancel_cloud_purchase_workflow_invoice(uuid,uuid,text)
      rename to erp_cancel_cloud_purchase_workflow_invoice_pre_r88;
  end if;
end $$;

create or replace function public.erp_r49_approve_sales_order(
  p_company_id uuid,p_order_id uuid
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_r88_require_restricted_action(p_company_id,'sales','order.approve');
  perform public.erp_r49_approve_sales_order_pre_r88(p_company_id,p_order_id);
end;
$$;
create or replace function public.erp_r49_approve_purchase_order(
  p_company_id uuid,p_order_id uuid
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_r88_require_restricted_action(p_company_id,'purchases','order.approve');
  perform public.erp_r49_approve_purchase_order_pre_r88(p_company_id,p_order_id);
end;
$$;
create or replace function public.erp_r49_create_sales_delivery(
  p_company_id uuid,p_order_id uuid,p_warehouse_id text default null,p_notes text default null
) returns uuid language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_r88_require_restricted_action(p_company_id,'sales','delivery.create');
  return public.erp_r49_create_sales_delivery_pre_r88(p_company_id,p_order_id,p_warehouse_id,p_notes);
end;
$$;
create or replace function public.erp_r49_create_sales_delivery_multi(
  p_company_id uuid,p_order_id uuid,p_allocations jsonb,p_notes text default null
) returns uuid language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_r88_require_restricted_action(p_company_id,'sales','delivery.create');
  return public.erp_r49_create_sales_delivery_multi_pre_r88(p_company_id,p_order_id,p_allocations,p_notes);
end;
$$;
create or replace function public.erp_r49_create_purchase_receipt(
  p_company_id uuid,p_order_id uuid,p_warehouse_id text default null,p_notes text default null
) returns uuid language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_r88_require_restricted_action(p_company_id,'purchases','receipt.create');
  return public.erp_r49_create_purchase_receipt_pre_r88(p_company_id,p_order_id,p_warehouse_id,p_notes);
end;
$$;
create or replace function public.erp_r49_create_purchase_receipt_multi(
  p_company_id uuid,p_order_id uuid,p_allocations jsonb,p_notes text default null
) returns uuid language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_r88_require_restricted_action(p_company_id,'purchases','receipt.create');
  return public.erp_r49_create_purchase_receipt_multi_pre_r88(p_company_id,p_order_id,p_allocations,p_notes);
end;
$$;
create or replace function public.erp_phase2_approve_sales_delivery(
  p_company_id uuid,p_delivery_id uuid
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_r88_require_restricted_action(p_company_id,'sales','delivery.approve');
  perform public.erp_phase2_approve_sales_delivery_pre_r88(p_company_id,p_delivery_id);
end;
$$;
create or replace function public.erp_phase2_approve_purchase_receipt(
  p_company_id uuid,p_receipt_id uuid
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_r88_require_restricted_action(p_company_id,'purchases','receipt.approve');
  perform public.erp_phase2_approve_purchase_receipt_pre_r88(p_company_id,p_receipt_id);
end;
$$;
create or replace function public.erp_create_cloud_sales_workflow_invoice(
  p_company_id uuid,p_order_id uuid
) returns uuid language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_r88_require_restricted_action(p_company_id,'sales','invoice.create');
  return public.erp_create_cloud_sales_workflow_invoice_pre_r88(p_company_id,p_order_id);
end;
$$;
create or replace function public.erp_create_cloud_purchase_workflow_invoice(
  p_company_id uuid,p_order_id uuid
) returns uuid language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_r88_require_restricted_action(p_company_id,'purchases','invoice.create');
  return public.erp_create_cloud_purchase_workflow_invoice_pre_r88(p_company_id,p_order_id);
end;
$$;
create or replace function public.erp_r22_approve_sales_invoice(
  p_company_id uuid,p_invoice_id uuid
) returns jsonb language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_r88_require_restricted_action(p_company_id,'sales','invoice.approve');
  return public.erp_r22_approve_sales_invoice_pre_r88(p_company_id,p_invoice_id);
end;
$$;
create or replace function public.erp_r22_approve_purchase_invoice(
  p_company_id uuid,p_invoice_id uuid
) returns jsonb language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_r88_require_restricted_action(p_company_id,'purchases','invoice.approve');
  return public.erp_r22_approve_purchase_invoice_pre_r88(p_company_id,p_invoice_id);
end;
$$;
create or replace function public.erp_v2300_pay_cloud_workflow_invoice_batch(
  p_company_id uuid,p_invoice_id uuid,p_module text,p_payments jsonb
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_module text:=lower(btrim(coalesce(p_module,'')));
begin
  if v_module not in ('sales','purchases') then raise exception 'invalid_workflow_module'; end if;
  perform public.erp_r88_require_restricted_action(p_company_id,v_module,'payment');
  return public.erp_v2300_pay_cloud_workflow_invoice_batch_pre_r88(
    p_company_id,p_invoice_id,v_module,p_payments
  );
end;
$$;
create or replace function public.erp_cancel_cloud_sales_delivery(
  p_company_id uuid,p_delivery_id uuid
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_r88_require_restricted_action(p_company_id,'sales','reverse');
  perform public.erp_cancel_cloud_sales_delivery_pre_r88(p_company_id,p_delivery_id);
end;
$$;
create or replace function public.erp_cancel_cloud_purchase_receipt(
  p_company_id uuid,p_receipt_id uuid
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_r88_require_restricted_action(p_company_id,'purchases','reverse');
  perform public.erp_cancel_cloud_purchase_receipt_pre_r88(p_company_id,p_receipt_id);
end;
$$;
create or replace function public.erp_cancel_cloud_sales_workflow_invoice(
  p_company_id uuid,p_invoice_id uuid,p_reason text default null
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_r88_require_restricted_action(p_company_id,'sales','reverse');
  perform public.erp_cancel_cloud_sales_workflow_invoice_pre_r88(p_company_id,p_invoice_id,p_reason);
end;
$$;
create or replace function public.erp_cancel_cloud_purchase_workflow_invoice(
  p_company_id uuid,p_invoice_id uuid,p_reason text default null
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_r88_require_restricted_action(p_company_id,'purchases','reverse');
  perform public.erp_cancel_cloud_purchase_workflow_invoice_pre_r88(p_company_id,p_invoice_id,p_reason);
end;
$$;

-- The renamed implementations are internal only; authenticated clients must
-- enter through the guarded signatures above.
revoke all on function public.erp_r49_approve_sales_order_pre_r88(uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_r49_approve_purchase_order_pre_r88(uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_r49_create_sales_delivery_pre_r88(uuid,uuid,text,text) from public,anon,authenticated;
revoke all on function public.erp_r49_create_sales_delivery_multi_pre_r88(uuid,uuid,jsonb,text) from public,anon,authenticated;
revoke all on function public.erp_r49_create_purchase_receipt_pre_r88(uuid,uuid,text,text) from public,anon,authenticated;
revoke all on function public.erp_r49_create_purchase_receipt_multi_pre_r88(uuid,uuid,jsonb,text) from public,anon,authenticated;
revoke all on function public.erp_phase2_approve_sales_delivery_pre_r88(uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_phase2_approve_purchase_receipt_pre_r88(uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_create_cloud_sales_workflow_invoice_pre_r88(uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_create_cloud_purchase_workflow_invoice_pre_r88(uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_r22_approve_sales_invoice_pre_r88(uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_r22_approve_purchase_invoice_pre_r88(uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_v2300_pay_cloud_workflow_invoice_batch_pre_r88(uuid,uuid,text,jsonb) from public,anon,authenticated;
revoke all on function public.erp_cancel_cloud_sales_delivery_pre_r88(uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_cancel_cloud_purchase_receipt_pre_r88(uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_cancel_cloud_sales_workflow_invoice_pre_r88(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.erp_cancel_cloud_purchase_workflow_invoice_pre_r88(uuid,uuid,text) from public,anon,authenticated;

grant execute on function public.erp_r49_approve_sales_order(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r49_approve_purchase_order(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r49_create_sales_delivery(uuid,uuid,text,text) to authenticated,service_role;
grant execute on function public.erp_r49_create_sales_delivery_multi(uuid,uuid,jsonb,text) to authenticated,service_role;
grant execute on function public.erp_r49_create_purchase_receipt(uuid,uuid,text,text) to authenticated,service_role;
grant execute on function public.erp_r49_create_purchase_receipt_multi(uuid,uuid,jsonb,text) to authenticated,service_role;
grant execute on function public.erp_phase2_approve_sales_delivery(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_phase2_approve_purchase_receipt(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_create_cloud_sales_workflow_invoice(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_create_cloud_purchase_workflow_invoice(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r22_approve_sales_invoice(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r22_approve_purchase_invoice(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_v2300_pay_cloud_workflow_invoice_batch(uuid,uuid,text,jsonb) to authenticated,service_role;
grant execute on function public.erp_cancel_cloud_sales_delivery(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_cancel_cloud_purchase_receipt(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_cancel_cloud_sales_workflow_invoice(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.erp_cancel_cloud_purchase_workflow_invoice(uuid,uuid,text) to authenticated,service_role;

-- Maintenance operational actions use the same compatibility boundary. The
-- mature pre-R88 functions retain their business/inventory/accounting checks;
-- these wrappers add the Phase 11 leaf permission for the exact workflow step.
do $$
begin
  if to_regprocedure('public.erp_r37_advance_maintenance_workflow_pre_r88(uuid,uuid)') is null then
    alter function public.erp_r37_advance_maintenance_workflow(uuid,uuid)
      rename to erp_r37_advance_maintenance_workflow_pre_r88;
  end if;
  if to_regprocedure('public.erp_r57_execute_maintenance_material_issue_pre_r88(uuid,uuid,uuid,uuid,text,numeric,timestamptz)') is null then
    alter function public.erp_r57_execute_maintenance_material_issue(uuid,uuid,uuid,uuid,text,numeric,timestamptz)
      rename to erp_r57_execute_maintenance_material_issue_pre_r88;
  end if;
  if to_regprocedure('public.erp_r57_reverse_maintenance_material_issue_pre_r88(uuid,uuid,text)') is null then
    alter function public.erp_r57_reverse_maintenance_material_issue(uuid,uuid,text)
      rename to erp_r57_reverse_maintenance_material_issue_pre_r88;
  end if;
  if to_regprocedure('public.erp_v2300_record_maintenance_payment_batch_pre_r88(uuid,uuid,jsonb)') is null then
    alter function public.erp_v2300_record_maintenance_payment_batch(uuid,uuid,jsonb)
      rename to erp_v2300_record_maintenance_payment_batch_pre_r88;
  end if;
  if to_regprocedure('public.erp_manage_maintenance_order_component_pre_r88(uuid,uuid,text,text,text)') is null then
    alter function public.erp_manage_maintenance_order_component(uuid,uuid,text,text,text)
      rename to erp_manage_maintenance_order_component_pre_r88;
  end if;
end $$;

create or replace function public.erp_r37_advance_maintenance_workflow(
  p_company_id uuid,p_order_id uuid
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_stage text;
  v_pricing text;
  v_action text;
begin
  select lower(coalesce(workflow_stage,status)),lower(coalesce(pricing_type,'paid'))
    into v_stage,v_pricing
  from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id and not is_deleted;
  if not found then raise exception 'maintenance_order_not_found'; end if;

  v_action:=case
    when v_stage in ('draft','order_draft') then 'order.approve'
    when v_stage='order_approved' then 'material_issue.create'
    when v_stage='stock_issue_draft' then 'material_issue.approve'
    when v_stage='stock_issue_approved' and v_pricing='paid' then 'invoice.create'
    when v_stage='stock_issue_approved' then 'order.approve'
    when v_stage='invoice_draft' then 'invoice.approve'
    else null end;
  if v_action is not null then
    perform public.erp_r88_require_restricted_action(p_company_id,'maintenance',v_action);
  end if;
  return public.erp_r37_advance_maintenance_workflow_pre_r88(p_company_id,p_order_id);
end;
$$;

create or replace function public.erp_r57_execute_maintenance_material_issue(
  p_company_id uuid,p_order_id uuid,p_issue_id uuid,p_part_id uuid,
  p_warehouse_id text,p_quantity numeric,p_effective_at timestamptz default now()
) returns jsonb language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_r88_require_restricted_action(
    p_company_id,'maintenance','material_issue.approve'
  );
  return public.erp_r57_execute_maintenance_material_issue_pre_r88(
    p_company_id,p_order_id,p_issue_id,p_part_id,p_warehouse_id,p_quantity,p_effective_at
  );
end;
$$;

create or replace function public.erp_r57_reverse_maintenance_material_issue(
  p_company_id uuid,p_issue_id uuid,p_reason text default null
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_r88_require_restricted_action(p_company_id,'maintenance','reverse');
  perform public.erp_r57_reverse_maintenance_material_issue_pre_r88(
    p_company_id,p_issue_id,p_reason
  );
end;
$$;

create or replace function public.erp_v2300_record_maintenance_payment_batch(
  p_company_id uuid,p_order_id uuid,p_payments jsonb
) returns jsonb language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_r88_require_restricted_action(p_company_id,'maintenance','payment');
  return public.erp_v2300_record_maintenance_payment_batch_pre_r88(
    p_company_id,p_order_id,p_payments
  );
end;
$$;

create or replace function public.erp_manage_maintenance_order_component(
  p_company_id uuid,p_order_id uuid,p_component_type text,p_action text,
  p_reason text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_component text:=lower(btrim(coalesce(p_component_type,'')));
  v_action_name text:=lower(btrim(coalesce(p_action,'')));
  v_stage text;
  v_pricing text;
  v_permission text;
begin
  if v_action_name='approve' then
    select lower(coalesce(workflow_stage,status)),lower(coalesce(pricing_type,'paid'))
      into v_stage,v_pricing
    from public.erp_maintenance_orders
    where company_id=p_company_id and id=p_order_id and not is_deleted;
    if not found then raise exception 'maintenance_order_not_found'; end if;
    v_permission:=case
      when v_stage in ('draft','order_draft') then 'order.approve'
      when v_stage='order_approved' then 'material_issue.create'
      when v_stage='stock_issue_draft' then 'material_issue.approve'
      when v_stage='stock_issue_approved' and v_pricing='paid' then 'invoice.create'
      when v_stage='stock_issue_approved' then 'order.approve'
      when v_stage='invoice_draft' then 'invoice.approve'
      else null end;
  elsif v_action_name in ('delete','cancel','reverse','reopen') then
    v_permission:='reverse';
  end if;
  if v_permission is not null then
    perform public.erp_r88_require_restricted_action(
      p_company_id,'maintenance',v_permission
    );
  end if;
  return public.erp_manage_maintenance_order_component_pre_r88(
    p_company_id,p_order_id,v_component,v_action_name,p_reason
  );
end;
$$;

revoke all on function public.erp_r37_advance_maintenance_workflow_pre_r88(uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_r57_execute_maintenance_material_issue_pre_r88(uuid,uuid,uuid,uuid,text,numeric,timestamptz) from public,anon,authenticated;
revoke all on function public.erp_r57_reverse_maintenance_material_issue_pre_r88(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.erp_v2300_record_maintenance_payment_batch_pre_r88(uuid,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.erp_manage_maintenance_order_component_pre_r88(uuid,uuid,text,text,text) from public,anon,authenticated;
revoke all on function public.erp_r37_advance_maintenance_workflow(uuid,uuid) from public,anon;
revoke all on function public.erp_r57_execute_maintenance_material_issue(uuid,uuid,uuid,uuid,text,numeric,timestamptz) from public,anon;
revoke all on function public.erp_r57_reverse_maintenance_material_issue(uuid,uuid,text) from public,anon;
revoke all on function public.erp_v2300_record_maintenance_payment_batch(uuid,uuid,jsonb) from public,anon;
revoke all on function public.erp_manage_maintenance_order_component(uuid,uuid,text,text,text) from public,anon;
grant execute on function public.erp_r37_advance_maintenance_workflow(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r57_execute_maintenance_material_issue(uuid,uuid,uuid,uuid,text,numeric,timestamptz) to authenticated,service_role;
grant execute on function public.erp_r57_reverse_maintenance_material_issue(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.erp_v2300_record_maintenance_payment_batch(uuid,uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_manage_maintenance_order_component(uuid,uuid,text,text,text) to authenticated,service_role;

-- ---------------------------------------------------------------------------
-- 2. Commercial component contract repair.
-- R22 accepted receipt/delivery but forwarded those values to v2/base, whose
-- canonical logistics type is "logistics". Normalize only at this adapter.
-- ---------------------------------------------------------------------------
create or replace function public.erp_manage_commercial_order_component_v3(
  p_company_id uuid,p_module text,p_order_id uuid,p_component_type text,
  p_component_id uuid,p_action text,p_reason text default null
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_module text:=lower(btrim(coalesce(p_module,'')));
  v_type text:=lower(btrim(coalesce(p_component_type,'')));
  v_action text:=lower(btrim(coalesce(p_action,'')));
  v_inner_type text;
  v_expected_type text;
  v_permission_action text;
  v_legacy_permission text;
  v_result jsonb;
begin
  if p_company_id is null then
    return jsonb_build_object('ok',false,'code','company_required','error','A company context is required.');
  end if;
  if p_order_id is null then
    return jsonb_build_object('ok',false,'code','order_required','error','A commercial order is required.');
  end if;
  if p_component_id is null then
    return jsonb_build_object('ok',false,'code','component_required','error','A workflow component is required.');
  end if;
  if v_module not in ('sales','purchases') then
    return jsonb_build_object('ok',false,'code','invalid_workflow_module','error','Unsupported workflow module.');
  end if;
  if v_type not in ('order','delivery','receipt','logistics','invoice','payment') then
    return jsonb_build_object('ok',false,'code','invalid_component_type','error','Unsupported workflow component.');
  end if;
  if v_action not in ('approve','delete','cancel','reverse','reopen') then
    return jsonb_build_object('ok',false,'code','invalid_component_action','error','Unsupported workflow action.');
  end if;

  v_expected_type:=case when v_module='sales' then 'delivery' else 'receipt' end;
  if v_type in ('delivery','receipt') and v_type<>v_expected_type then
    return jsonb_build_object(
      'ok',false,'code','workflow_component_type_mismatch',
      'error','The workflow component does not match the selected module.'
    );
  end if;
  v_inner_type:=case when v_type in ('delivery','receipt','logistics') then 'logistics' else v_type end;

  v_permission_action:=case
    when v_inner_type='order' and v_action='approve' then 'order.approve'
    when v_inner_type='logistics' and v_action='approve' then
      case when v_module='sales' then 'delivery.approve' else 'receipt.approve' end
    when v_inner_type='invoice' and v_action='approve' then 'invoice.approve'
    when v_action='delete' then 'delete'
    when v_action in ('cancel','reverse','reopen') then 'reverse'
    else v_action end;
  v_legacy_permission:=case
    when v_action='approve' then v_module||'.approve'
    when v_action='delete' then v_module||'.delete'
    else v_module||'.cancel' end;

  if not public.erp_r88_action_allowed(
    p_company_id,v_module,v_permission_action,v_legacy_permission
  ) then
    raise exception 'permission_denied:%.%',v_module,v_permission_action
      using errcode='42501';
  end if;

  if v_inner_type='invoice' and v_action='approve' then
    v_result:=public.erp_v762_approve_workflow_invoice(
      p_company_id,p_component_id,v_module
    );
  else
    v_result:=public.erp_manage_commercial_order_component_v2(
      p_company_id,v_module,p_order_id,v_inner_type,p_component_id,v_action,p_reason
    );
  end if;

  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'module',v_module,
    'orderId',p_order_id,
    'componentType',case when v_inner_type='logistics' then v_expected_type else v_type end,
    'canonicalComponentType',v_inner_type,
    'componentId',p_component_id,
    'action',v_action
  );
exception when others then
  return jsonb_build_object(
    'ok',false,'code',sqlstate,'error',sqlerrm,
    'details',jsonb_build_object(
      'module',v_module,'orderId',p_order_id,'componentType',v_type,
      'componentId',p_component_id,'action',v_action
    )::text
  );
end;
$$;

revoke all on function public.erp_manage_commercial_order_component_v3(
  uuid,text,uuid,text,uuid,text,text
) from public,anon;
grant execute on function public.erp_manage_commercial_order_component_v3(
  uuid,text,uuid,text,uuid,text,text
) to authenticated,service_role;

-- ---------------------------------------------------------------------------
-- 3. Trial-balance field filtering repair.
-- R9's generic accounting key mapper did not know the six detailed trial
-- balance debit/credit keys, so restricted-field users received blank values.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r88_filter_trial_balance_row(
  p_company_id uuid,p_payload jsonb
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_result jsonb:='{}'::jsonb;
  v_item record;
  v_field text;
begin
  if p_payload is null then return '{}'::jsonb; end if;
  if not public.erp_cloud_user_has_permission(p_company_id,'accounting.fields.restrict') then
    return p_payload;
  end if;

  for v_item in select key,value from jsonb_each(p_payload) loop
    v_field:=case v_item.key
      when 'openingDebit' then 'debit'
      when 'periodDebit' then 'debit'
      when 'closingDebit' then 'debit'
      when 'openingCredit' then 'credit'
      when 'periodCredit' then 'credit'
      when 'closingCredit' then 'credit'
      when 'parentAccountId' then 'parentAccount'
      when 'rootAccountCode' then 'accountCode'
      when 'rootAccountName' then 'accountName'
      when 'hierarchyPath' then 'accountName'
      when 'hierarchyDepth' then 'accountName'
      else public.erp_r9_result_field_for_key('accounting',v_item.key)
    end;
    if v_item.key in ('id','_cloudVersion','_cloudUpdatedAt')
       or (v_field is not null and public.erp_cloud_user_can_view_field(
         p_company_id,'accounting',v_field,null
       )) then
      v_result:=v_result||jsonb_build_object(v_item.key,v_item.value);
    end if;
  end loop;
  return v_result;
end;
$$;

create or replace function public.erp_r9_cloud_detailed_accounting_report(
  p_company_id uuid,p_report_type text,p_currency text default 'ALL',
  p_branch_id text default null,p_cost_center_id text default null,
  p_from_date timestamptz default null,p_to_date timestamptz default null
) returns setof jsonb
language plpgsql stable security definer set search_path=public as $$
declare v_field text;
begin
  v_field:=case lower(coalesce(p_report_type,''))
    when 'trialbalance' then 'trialBalance'
    when 'generalledger' then 'generalLedger'
    when 'journalledger' then 'generalLedger'
    else 'generalLedger' end;
  if not public.erp_cloud_user_can_view_field(
    p_company_id,'accounting',v_field,'accounting.view'
  ) then
    raise exception 'field_permission_denied:accounting.%',v_field using errcode='42501';
  end if;

  if lower(coalesce(p_report_type,''))='trialbalance' then
    return query
      select public.erp_r88_filter_trial_balance_row(p_company_id,x)
      from public.erp_cloud_detailed_accounting_report(
        p_company_id,p_report_type,p_currency,p_branch_id,p_cost_center_id,
        p_from_date,p_to_date
      ) x;
  else
    return query
      select public.erp_r9_filter_result_json(p_company_id,'accounting',x,null)
      from public.erp_cloud_detailed_accounting_report(
        p_company_id,p_report_type,p_currency,p_branch_id,p_cost_center_id,
        p_from_date,p_to_date
      ) x;
  end if;
end;
$$;

revoke all on function public.erp_r88_filter_trial_balance_row(uuid,jsonb)
  from public,anon;
grant execute on function public.erp_r88_filter_trial_balance_row(uuid,jsonb)
  to authenticated,service_role;
revoke all on function public.erp_r9_cloud_detailed_accounting_report(
  uuid,text,text,text,text,timestamptz,timestamptz
) from public,anon;
grant execute on function public.erp_r9_cloud_detailed_accounting_report(
  uuid,text,text,text,text,timestamptz,timestamptz
) to authenticated,service_role;

-- ---------------------------------------------------------------------------
-- 4. Cash Flow Statement boundary.
-- The report remains sourced from erp_cash_transactions only. Unknown movement
-- types that have neither explicit cashIn nor cashOut are excluded instead of
-- being inferred from a journal-style debit/credit sign.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r9_cloud_cash_flow_hierarchy(
  p_company_id uuid,p_currency text default 'ALL',p_branch_id text default null,
  p_cost_center_id text default null,p_from_date timestamptz default null,
  p_to_date timestamptz default null
) returns setof jsonb
language plpgsql stable security definer set search_path=public as $$
begin
  if not public.erp_cloud_user_can_view_field(
    p_company_id,'accounting','cashFlow','accounting.view'
  ) then
    raise exception 'field_permission_denied:accounting.cashFlow' using errcode='42501';
  end if;
  return query
  select x
  from public.erp_cloud_cash_flow_hierarchy(
    p_company_id,p_currency,p_branch_id,p_cost_center_id,p_from_date,p_to_date
  ) x
  where public.erp_try_numeric(x->>'cashIn',0)>0
     or public.erp_try_numeric(x->>'cashOut',0)>0;
end;
$$;

revoke all on function public.erp_r9_cloud_cash_flow_hierarchy(
  uuid,text,text,text,timestamptz,timestamptz
) from public,anon;
grant execute on function public.erp_r9_cloud_cash_flow_hierarchy(
  uuid,text,text,text,timestamptz,timestamptz
) to authenticated,service_role;

-- ---------------------------------------------------------------------------
-- 5. Sales/Purchases order lists: retain R84 record scope and expose creator
-- identity only when field policy permits it.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r9_list_cloud_sales_workflow_orders(
  p_company_id uuid
) returns setof jsonb
language sql stable security definer set search_path=public as $$
  select public.erp_r9_filter_result_json(p_company_id,'sales',x,'sales.view')
    || case
      when not public.erp_cloud_user_has_permission(p_company_id,'sales.fields.restrict')
        or public.erp_cloud_user_can_view_field(p_company_id,'sales','createdBy',null)
      then jsonb_build_object(
        'createdBy',o.created_by,
        'createdByName',coalesce(nullif(btrim(p.full_name),''),o.created_by::text,'')
      )
      else '{}'::jsonb end
  from public.erp_list_cloud_sales_workflow_orders(p_company_id) x
  join public.erp_sales_orders_cloud o
    on o.company_id=p_company_id and o.id::text=x->>'id' and not o.is_deleted
  left join public.profiles p on p.id=o.created_by
  where public.erp_r84_record_visible(p_company_id,'sales',o.created_by,null);
$$;

create or replace function public.erp_r9_list_cloud_purchase_workflow_orders(
  p_company_id uuid
) returns setof jsonb
language sql stable security definer set search_path=public as $$
  select public.erp_r9_filter_result_json(p_company_id,'purchases',x,'purchases.view')
    || case
      when not public.erp_cloud_user_has_permission(p_company_id,'purchases.fields.restrict')
        or public.erp_cloud_user_can_view_field(p_company_id,'purchases','createdBy',null)
      then jsonb_build_object(
        'createdBy',o.created_by,
        'createdByName',coalesce(nullif(btrim(p.full_name),''),o.created_by::text,'')
      )
      else '{}'::jsonb end
  from public.erp_list_cloud_purchase_workflow_orders(p_company_id) x
  join public.erp_purchase_orders_cloud o
    on o.company_id=p_company_id and o.id::text=x->>'id' and not o.is_deleted
  left join public.profiles p on p.id=o.created_by
  where public.erp_r84_record_visible(p_company_id,'purchases',o.created_by,null);
$$;

revoke all on function public.erp_r9_list_cloud_sales_workflow_orders(uuid)
  from public,anon;
revoke all on function public.erp_r9_list_cloud_purchase_workflow_orders(uuid)
  from public,anon;
grant execute on function public.erp_r9_list_cloud_sales_workflow_orders(uuid)
  to authenticated,service_role;
grant execute on function public.erp_r9_list_cloud_purchase_workflow_orders(uuid)
  to authenticated,service_role;

create or replace function public.erp_r87_list_cloud_maintenance_orders(
  p_company_id uuid
) returns setof jsonb
language sql stable security definer set search_path=public as $$
  select row_value
    || case
      when row_value ? 'totalCost' then jsonb_build_object(
        'materialCostTotalsByCurrency',
        public.erp_r87_maintenance_material_cost_totals(
          p_company_id,(row_value->>'id')::uuid,false
        )
      ) else '{}'::jsonb end
    || case
      when not public.erp_cloud_user_has_permission(p_company_id,'maintenance.fields.restrict')
        or public.erp_cloud_user_can_view_field(p_company_id,'maintenance','createdBy',null)
      then jsonb_build_object(
        'createdBy',o.created_by,
        'createdByName',coalesce(nullif(btrim(p.full_name),''),o.created_by::text,''),
        'createdAt',o.created_at
      ) else '{}'::jsonb end
    || case
      when public.erp_cloud_user_can_view_field(
        p_company_id,'maintenance','invoice','maintenance.view'
      ) then jsonb_build_object(
        'invoiceCreatedBy',coalesce(
          (select nullif(btrim(ip.full_name),'')
           from public.erp_audit_log al
           left join public.profiles ip on ip.id::text=al.actor_uid
           where al.company_id=p_company_id
             and al.table_name='erp_maintenance_orders'
             and al.record_id=o.id::text
             and al.operation='UPDATE'
             and al.new_data->>'workflow_stage'='invoice_draft'
           order by al.occurred_at asc,al.id asc limit 1),
          (select al.actor_uid
           from public.erp_audit_log al
           where al.company_id=p_company_id
             and al.table_name='erp_maintenance_orders'
             and al.record_id=o.id::text
             and al.operation='UPDATE'
             and al.new_data->>'workflow_stage'='invoice_draft'
           order by al.occurred_at asc,al.id asc limit 1),
          ''
        ),
        'invoiceCreatedAt',(
          select al.occurred_at
          from public.erp_audit_log al
          where al.company_id=p_company_id
            and al.table_name='erp_maintenance_orders'
            and al.record_id=o.id::text
            and al.operation='UPDATE'
            and al.new_data->>'workflow_stage'='invoice_draft'
          order by al.occurred_at asc,al.id asc limit 1
        ),
        'invoiceApprovedBy',coalesce(
          (select nullif(btrim(ip.full_name),'')
           from public.erp_audit_log al
           left join public.profiles ip on ip.id::text=al.actor_uid
           where al.company_id=p_company_id
             and al.table_name='erp_maintenance_orders'
             and al.record_id=o.id::text
             and al.operation='UPDATE'
             and al.new_data->>'workflow_stage'='invoice_approved'
           order by al.occurred_at desc,al.id desc limit 1),
          (select al.actor_uid
           from public.erp_audit_log al
           where al.company_id=p_company_id
             and al.table_name='erp_maintenance_orders'
             and al.record_id=o.id::text
             and al.operation='UPDATE'
             and al.new_data->>'workflow_stage'='invoice_approved'
           order by al.occurred_at desc,al.id desc limit 1),
          ''
        ),
        'invoiceApprovedAt',(
          select al.occurred_at
          from public.erp_audit_log al
          where al.company_id=p_company_id
            and al.table_name='erp_maintenance_orders'
            and al.record_id=o.id::text
            and al.operation='UPDATE'
            and al.new_data->>'workflow_stage'='invoice_approved'
          order by al.occurred_at desc,al.id desc limit 1
        )
      ) else '{}'::jsonb end
  from public.erp_r9_list_cloud_maintenance_orders(p_company_id) row_value
  join public.erp_maintenance_orders o
    on o.company_id=p_company_id
   and o.id=(row_value->>'id')::uuid
   and not o.is_deleted
  left join public.profiles p on p.id=o.created_by;
$$;
revoke all on function public.erp_r87_list_cloud_maintenance_orders(uuid)
  from public,anon;
grant execute on function public.erp_r87_list_cloud_maintenance_orders(uuid)
  to authenticated,service_role;

-- Cashbox transaction reads are action-gated and field-filtered so enabling
-- cashbox.actions.restrict / cashbox.fields.restrict does not remain UI-only.
create or replace function public.erp_r88_filter_cashbox_transaction(
  p_company_id uuid,p_payload jsonb
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_result jsonb:='{}'::jsonb;
  v_item record;
  v_field text;
begin
  if p_payload is null then return '{}'::jsonb; end if;
  if not public.erp_cloud_user_has_permission(p_company_id,'cashbox.fields.restrict') then
    return p_payload;
  end if;
  for v_item in select key,value from jsonb_each(p_payload) loop
    v_field:=case v_item.key
      when 'voucherNumber' then 'documentNumber'
      when 'type' then 'transactionType'
      when 'category' then 'purpose'
      when 'amount' then 'amount'
      when 'currency' then 'currency'
      when 'transactionDate' then 'operationalDate'
      when 'partyType' then 'partyType'
      when 'partyId' then 'partyId'
      when 'partyName' then 'partyName'
      when 'paymentMethod' then 'paymentMethod'
      when 'referenceType' then 'reference'
      when 'referenceId' then 'reference'
      when 'notes' then 'notes'
      when 'cashAccountId' then 'cashAccount'
      when 'counterAccountId' then 'counterAccount'
      when 'journalEntryId' then 'journalEntryId'
      when 'performedBy' then 'performedBy'
      when 'status' then 'transactionStatus'
      when 'createdAt' then 'auditMetadata'
      when 'updatedAt' then 'auditMetadata'
      when 'created_at' then 'auditMetadata'
      when 'updated_at' then 'auditMetadata'
      else null end;
    if v_item.key in ('id','_cloudVersion','_cloudCreatedAt','_cloudUpdatedAt')
       or (v_field is not null and public.erp_cloud_user_can_view_field(
         p_company_id,'cashbox',v_field,null
       )) then
      v_result:=v_result||jsonb_build_object(v_item.key,v_item.value);
    end if;
  end loop;
  return v_result;
end;
$$;

create or replace function public.erp_r28_list_cash_transactions(p_company_id uuid)
returns setof jsonb
language sql stable security definer set search_path=public
as $$
  select public.erp_r88_filter_cashbox_transaction(
    p_company_id,
    ct.data || jsonb_build_object(
      'id',ct.id,
      'transactionDate',coalesce(
        nullif(ct.data->>'transactionDate',''),
        nullif(ct.data->>'transaction_date',''),
        ct.created_at::text
      ),
      'createdAt',ct.created_at,
      'created_at',ct.created_at,
      'updatedAt',ct.updated_at,
      'updated_at',ct.updated_at,
      '_cloudCreatedAt',ct.created_at,
      '_cloudUpdatedAt',ct.updated_at,
      '_cloudVersion',ct.version,
      'performedBy',coalesce(pr.full_name,ct.created_by::text),
      'status',coalesce(nullif(ct.data->>'status',''),'posted')
    )
  )
  from public.erp_cash_transactions ct
  left join public.profiles pr on pr.id=ct.created_by
  where ct.company_id=p_company_id
    and not ct.is_deleted
    and public.is_active_company_member(p_company_id)
    and public.erp_r88_action_allowed(
      p_company_id,'cashbox','transaction.view','accounting.view'
    )
  order by public.erp_try_timestamptz(
    coalesce(ct.data->>'transactionDate',ct.data->>'transaction_date'),
    ct.created_at
  ) desc,ct.created_at desc,ct.id desc
$$;

revoke all on function public.erp_r88_filter_cashbox_transaction(uuid,jsonb) from public,anon;
grant execute on function public.erp_r88_filter_cashbox_transaction(uuid,jsonb) to authenticated,service_role;
revoke all on function public.erp_r28_list_cash_transactions(uuid) from public,anon;
grant execute on function public.erp_r28_list_cash_transactions(uuid) to authenticated,service_role;

-- ---------------------------------------------------------------------------
-- 6. Vehicle maintenance schedules and free-form history details.
-- ---------------------------------------------------------------------------
create table if not exists public.erp_vehicle_maintenance_schedules (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  car_id text not null,
  title text not null,
  description text,
  due_at timestamptz not null,
  recurrence text not null default 'none',
  assigned_user_id uuid references auth.users(id) on delete set null,
  created_by uuid references auth.users(id) on delete set null,
  reminder_minutes integer not null default 1440 check(reminder_minutes>=0),
  status text not null default 'scheduled',
  linked_maintenance_order_id uuid,
  last_reminded_at timestamptz,
  is_deleted boolean not null default false,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(recurrence in ('none','daily','weekly','monthly','yearly')),
  check(status in ('scheduled','due','completed','cancelled','converted'))
);

create index if not exists erp_vehicle_maintenance_schedules_car_idx
  on public.erp_vehicle_maintenance_schedules(company_id,car_id,due_at)
  where not is_deleted;
create index if not exists erp_vehicle_maintenance_schedules_assignee_idx
  on public.erp_vehicle_maintenance_schedules(company_id,assigned_user_id,due_at)
  where not is_deleted and status in ('scheduled','due');

create table if not exists public.erp_maintenance_history_details (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  car_id text not null,
  maintenance_order_id uuid,
  title text not null,
  description text not null default '',
  sort_order integer not null default 0,
  created_by uuid references auth.users(id) on delete set null,
  is_deleted boolean not null default false,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists erp_maintenance_history_details_car_idx
  on public.erp_maintenance_history_details(
    company_id,car_id,maintenance_order_id,sort_order,created_at
  ) where not is_deleted;

alter table public.erp_vehicle_maintenance_schedules enable row level security;
alter table public.erp_maintenance_history_details enable row level security;

drop policy if exists erp_r88_schedule_select on public.erp_vehicle_maintenance_schedules;
create policy erp_r88_schedule_select on public.erp_vehicle_maintenance_schedules
for select to authenticated using (
  public.is_active_company_member(company_id)
  and public.erp_cloud_user_has_permission(company_id,'maintenance.view')
  and public.erp_cloud_user_can_view_field(
    company_id,'maintenance','maintenanceSchedule','maintenance.view'
  )
);
drop policy if exists erp_r88_schedule_write on public.erp_vehicle_maintenance_schedules;
create policy erp_r88_schedule_write on public.erp_vehicle_maintenance_schedules
for all to authenticated using (
  public.is_active_company_member(company_id)
  and public.erp_r88_action_allowed(
    company_id,'maintenance','schedule.update','maintenance.update'
  )
  and public.erp_cloud_user_can_edit_field(
    company_id,'maintenance','maintenanceSchedule','maintenance.update'
  )
) with check (
  public.is_active_company_member(company_id)
  and public.erp_r88_action_allowed(
    company_id,'maintenance','schedule.update','maintenance.update'
  )
  and public.erp_cloud_user_can_edit_field(
    company_id,'maintenance','maintenanceSchedule','maintenance.update'
  )
);

drop policy if exists erp_r88_history_detail_select on public.erp_maintenance_history_details;
create policy erp_r88_history_detail_select on public.erp_maintenance_history_details
for select to authenticated using (
  public.is_active_company_member(company_id)
  and public.erp_cloud_user_can_view_field(
    company_id,'cars','maintenanceHistory','cars.view'
  )
  and public.erp_cloud_user_can_view_field(
    company_id,'maintenance','maintenanceHistoryDetails','maintenance.view'
  )
);
drop policy if exists erp_r88_history_detail_write on public.erp_maintenance_history_details;
create policy erp_r88_history_detail_write on public.erp_maintenance_history_details
for all to authenticated using (
  public.is_active_company_member(company_id)
  and public.erp_r88_action_allowed(
    company_id,'maintenance','history_detail.edit','maintenance.update'
  )
  and public.erp_cloud_user_can_edit_field(
    company_id,'maintenance','maintenanceHistoryDetails','maintenance.update'
  )
) with check (
  public.is_active_company_member(company_id)
  and public.erp_r88_action_allowed(
    company_id,'maintenance','history_detail.edit','maintenance.update'
  )
  and public.erp_cloud_user_can_edit_field(
    company_id,'maintenance','maintenanceHistoryDetails','maintenance.update'
  )
);

create or replace function public.erp_r88_list_vehicle_maintenance_schedules(
  p_company_id uuid,p_car_id text
) returns setof jsonb
language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'id',s.id,'carId',s.car_id,'title',s.title,'description',coalesce(s.description,''),
    'dueAt',s.due_at,'recurrence',s.recurrence,
    'assignedUserId',s.assigned_user_id,
    'assignedUserName',coalesce(ap.full_name,''),
    'createdBy',s.created_by,'createdByName',coalesce(cp.full_name,''),
    'reminderMinutes',s.reminder_minutes,'status',s.status,
    'linkedMaintenanceOrderId',s.linked_maintenance_order_id,
    'linkedMaintenanceOrderNumber',coalesce(m.order_number,''),
    'lastRemindedAt',s.last_reminded_at,
    'createdAt',s.created_at,'updatedAt',s.updated_at
  )
  from public.erp_vehicle_maintenance_schedules s
  left join public.profiles ap on ap.id=s.assigned_user_id
  left join public.profiles cp on cp.id=s.created_by
  left join public.erp_maintenance_orders m
    on m.company_id=s.company_id and m.id=s.linked_maintenance_order_id and not m.is_deleted
  where s.company_id=p_company_id and s.car_id=p_car_id and not s.is_deleted
    and public.is_active_company_member(p_company_id)
    and public.erp_cloud_user_has_permission(p_company_id,'maintenance.view')
    and public.erp_cloud_user_can_view_field(
      p_company_id,'maintenance','maintenanceSchedule','maintenance.view'
    )
  order by
    case s.status when 'due' then 0 when 'scheduled' then 1 when 'converted' then 2 else 3 end,
    s.due_at,s.created_at;
$$;

create or replace function public.erp_r88_save_vehicle_maintenance_schedule(
  p_company_id uuid,p_schedule jsonb
) returns uuid
language plpgsql security definer set search_path=public as $$
declare
  v_id uuid;
  v_existing public.erp_vehicle_maintenance_schedules%rowtype;
  v_car_id text:=nullif(btrim(coalesce(p_schedule->>'carId','')),'');
  v_assigned uuid;
  v_required_action text;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_cloud_user_can_edit_field(
    p_company_id,'maintenance','maintenanceSchedule','maintenance.update'
  ) then
    raise exception 'permission_denied:maintenance.fields.maintenanceSchedule.edit' using errcode='42501';
  end if;
  if v_car_id is null then raise exception 'car_required'; end if;
  if not exists(
    select 1 from public.erp_cars c
    where c.company_id=p_company_id and c.id=v_car_id and not c.is_deleted
  ) then raise exception 'car_not_found'; end if;

  begin v_id:=nullif(p_schedule->>'id','')::uuid; exception when others then v_id:=null; end;
  if v_id is not null then
    select * into v_existing from public.erp_vehicle_maintenance_schedules
    where company_id=p_company_id and id=v_id and not is_deleted for update;
  end if;
  v_required_action:=case when found then 'schedule.update' else 'schedule.create' end;
  if not public.erp_r88_action_allowed(
    p_company_id,'maintenance',v_required_action,
    case when found then 'maintenance.update' else 'maintenance.create' end
  ) then raise exception 'permission_denied:maintenance.%',v_required_action using errcode='42501';
  end if;

  begin
    v_assigned:=nullif(p_schedule->>'assignedUserId','')::uuid;
  exception when others then
    raise exception 'invalid_assigned_user';
  end;
  if v_assigned is null then v_assigned:=auth.uid(); end if;
  if v_assigned<>auth.uid()
     and not public.erp_r88_action_allowed(
       p_company_id,'maintenance','schedule.assign_other','maintenance.update'
     ) then
    raise exception 'permission_denied:maintenance.schedule.assign_other' using errcode='42501';
  end if;
  if not exists(
    select 1 from public.company_memberships cm
    where cm.company_id=p_company_id and cm.user_id=v_assigned and cm.is_active
  ) then raise exception 'assigned_user_not_company_member'; end if;

  if v_existing.id is null then
    v_id:=coalesce(v_id,gen_random_uuid());
    insert into public.erp_vehicle_maintenance_schedules(
      id,company_id,car_id,title,description,due_at,recurrence,
      assigned_user_id,created_by,reminder_minutes,status,
      linked_maintenance_order_id,created_at,updated_at
    ) values(
      v_id,p_company_id,v_car_id,
      coalesce(nullif(btrim(p_schedule->>'title'),''),'Maintenance'),
      nullif(btrim(p_schedule->>'description'),''),
      (p_schedule->>'dueAt')::timestamptz,
      coalesce(nullif(lower(btrim(p_schedule->>'recurrence')),''),'none'),
      v_assigned,auth.uid(),greatest(coalesce((p_schedule->>'reminderMinutes')::integer,1440),0),
      coalesce(nullif(lower(btrim(p_schedule->>'status')),''),'scheduled'),
      nullif(p_schedule->>'linkedMaintenanceOrderId','')::uuid,now(),now()
    );
  else
    update public.erp_vehicle_maintenance_schedules set
      car_id=v_car_id,
      title=coalesce(nullif(btrim(p_schedule->>'title'),''),title),
      description=coalesce(p_schedule->>'description',description),
      due_at=coalesce(nullif(p_schedule->>'dueAt','')::timestamptz,due_at),
      recurrence=coalesce(nullif(lower(btrim(p_schedule->>'recurrence')),''),recurrence),
      assigned_user_id=v_assigned,
      reminder_minutes=greatest(coalesce((p_schedule->>'reminderMinutes')::integer,reminder_minutes),0),
      status=coalesce(nullif(lower(btrim(p_schedule->>'status')),''),status),
      linked_maintenance_order_id=coalesce(
        nullif(p_schedule->>'linkedMaintenanceOrderId','')::uuid,
        linked_maintenance_order_id
      ),
      updated_at=now()
    where company_id=p_company_id and id=v_existing.id;
    v_id:=v_existing.id;
  end if;
  return v_id;
end;
$$;

create or replace function public.erp_r88_delete_vehicle_maintenance_schedule(
  p_company_id uuid,p_schedule_id uuid
) returns void
language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_cloud_user_can_edit_field(
    p_company_id,'maintenance','maintenanceSchedule','maintenance.update'
  ) then
    raise exception 'permission_denied:maintenance.fields.maintenanceSchedule.edit' using errcode='42501';
  end if;
  if not public.erp_r88_action_allowed(
    p_company_id,'maintenance','schedule.delete','maintenance.delete'
  ) then raise exception 'permission_denied:maintenance.schedule.delete' using errcode='42501';
  end if;
  update public.erp_vehicle_maintenance_schedules
  set is_deleted=true,deleted_at=now(),updated_at=now()
  where company_id=p_company_id and id=p_schedule_id and not is_deleted;
end;
$$;

create or replace function public.erp_r88_link_maintenance_schedule_order(
  p_company_id uuid,p_schedule_id uuid,p_maintenance_order_id uuid
) returns void
language plpgsql security definer set search_path=public as $$
declare v_car_id text; v_order_car text;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_cloud_user_can_edit_field(
    p_company_id,'maintenance','maintenanceSchedule','maintenance.update'
  ) then
    raise exception 'permission_denied:maintenance.fields.maintenanceSchedule.edit' using errcode='42501';
  end if;
  if not public.erp_r88_action_allowed(
    p_company_id,'maintenance','schedule.convert','maintenance.create'
  ) then raise exception 'permission_denied:maintenance.schedule.convert' using errcode='42501';
  end if;
  select car_id into v_car_id from public.erp_vehicle_maintenance_schedules
  where company_id=p_company_id and id=p_schedule_id and not is_deleted for update;
  if v_car_id is null then raise exception 'schedule_not_found'; end if;
  select car_id::text into v_order_car from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_maintenance_order_id and not is_deleted;
  if v_order_car is null then raise exception 'maintenance_order_not_found'; end if;
  if v_order_car<>v_car_id then raise exception 'schedule_order_car_mismatch'; end if;
  update public.erp_vehicle_maintenance_schedules
  set linked_maintenance_order_id=p_maintenance_order_id,status='converted',updated_at=now()
  where company_id=p_company_id and id=p_schedule_id;
end;
$$;

create or replace function public.erp_r88_list_maintenance_history_details(
  p_company_id uuid,p_car_id text,p_maintenance_order_id uuid default null
) returns setof jsonb
language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'id',d.id,'carId',d.car_id,'maintenanceOrderId',d.maintenance_order_id,
    'title',d.title,'description',d.description,'sortOrder',d.sort_order,
    'createdBy',d.created_by,'createdByName',coalesce(p.full_name,''),
    'createdAt',d.created_at,'updatedAt',d.updated_at
  )
  from public.erp_maintenance_history_details d
  left join public.profiles p on p.id=d.created_by
  where d.company_id=p_company_id and d.car_id=p_car_id and not d.is_deleted
    and (p_maintenance_order_id is null or d.maintenance_order_id=p_maintenance_order_id)
    and public.is_active_company_member(p_company_id)
    and public.erp_cloud_user_can_view_field(
      p_company_id,'cars','maintenanceHistory','cars.view'
    )
    and public.erp_cloud_user_can_view_field(
      p_company_id,'maintenance','maintenanceHistoryDetails','maintenance.view'
    )
  order by d.maintenance_order_id,d.sort_order,d.created_at;
$$;

create or replace function public.erp_r88_save_maintenance_history_detail(
  p_company_id uuid,p_detail jsonb
) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_car_id text; v_order_id uuid;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_cloud_user_can_edit_field(
    p_company_id,'maintenance','maintenanceHistoryDetails','maintenance.update'
  ) then
    raise exception 'permission_denied:maintenance.fields.maintenanceHistoryDetails.edit' using errcode='42501';
  end if;
  if not public.erp_r88_action_allowed(
    p_company_id,'maintenance','history_detail.edit','maintenance.update'
  ) then raise exception 'permission_denied:maintenance.history_detail.edit' using errcode='42501';
  end if;
  v_car_id:=nullif(btrim(coalesce(p_detail->>'carId','')),'');
  if v_car_id is null then raise exception 'car_required'; end if;
  begin v_id:=nullif(p_detail->>'id','')::uuid; exception when others then v_id:=null; end;
  begin v_order_id:=nullif(p_detail->>'maintenanceOrderId','')::uuid; exception when others then v_order_id:=null; end;
  if v_order_id is not null and not exists(
    select 1 from public.erp_maintenance_orders m
    where m.company_id=p_company_id and m.id=v_order_id and not m.is_deleted
      and m.car_id::text=v_car_id
  ) then raise exception 'maintenance_history_order_car_mismatch'; end if;

  if v_id is null then
    v_id:=gen_random_uuid();
    insert into public.erp_maintenance_history_details(
      id,company_id,car_id,maintenance_order_id,title,description,sort_order,created_by
    ) values(
      v_id,p_company_id,v_car_id,v_order_id,
      coalesce(nullif(btrim(p_detail->>'title'),''),'Detail'),
      coalesce(p_detail->>'description',''),
      coalesce((p_detail->>'sortOrder')::integer,0),auth.uid()
    );
  else
    update public.erp_maintenance_history_details set
      title=coalesce(nullif(btrim(p_detail->>'title'),''),title),
      description=coalesce(p_detail->>'description',description),
      sort_order=coalesce((p_detail->>'sortOrder')::integer,sort_order),
      updated_at=now()
    where company_id=p_company_id and id=v_id and car_id=v_car_id and not is_deleted;
    if not found then raise exception 'maintenance_history_detail_not_found'; end if;
  end if;
  return v_id;
end;
$$;

create or replace function public.erp_r88_delete_maintenance_history_detail(
  p_company_id uuid,p_detail_id uuid
) returns void
language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_cloud_user_can_edit_field(
    p_company_id,'maintenance','maintenanceHistoryDetails','maintenance.update'
  ) then
    raise exception 'permission_denied:maintenance.fields.maintenanceHistoryDetails.edit' using errcode='42501';
  end if;
  if not public.erp_r88_action_allowed(
    p_company_id,'maintenance','history_detail.edit','maintenance.update'
  ) then raise exception 'permission_denied:maintenance.history_detail.edit' using errcode='42501';
  end if;
  update public.erp_maintenance_history_details
  set is_deleted=true,deleted_at=now(),updated_at=now()
  where company_id=p_company_id and id=p_detail_id and not is_deleted;
end;
$$;

-- Detailed, permission-filtered vehicle service card. The legacy R56 RPC is
-- retained as an internal implementation detail but no longer exposed directly
-- to authenticated clients after this migration.
create or replace function public.erp_r88_vehicle_service_card(
  p_company_id uuid,p_car_id text
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_base jsonb;
  v_vehicle jsonb;
  v_history jsonb:='[]'::jsonb;
  v_schedules jsonb:='[]'::jsonb;
  v_row jsonb;
  v_filtered jsonb;
  v_order public.erp_maintenance_orders%rowtype;
  v_creator_name text;
  v_details jsonb;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_cloud_user_has_permission(p_company_id,'cars.view')
     or not public.erp_cloud_user_has_permission(p_company_id,'maintenance.view') then
    raise exception 'permission_denied:vehicle_service_card' using errcode='42501';
  end if;

  v_base:=public.erp_r56_vehicle_service_card(p_company_id,p_car_id);
  v_vehicle:=public.erp_r9_filter_result_json(
    p_company_id,'cars',coalesce(v_base->'vehicle','{}'::jsonb),'cars.view'
  );

  for v_row in
    select value from jsonb_array_elements(
      coalesce(v_base->'maintenanceHistory','[]'::jsonb)
    )
  loop
    select * into v_order
    from public.erp_maintenance_orders o
    where o.company_id=p_company_id
      and o.id=(v_row->>'id')::uuid
      and not o.is_deleted;
    if not found then continue; end if;
    if not public.erp_r84_record_visible(
      p_company_id,'maintenance',v_order.created_by,null
    ) then continue; end if;

    select coalesce(full_name,'') into v_creator_name
    from public.profiles where id=v_order.created_by;
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',d.id,'title',d.title,'description',d.description,
      'sortOrder',d.sort_order,'createdBy',d.created_by,
      'createdByName',coalesce(p.full_name,''),'createdAt',d.created_at
    ) order by d.sort_order,d.created_at),'[]'::jsonb)
    into v_details
    from public.erp_maintenance_history_details d
    left join public.profiles p on p.id=d.created_by
    where d.company_id=p_company_id and d.car_id=p_car_id
      and d.maintenance_order_id=v_order.id and not d.is_deleted;

    v_filtered:=public.erp_r9_filter_result_json(
      p_company_id,'maintenance',
      v_row||jsonb_build_object(
        'laborCost',v_order.labor_cost,
        'partsCost',v_order.parts_cost,
        'totalCost',v_order.total_cost,
        'profit',v_order.profit,
        'createdAt',v_order.created_at,
        'createdBy',v_order.created_by,
        'createdByName',coalesce(v_creator_name,''),
        'responsibleUser',coalesce(v_creator_name,''),
        'materialIssues',case when v_order.stock_issue_number is null
          then '[]'::jsonb
          else jsonb_build_array(jsonb_build_object(
            'reference',v_order.stock_issue_number,
            'status',case when v_order.workflow_stage in(
              'stock_issue_approved','invoice_draft','invoice_approved','paid','completed'
            ) then 'approved' else 'draft' end,
            'warehouseId',v_order.source_warehouse_id,
            'warehouseName',v_row->>'warehouseName'
          )) end,
        'invoiceReferences',case when v_order.invoice_number is null
          then '[]'::jsonb
          else jsonb_build_array(jsonb_build_object(
            'reference',v_order.invoice_number,
            'status',v_row->>'invoiceStatus'
          )) end,
        'paymentReferences',coalesce(v_row->'payments','[]'::jsonb)
      ),'maintenance.view'
    );

    if not public.erp_cloud_user_has_permission(
      p_company_id,'maintenance.fields.restrict'
    ) or public.erp_cloud_user_can_view_field(
      p_company_id,'maintenance','createdBy',null
    ) then
      v_filtered:=v_filtered||jsonb_build_object(
        'createdBy',v_order.created_by,'createdByName',coalesce(v_creator_name,''),
        'responsibleUser',coalesce(v_creator_name,'')
      );
    end if;
    if public.erp_cloud_user_can_view_field(
      p_company_id,'cars','maintenanceHistory','cars.view'
    ) then
      v_filtered:=v_filtered||jsonb_build_object(
        'materialIssues',case when v_order.stock_issue_number is null
          then '[]'::jsonb
          else jsonb_build_array(jsonb_build_object(
            'reference',v_order.stock_issue_number,
            'status',case when v_order.workflow_stage in(
              'stock_issue_approved','invoice_draft','invoice_approved','paid','completed'
            ) then 'approved' else 'draft' end,
            'warehouseId',v_order.source_warehouse_id,
            'warehouseName',v_row->>'warehouseName'
          )) end,
        'invoiceReferences',case when v_order.invoice_number is null
          then '[]'::jsonb
          else jsonb_build_array(jsonb_build_object(
            'reference',v_order.invoice_number,'status',v_row->>'invoiceStatus'
          )) end,
        'paymentReferences',coalesce(v_row->'payments','[]'::jsonb)
      );
    end if;
    if public.erp_cloud_user_can_view_field(
      p_company_id,'cars','maintenanceHistory','cars.view'
    ) and public.erp_cloud_user_can_view_field(
      p_company_id,'maintenance','maintenanceHistoryDetails','maintenance.view'
    ) then
      v_filtered:=v_filtered||jsonb_build_object(
        'customDetails',coalesce(v_details,'[]'::jsonb)
      );
    end if;
    v_history:=v_history||jsonb_build_array(v_filtered);
  end loop;

  select coalesce(jsonb_agg(x),'[]'::jsonb) into v_schedules
  from public.erp_r88_list_vehicle_maintenance_schedules(p_company_id,p_car_id) x;

  return jsonb_build_object(
    'vehicle',v_vehicle,
    'maintenanceSchedules',coalesce(v_schedules,'[]'::jsonb),
    'maintenanceHistory',v_history,
    'profileVersion','R88'
  );
end;
$$;

revoke all on function public.erp_r88_vehicle_service_card(uuid,text) from public,anon;
grant execute on function public.erp_r88_vehicle_service_card(uuid,text)
  to authenticated,service_role;
-- Prevent direct client bypass of R88 field filtering.
revoke execute on function public.erp_r56_vehicle_service_card(uuid,text)
  from authenticated;


-- Detailed maintenance payment read model for the operational document table.
create or replace function public.erp_r88_list_maintenance_payments(
  p_company_id uuid,p_order_id uuid
) returns setof jsonb
language plpgsql stable security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_cloud_user_has_permission(p_company_id,'maintenance.view')
     or not public.erp_cloud_user_can_view_field(
       p_company_id,'maintenance','payments','maintenance.view'
     ) then
    raise exception 'field_permission_denied:maintenance.payments' using errcode='42501';
  end if;
  if not exists(
    select 1 from public.erp_maintenance_orders o
    where o.company_id=p_company_id and o.id=p_order_id and not o.is_deleted
      and public.erp_r84_record_visible(p_company_id,'maintenance',o.created_by,null)
  ) then return; end if;
  return query
  select jsonb_build_object(
    'id',p.id,'paymentReference',coalesce(p.payment_key,p.id::text),
    'cashTransactionId',p.cash_transaction_id,
    'cashboxId',coalesce(p.payment_payload->>'cashAccountId',''),
    'cashboxName',coalesce(ca.data->>'name',''),
    'currency',upper(p.currency_code),'amount',p.amount,
    'invoiceAmount',p.amount_in_order_currency,
    'invoiceCurrency',coalesce(p.payment_payload->>'invoiceCurrency',''),
    'exchangeRate',p.exchange_rate,
    'exchangeDifference',public.erp_try_numeric(p.payment_payload->>'exchangeDifference',0),
    'paymentDate',p.payment_date,
    'userId',p.updated_by,'userName',coalesce(pr.full_name,''),
    'relatedInvoice',coalesce(o.invoice_number,''),
    'relatedOrder',o.order_number,'status',case when p.is_deleted then 'deleted' else 'posted' end,
    'notes',coalesce(p.notes,''),'journalEntryId',p.journal_entry_id
  )
  from public.erp_maintenance_payments p
  join public.erp_maintenance_orders o
    on o.company_id=p.company_id and o.id=p.maintenance_order_id
  left join public.erp_cash_accounts ca
    on ca.company_id=p.company_id
   and ca.id=coalesce(p.payment_payload->>'cashAccountId','')
   and not ca.is_deleted
  left join public.profiles pr on pr.id=p.updated_by
  where p.company_id=p_company_id and p.maintenance_order_id=p_order_id
    and not p.is_deleted
  order by p.payment_date desc,p.created_at desc;
end;
$$;
revoke all on function public.erp_r88_list_maintenance_payments(uuid,uuid)
  from public,anon;
grant execute on function public.erp_r88_list_maintenance_payments(uuid,uuid)
  to authenticated,service_role;

-- ---------------------------------------------------------------------------
-- 7. Maintenance schedule reminders.
-- Materialization is idempotent through the existing eventKey unique index.
-- It can be invoked by the Notification Center refresh and by an external cron.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r88_materialize_maintenance_schedule_reminders(
  p_company_id uuid,p_now timestamptz default now()
) returns integer
language plpgsql security definer set search_path=public as $$
declare r record; v_count integer:=0; v_event_key text; v_car_name text;
begin
  perform public.erp_active_company_context(p_company_id);
  for r in
    select s.*,coalesce(ap.full_name,'') assigned_name,
      coalesce(cp.full_name,'') creator_name
    from public.erp_vehicle_maintenance_schedules s
    left join public.profiles ap on ap.id=s.assigned_user_id
    left join public.profiles cp on cp.id=s.created_by
    where s.company_id=p_company_id and not s.is_deleted
      and s.status in ('scheduled','due')
      and s.due_at-(s.reminder_minutes||' minutes')::interval<=p_now
      and (s.last_reminded_at is null or s.last_reminded_at<s.updated_at)
  loop
    select coalesce(
      nullif(c.data->>'displayName',''),nullif(c.data->>'name',''),
      nullif(c.data->>'model',''),r.car_id
    ) into v_car_name
    from public.erp_cars c
    where c.company_id=p_company_id and c.id=r.car_id;
    v_event_key:='r88:maintenance_schedule:'||r.id::text||':'||r.updated_at::text;
    insert into public.erp_enterprise_notifications(company_id,id,data)
    values(p_company_id,gen_random_uuid(),jsonb_build_object(
      'eventKey',v_event_key,
      'eventType','maintenance_schedule_reminder',
      'event','maintenance_schedule_reminder','type','reminder',
      'module','maintenance','userId',r.assigned_user_id::text,
      'targetUserId',r.assigned_user_id,'targetUser',r.assigned_name,
      'actorUserId',r.created_by,'actorUser',r.creator_name,
      'referenceType','maintenance_schedule','referenceId',r.id::text,
      'documentReference',r.title,'carId',r.car_id,'carName',coalesce(v_car_name,r.car_id),
      'dueAt',r.due_at,'reminderMinutes',r.reminder_minutes,
      'titleAr','تذكير صيانة: '||r.title,
      'titleEn','Maintenance reminder: '||r.title,
      'bodyAr','موعد صيانة '||coalesce(v_car_name,r.car_id)||' في '||r.due_at::text,
      'bodyEn','Maintenance for '||coalesce(v_car_name,r.car_id)||' is due at '||r.due_at::text,
      'createdAt',p_now
    )) on conflict do nothing;
    update public.erp_vehicle_maintenance_schedules
    set last_reminded_at=p_now,
        status=case when due_at<=p_now then 'due' else status end
    where company_id=p_company_id and id=r.id;
    v_count:=v_count+1;
  end loop;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Detailed operational commercial notifications.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r88_commercial_document_notification()
returns trigger
language plpgsql security definer set search_path=public as $$
declare
  v_actor text:=''; v_partner text:=''; v_warehouse text:='';
  v_order_number text:=''; v_event_type text; v_title_ar text; v_title_en text;
  v_event_key text; v_currency text; v_amount numeric:=0;
begin
  if new.is_deleted then return new; end if;
  if new.document_type not in ('receipt','delivery','invoice') then return new; end if;
  if tg_op='UPDATE' and new.status is not distinct from old.status then return new; end if;
  if tg_op='UPDATE' and lower(coalesce(new.status,''))<>'approved' then return new; end if;

  select coalesce(full_name,'') into v_actor
  from public.profiles where id=coalesce(new.updated_by,new.created_by,auth.uid());
  select coalesce(w.data->>'name','') into v_warehouse
  from public.erp_warehouses w
  where w.company_id=new.company_id
    and w.id=coalesce(new.warehouse_id,new.payload->>'warehouseId',new.payload->>'warehouse_id')
    and not w.is_deleted limit 1;

  if new.module='purchases' then
    select o.order_number,coalesce(s.data->>'name',''),upper(o.currency)
      into v_order_number,v_partner,v_currency
    from public.erp_purchase_orders_cloud o
    left join public.erp_suppliers s
      on s.company_id=o.company_id and s.id=o.supplier_id and not s.is_deleted
    where o.company_id=new.company_id and o.id=new.parent_id;
  elsif new.module='sales' then
    select o.order_number,coalesce(c.data->>'name',''),upper(o.currency)
      into v_order_number,v_partner,v_currency
    from public.erp_sales_orders_cloud o
    left join public.erp_customers c
      on c.company_id=o.company_id and c.id=o.customer_id and not c.is_deleted
    where o.company_id=new.company_id and o.id=new.parent_id;
  else return new;
  end if;

  v_amount:=public.erp_try_numeric(
    coalesce(new.payload->>'totalAmount',new.payload->>'total'),0
  );
  v_event_type:=case
    when new.document_type='receipt' and lower(new.status)='approved' then 'purchase_receipt_approved'
    when new.document_type='receipt' then 'purchase_receipt_created'
    when new.document_type='delivery' and lower(new.status)='approved' then 'sales_delivery_approved'
    when new.document_type='delivery' then 'sales_delivery_created'
    when new.module='purchases' then 'purchase_invoice'
    else 'sales_invoice' end;
  v_title_ar:=case v_event_type
    when 'purchase_receipt_approved' then 'تم تصديق الاستلام المخزني'
    when 'purchase_receipt_created' then 'تم إنشاء استلام مخزني'
    when 'sales_delivery_approved' then 'تم تصديق التجهيز المخزني'
    when 'sales_delivery_created' then 'تم إنشاء تجهيز مخزني'
    when 'purchase_invoice' then 'فاتورة شراء'
    else 'فاتورة بيع' end;
  v_title_en:=replace(initcap(replace(v_event_type,'_',' ')),'  ',' ');
  v_event_key:=format(
    'r88:%s:%s:%s',v_event_type,new.id::text,lower(coalesce(new.status,'draft'))
  );

  insert into public.erp_enterprise_notifications(company_id,id,data)
  values(new.company_id,gen_random_uuid(),jsonb_build_object(
    'eventKey',v_event_key,'eventType',v_event_type,'event',v_event_type,
    'type',case when lower(new.status)='approved' then 'success' else 'info' end,
    'module',new.module,'documentReference',new.document_number,
    'orderReference',v_order_number,
    'actorUserId',coalesce(new.updated_by,new.created_by,auth.uid()),
    'actorUser',v_actor,'dateTime',coalesce(new.effective_at,new.updated_at,new.created_at),
    case when new.module='purchases' then 'supplierName' else 'customerName' end,v_partner,
    'warehouseName',v_warehouse,'amount',v_amount,'currency',v_currency,
    'referenceType',case when new.module='purchases' then 'purchase_order' else 'sales_order' end,
    'referenceId',new.parent_id::text,
    'deepLink',case when new.module='purchases' then '/purchases' else '/sales' end,
    'titleAr',v_title_ar,'titleEn',v_title_en,
    'bodyAr',coalesce(v_actor,'')||' • '||new.document_number||' • '||coalesce(v_partner,'')||
      case when v_warehouse='' then '' else ' • '||v_warehouse end,
    'bodyEn',coalesce(v_actor,'')||' • '||new.document_number||' • '||coalesce(v_partner,'')||
      case when v_warehouse='' then '' else ' • '||v_warehouse end,
    'createdAt',now()
  )) on conflict do nothing;
  return new;
end;
$$;

drop trigger if exists erp_r88_commercial_document_notification
  on public.erp_commercial_workflow_documents;
create trigger erp_r88_commercial_document_notification
after insert or update of status on public.erp_commercial_workflow_documents
for each row execute function public.erp_r88_commercial_document_notification();

create or replace function public.erp_r88_cash_payment_notification()
returns trigger
language plpgsql security definer set search_path=public as $$
declare
  v_type text;
  v_party_type text;
  v_reference_type text;
  v_event text;
  v_actor text:='';
  v_key text;
begin
  if new.is_deleted then return new; end if;
  v_type:=lower(coalesce(new.data->>'type',''));
  v_party_type:=lower(coalesce(new.data->>'partyType',new.data->>'party_type',''));
  v_reference_type:=lower(coalesce(new.data->>'referenceType',new.data->>'reference_type',''));

  if v_type in ('customer_receipt','receipt','cash_in','income')
     and (v_party_type='customer' or v_reference_type like 'sales%'
       or v_reference_type like 'maintenance%') then
    v_event:='payment_received';
  elsif v_type in ('supplier_payment','payment','cash_out')
     and (v_party_type='supplier' or v_reference_type like 'purchase%') then
    v_event:='supplier_payment';
  else
    -- Generic cash-in/out and expense entries are not commercial payment events.
    return new;
  end if;

  select coalesce(full_name,'') into v_actor from public.profiles where id=new.created_by;
  v_key:='r88:'||v_event||':'||new.id;
  insert into public.erp_enterprise_notifications(company_id,id,data)
  values(new.company_id,gen_random_uuid(),jsonb_build_object(
    'eventKey',v_key,'eventType',v_event,'event',v_event,'module','cashbox',
    'type','success','documentReference',coalesce(new.data->>'voucherNumber',new.id::text),
    'actorUserId',new.created_by,'actorUser',v_actor,
    'dateTime',coalesce(new.data->>'transactionDate',new.created_at::text),
    'amount',abs(public.erp_try_numeric(new.data->>'amount',0)),
    'currency',upper(coalesce(nullif(new.data->>'currency',''),'IQD')),
    'cashboxId',coalesce(new.data->>'cashAccountId',new.data->>'cash_account_id'),
    'cashboxName',coalesce(new.data->>'cashAccountName',''),
    'relatedDocument',coalesce(new.data->>'referenceDocumentNumber',new.data->>'referenceId',''),
    'referenceType',coalesce(new.data->>'referenceType','cash_transaction'),
    'referenceId',coalesce(new.data->>'referenceId',new.id::text),
    'deepLink','/accounting',
    'titleAr',case when v_event='payment_received' then 'تم استلام دفعة' else 'تم دفع مستحقات مجهز' end,
    'titleEn',case when v_event='payment_received' then 'Payment received' else 'Supplier payment' end,
    'bodyAr',coalesce(new.data->>'partyName','')||' • '||abs(public.erp_try_numeric(new.data->>'amount',0))::text||' '||upper(coalesce(new.data->>'currency','IQD')),
    'bodyEn',coalesce(new.data->>'partyName','')||' • '||abs(public.erp_try_numeric(new.data->>'amount',0))::text||' '||upper(coalesce(new.data->>'currency','IQD')),
    'createdAt',now()
  )) on conflict do nothing;
  return new;
end;
$$;

drop trigger if exists erp_r88_cash_payment_notification on public.erp_cash_transactions;
create trigger erp_r88_cash_payment_notification
after insert on public.erp_cash_transactions
for each row execute function public.erp_r88_cash_payment_notification();

-- Maintenance operational event notifications share the same persistent inbox.
create or replace function public.erp_r88_maintenance_order_notification()
returns trigger
language plpgsql security definer set search_path=public as $$
declare
  v_event text;
  v_reference text;
  v_actor text:='';
  v_car text;
  v_key text;
begin
  if new.is_deleted then return new; end if;
  if tg_op<>'UPDATE' then return new; end if;

  if new.workflow_stage is distinct from old.workflow_stage then
    v_event:=case new.workflow_stage
      when 'stock_issue_approved' then 'maintenance_material_issue'
      when 'invoice_approved' then 'maintenance_invoice'
      else null end;
  end if;
  if v_event is null and new.paid_amount>old.paid_amount then
    v_event:='maintenance_payment';
  end if;
  if v_event is null then return new; end if;

  select coalesce(full_name,'') into v_actor
  from public.profiles where id=coalesce(new.updated_by,new.created_by,auth.uid());
  v_car:=coalesce(nullif(new.car_name,''),new.car_id::text);
  v_reference:=case v_event
    when 'maintenance_material_issue' then coalesce(new.stock_issue_number,new.order_number)
    when 'maintenance_invoice' then coalesce(new.invoice_number,new.order_number)
    else new.order_number end;
  v_key:=format('r88:%s:%s:%s',v_event,new.id::text,new.updated_at::text);

  insert into public.erp_enterprise_notifications(company_id,id,data)
  values(new.company_id,gen_random_uuid(),jsonb_build_object(
    'eventKey',v_key,'eventType',v_event,'event',v_event,
    'type','success','module','maintenance',
    'documentReference',v_reference,'orderReference',new.order_number,
    'actorUserId',coalesce(new.updated_by,new.created_by,auth.uid()),
    'actorUser',v_actor,'dateTime',new.updated_at,
    'carId',new.car_id,'carName',v_car,
    'customerName',coalesce(new.customer_name,''),
    'amount',case when v_event='maintenance_payment'
      then greatest(new.paid_amount-old.paid_amount,0)
      else new.sale_price end,
    'currency',upper(new.currency_code),
    'referenceType','maintenance_order','referenceId',new.id::text,
    'deepLink','/maintenance',
    'titleAr',case v_event
      when 'maintenance_material_issue' then 'تم تصديق صرف مواد الصيانة'
      when 'maintenance_invoice' then 'تم تصديق فاتورة الصيانة'
      else 'تم تسجيل دفعة صيانة' end,
    'titleEn',case v_event
      when 'maintenance_material_issue' then 'Maintenance material issue approved'
      when 'maintenance_invoice' then 'Maintenance invoice posted'
      else 'Maintenance payment recorded' end,
    'bodyAr',coalesce(v_actor,'')||' • '||v_reference||' • '||v_car,
    'bodyEn',coalesce(v_actor,'')||' • '||v_reference||' • '||v_car,
    'createdAt',now()
  )) on conflict do nothing;
  return new;
end;
$$;

drop trigger if exists erp_r88_maintenance_order_notification
  on public.erp_maintenance_orders;
create trigger erp_r88_maintenance_order_notification
after update of workflow_stage,paid_amount on public.erp_maintenance_orders
for each row execute function public.erp_r88_maintenance_order_notification();

-- Report exports are recorded as user-targeted operational events. They are
-- intentionally written after a successful export request and do not pretend
-- that loading a report is itself a generated document.
create or replace function public.erp_r88_record_report_event(
  p_company_id uuid,
  p_report_key text,
  p_report_title text,
  p_output_format text default null,
  p_module text default null,
  p_from_date timestamptz default null,
  p_to_date timestamptz default null
) returns uuid
language plpgsql security definer set search_path=public as $$
declare
  v_id uuid:=gen_random_uuid();
  v_user_key text:=public.erp_r49_notification_user_key();
  v_actor text:='';
  v_format text:=upper(btrim(coalesce(p_output_format,'')));
  v_module text:=lower(btrim(coalesce(p_module,'')));
  v_title text:=coalesce(nullif(btrim(p_report_title),''),nullif(btrim(p_report_key),''),'Report');
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_cloud_user_has_permission(p_company_id,'reports.export') then
    raise exception 'permission_denied:reports.export' using errcode='42501';
  end if;
  if v_user_key is null then
    raise exception 'notification_user_identity_required' using errcode='42501';
  end if;

  select coalesce(nullif(btrim(full_name),''),v_user_key)
    into v_actor
  from public.profiles
  where id=auth.uid();
  v_actor:=coalesce(nullif(v_actor,''),v_user_key);

  insert into public.erp_enterprise_notifications(company_id,id,data)
  values(p_company_id,v_id,jsonb_build_object(
    'eventKey','report_event:'||v_id::text,
    'eventType','report_event','event','report_event','type','info',
    'module',coalesce(nullif(v_module,''),'reports'),
    'userId',v_user_key,'targetUserId',v_user_key,'targetUser',v_actor,
    'actorUserId',auth.uid(),'actorUser',v_actor,
    'dateTime',now(),'createdAt',now(),
    'referenceType','report','referenceId',coalesce(nullif(btrim(p_report_key),''),v_id::text),
    'documentReference',v_title,
    'outputFormat',coalesce(nullif(v_format,''),'VIEW'),
    'periodFrom',p_from_date,'periodTo',p_to_date,
    'deepLink','/settings/reports',
    'titleAr','تم إنشاء تقرير',
    'titleEn','Report generated',
    'bodyAr',v_actor||' • '||v_title||' • '||coalesce(nullif(v_format,''),'REPORT'),
    'bodyEn',v_actor||' • '||v_title||' • '||coalesce(nullif(v_format,''),'REPORT')
  ));
  return v_id;
end;
$$;

revoke all on function public.erp_r88_record_report_event(
  uuid,text,text,text,text,timestamptz,timestamptz
) from public,anon;
grant execute on function public.erp_r88_record_report_event(
  uuid,text,text,text,text,timestamptz,timestamptz
) to authenticated,service_role;

-- ---------------------------------------------------------------------------
-- 9. Permission catalog registration.
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('public.erp_permissions') is not null then
    insert into public.erp_permissions(code,module,action,description) values
      ('sales.actions.restrict','sales','restrict','Require granular Sales action permissions'),
      ('sales.order.approve','sales','approve','Approve Sales Order'),
      ('sales.delivery.create','sales','create','Create Sales Delivery'),
      ('sales.delivery.approve','sales','approve','Approve Sales Delivery'),
      ('sales.invoice.create','sales','create','Create Sales Invoice'),
      ('sales.invoice.approve','sales','approve','Approve Sales Invoice'),
      ('sales.payment','sales','payment','Receive Sales Payment'),
      ('sales.reverse','sales','reverse','Reverse Sales workflow document'),
      ('purchases.actions.restrict','purchases','restrict','Require granular Purchase action permissions'),
      ('purchases.order.approve','purchases','approve','Approve Purchase Order'),
      ('purchases.receipt.create','purchases','create','Create Purchase Receipt'),
      ('purchases.receipt.approve','purchases','approve','Approve Purchase Receipt'),
      ('purchases.invoice.create','purchases','create','Create Purchase Invoice'),
      ('purchases.invoice.approve','purchases','approve','Approve Purchase Invoice'),
      ('purchases.payment','purchases','payment','Pay Supplier'),
      ('purchases.reverse','purchases','reverse','Reverse Purchase workflow document'),
      ('maintenance.actions.restrict','maintenance','restrict','Require granular Maintenance action permissions'),
      ('maintenance.order.approve','maintenance','approve','Approve Maintenance Order'),
      ('maintenance.material_issue.create','maintenance','create','Create Maintenance Material Issue'),
      ('maintenance.material_issue.approve','maintenance','approve','Approve Maintenance Material Issue'),
      ('maintenance.invoice.create','maintenance','create','Create Maintenance Invoice'),
      ('maintenance.invoice.approve','maintenance','approve','Approve Maintenance Invoice'),
      ('maintenance.payment','maintenance','payment','Record Maintenance Payment'),
      ('maintenance.reverse','maintenance','reverse','Reverse Maintenance document'),
      ('maintenance.schedule.create','maintenance','create','Create Vehicle Maintenance Schedule'),
      ('maintenance.schedule.update','maintenance','update','Update Vehicle Maintenance Schedule'),
      ('maintenance.schedule.delete','maintenance','delete','Delete Vehicle Maintenance Schedule'),
      ('maintenance.schedule.assign_other','maintenance','assign','Assign Maintenance Schedule to another user'),
      ('maintenance.schedule.convert','maintenance','create','Convert Maintenance Schedule to Order'),
      ('maintenance.history_detail.edit','maintenance','update','Edit custom Maintenance History details'),
      ('cashbox.actions.restrict','cashbox','restrict','Require granular Cashbox action permissions'),
      ('cashbox.transaction.view','cashbox','view','View Cashbox transactions'),
      ('cashbox.transaction.edit','cashbox','update','Edit Cashbox transaction when accounting integrity permits'),
      ('cashbox.transaction.delete','cashbox','delete','Delete/reverse Cashbox transaction when accounting integrity permits')
    on conflict(code) do nothing;
  end if;
end $$;

-- Field permission catalog entries are regular permission codes as well.
do $$
begin
  if to_regclass('public.erp_permissions') is not null then
    insert into public.erp_permissions(code,module,action,description) values
      ('purchases.fields.createdBy.view','purchases','view','View Purchase creator'),
      ('sales.fields.createdBy.view','sales','view','View Sales creator'),
      ('maintenance.fields.createdBy.view','maintenance','view','View Maintenance creator'),
      ('cars.fields.maintenanceHistory.view','cars','view','View Vehicle Maintenance History'),
      ('cars.fields.purchasePrice.view','cars','view','View Vehicle Purchase Cost'),
      ('cars.fields.maintenanceCost.view','cars','view','View Vehicle Maintenance Cost'),
      ('cars.fields.salePrice.view','cars','view','View Vehicle Sale Price'),
      ('cars.fields.margin.view','cars','view','View Vehicle Margin / Profit'),
      ('cars.fields.inventoryAssetAccountId.view','cars','view','View Vehicle Inventory Account'),
      ('cars.fields.salesCostExpenseAccountId.view','cars','view','View Vehicle Cost of Sales Account'),
      ('cars.fields.salesRevenueIqdAccountId.view','cars','view','View Vehicle IQD Revenue Account'),
      ('cars.fields.salesRevenueUsdAccountId.view','cars','view','View Vehicle USD Revenue Account'),
      ('maintenance.fields.materialCost.view','maintenance','view','View actual Maintenance material cost'),
      ('maintenance.fields.margin.view','maintenance','view','View Maintenance margin'),
      ('maintenance.fields.maintenanceSchedule.view','maintenance','view','View Maintenance schedules'),
      ('maintenance.fields.maintenanceSchedule.edit','maintenance','update','Edit Maintenance schedules'),
      ('maintenance.fields.maintenanceHistoryDetails.view','maintenance','view','View custom Maintenance history details'),
      ('maintenance.fields.maintenanceHistoryDetails.edit','maintenance','update','Edit custom Maintenance history details'),
      ('cashbox.fields.performedBy.view','cashbox','view','View Cashbox transaction user'),
      ('cashbox.fields.transactionStatus.view','cashbox','view','View Cashbox transaction status')
    on conflict(code) do nothing;
  end if;
end $$;

-- Harden SECURITY DEFINER helpers and public tables.
revoke all on function public.erp_r88_list_vehicle_maintenance_schedules(uuid,text) from public,anon;
revoke all on function public.erp_r88_save_vehicle_maintenance_schedule(uuid,jsonb) from public,anon;
revoke all on function public.erp_r88_delete_vehicle_maintenance_schedule(uuid,uuid) from public,anon;
revoke all on function public.erp_r88_link_maintenance_schedule_order(uuid,uuid,uuid) from public,anon;
revoke all on function public.erp_r88_list_maintenance_history_details(uuid,text,uuid) from public,anon;
revoke all on function public.erp_r88_save_maintenance_history_detail(uuid,jsonb) from public,anon;
revoke all on function public.erp_r88_delete_maintenance_history_detail(uuid,uuid) from public,anon;
revoke all on function public.erp_r88_materialize_maintenance_schedule_reminders(uuid,timestamptz) from public,anon;
revoke all on function public.erp_r88_commercial_document_notification() from public,anon,authenticated;
revoke all on function public.erp_r88_cash_payment_notification() from public,anon,authenticated;
revoke all on function public.erp_r88_maintenance_order_notification() from public,anon,authenticated;

grant execute on function public.erp_r88_list_vehicle_maintenance_schedules(uuid,text) to authenticated,service_role;
grant execute on function public.erp_r88_save_vehicle_maintenance_schedule(uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_r88_delete_vehicle_maintenance_schedule(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r88_link_maintenance_schedule_order(uuid,uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r88_list_maintenance_history_details(uuid,text,uuid) to authenticated,service_role;
grant execute on function public.erp_r88_save_maintenance_history_detail(uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_r88_delete_maintenance_history_detail(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r88_materialize_maintenance_schedule_reminders(uuid,timestamptz) to authenticated,service_role;

grant select,insert,update on public.erp_vehicle_maintenance_schedules to authenticated;
grant select,insert,update on public.erp_maintenance_history_details to authenticated;

notify pgrst,'reload schema';
commit;
