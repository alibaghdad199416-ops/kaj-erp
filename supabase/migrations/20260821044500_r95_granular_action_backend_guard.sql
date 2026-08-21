begin;

-- R95 granular workflow action backend guard.
-- The Flutter permission contract treats `<resource>.actions.restrict` as a
-- compatibility switch: legacy broad permissions apply while the switch is
-- absent; once enabled, the exact granular action permission is authoritative.
-- Keep that same contract at SECURITY DEFINER entry points so button visibility
-- can never be used as the security boundary.

create or replace function public.erp_r95_user_can_perform_action(
  p_company_id uuid,
  p_restriction_permission text,
  p_granular_permission text,
  p_legacy_permissions text[]
) returns boolean
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_restriction text:=nullif(btrim(coalesce(p_restriction_permission,'')),'');
  v_granular text:=nullif(btrim(coalesce(p_granular_permission,'')),'');
  v_legacy text;
begin
  perform public.erp_active_company_context(p_company_id);

  if public.is_company_admin(p_company_id) then
    return true;
  end if;

  if v_restriction is null or v_granular is null then
    return false;
  end if;

  if public.erp_cloud_user_has_permission(p_company_id,v_restriction) then
    return public.erp_cloud_user_has_permission(p_company_id,v_granular);
  end if;

  foreach v_legacy in array coalesce(p_legacy_permissions,array[]::text[]) loop
    v_legacy:=nullif(btrim(coalesce(v_legacy,'')),'');
    if v_legacy is not null
       and public.erp_cloud_user_has_permission(p_company_id,v_legacy) then
      return true;
    end if;
  end loop;
  return false;
end;
$$;

revoke all on function public.erp_r95_user_can_perform_action(uuid,text,text,text[])
  from public,anon;
grant execute on function public.erp_r95_user_can_perform_action(uuid,text,text,text[])
  to authenticated,service_role;

-- Order approval: unrestricted companies retain the historical broad approval
-- permission. Restricted companies require the exact per-document permission.
create or replace function public.erp_r49_approve_sales_order(
  p_company_id uuid,p_order_id uuid
) returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_r95_user_can_perform_action(
    p_company_id,
    'sales.actions.restrict',
    'sales.order.approve',
    array['sales.approve']
  ) then
    raise exception 'permission_denied:sales.order.approve' using errcode='42501';
  end if;
  perform public.erp_approve_cloud_sales_order(p_company_id,p_order_id);
end;
$$;

create or replace function public.erp_r49_approve_purchase_order(
  p_company_id uuid,p_order_id uuid
) returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_r95_user_can_perform_action(
    p_company_id,
    'purchases.actions.restrict',
    'purchases.order.approve',
    array['purchases.approve']
  ) then
    raise exception 'permission_denied:purchases.order.approve' using errcode='42501';
  end if;
  perform public.erp_approve_cloud_purchase_order(p_company_id,p_order_id);
end;
$$;

-- Logistics draft creation remains a distinct operational boundary from order
-- approval. Preserve R49 warehouse validation and canonical business functions,
-- but authorize the operation with the exact granular action in restricted mode.
create or replace function public.erp_r49_create_purchase_receipt(
  p_company_id uuid,p_order_id uuid,p_warehouse_id text default null,
  p_notes text default null
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_r95_user_can_perform_action(
    p_company_id,
    'purchases.actions.restrict',
    'purchases.receipt.create',
    array['purchases.update']
  ) then
    raise exception 'permission_denied:purchases.receipt.create' using errcode='42501';
  end if;
  perform public.erp_r49_require_active_warehouse(p_company_id,p_warehouse_id);
  return public.erp_create_cloud_purchase_receipt(
    p_company_id,p_order_id,p_warehouse_id,p_notes
  );
end;
$$;

create or replace function public.erp_r49_create_purchase_receipt_multi(
  p_company_id uuid,p_order_id uuid,p_allocations jsonb,p_notes text default null
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_r95_user_can_perform_action(
    p_company_id,
    'purchases.actions.restrict',
    'purchases.receipt.create',
    array['purchases.update']
  ) then
    raise exception 'permission_denied:purchases.receipt.create' using errcode='42501';
  end if;
  perform public.erp_r49_require_allocation_warehouses(p_company_id,p_allocations);
  return public.erp_create_cloud_purchase_receipt_multi(
    p_company_id,p_order_id,p_allocations,p_notes
  );
end;
$$;

create or replace function public.erp_r49_create_sales_delivery(
  p_company_id uuid,p_order_id uuid,p_warehouse_id text default null,
  p_notes text default null
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_r95_user_can_perform_action(
    p_company_id,
    'sales.actions.restrict',
    'sales.delivery.create',
    array['sales.update']
  ) then
    raise exception 'permission_denied:sales.delivery.create' using errcode='42501';
  end if;
  perform public.erp_r49_require_active_warehouse(p_company_id,p_warehouse_id);
  return public.erp_create_cloud_sales_delivery(
    p_company_id,p_order_id,p_warehouse_id,p_notes
  );
end;
$$;

create or replace function public.erp_r49_create_sales_delivery_multi(
  p_company_id uuid,p_order_id uuid,p_allocations jsonb,p_notes text default null
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_r95_user_can_perform_action(
    p_company_id,
    'sales.actions.restrict',
    'sales.delivery.create',
    array['sales.update']
  ) then
    raise exception 'permission_denied:sales.delivery.create' using errcode='42501';
  end if;
  perform public.erp_r49_require_allocation_warehouses(p_company_id,p_allocations);
  return public.erp_create_cloud_sales_delivery_multi(
    p_company_id,p_order_id,p_allocations,p_notes
  );
end;
$$;

-- Re-assert the browser-facing surface after replacement.
revoke all on function public.erp_r49_approve_sales_order(uuid,uuid) from public,anon;
revoke all on function public.erp_r49_approve_purchase_order(uuid,uuid) from public,anon;
revoke all on function public.erp_r49_create_purchase_receipt(uuid,uuid,text,text) from public,anon;
revoke all on function public.erp_r49_create_purchase_receipt_multi(uuid,uuid,jsonb,text) from public,anon;
revoke all on function public.erp_r49_create_sales_delivery(uuid,uuid,text,text) from public,anon;
revoke all on function public.erp_r49_create_sales_delivery_multi(uuid,uuid,jsonb,text) from public,anon;

grant execute on function public.erp_r49_approve_sales_order(uuid,uuid)
  to authenticated,service_role;
grant execute on function public.erp_r49_approve_purchase_order(uuid,uuid)
  to authenticated,service_role;
grant execute on function public.erp_r49_create_purchase_receipt(uuid,uuid,text,text)
  to authenticated,service_role;
grant execute on function public.erp_r49_create_purchase_receipt_multi(uuid,uuid,jsonb,text)
  to authenticated,service_role;
grant execute on function public.erp_r49_create_sales_delivery(uuid,uuid,text,text)
  to authenticated,service_role;
grant execute on function public.erp_r49_create_sales_delivery_multi(uuid,uuid,jsonb,text)
  to authenticated,service_role;

notify pgrst,'reload schema';
commit;
