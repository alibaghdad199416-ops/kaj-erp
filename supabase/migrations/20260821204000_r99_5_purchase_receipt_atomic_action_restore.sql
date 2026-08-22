-- Quality Line ERP / KAJ ERP R99.5
-- R95 added granular receipt permissions but replaced R93's atomic create and
-- approve boundary with draft creation only. Require both exact actions, then
-- run the proven R88-preserved create and approve implementations in one RPC.
begin;

create or replace function public.erp_r49_create_purchase_receipt_multi(
  p_company_id uuid,
  p_order_id uuid,
  p_allocations jsonb,
  p_notes text default null
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_receipt_id uuid;
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
  if not public.erp_r95_user_can_perform_action(
    p_company_id,
    'purchases.actions.restrict',
    'purchases.receipt.approve',
    array['purchases.approve','purchases.update','purchases.create']
  ) then
    raise exception 'permission_denied:purchases.receipt.approve' using errcode='42501';
  end if;

  if p_allocations is null
     or jsonb_typeof(p_allocations)<>'array'
     or jsonb_array_length(p_allocations)=0 then
    raise exception 'purchase_receipt_allocations_required' using errcode='22023';
  end if;
  perform public.erp_r49_require_allocation_warehouses(
    p_company_id,p_allocations
  );

  v_receipt_id:=public.erp_r49_create_purchase_receipt_multi_pre_r88(
    p_company_id,p_order_id,p_allocations,p_notes
  );
  perform public.erp_phase2_approve_purchase_receipt_pre_r88(
    p_company_id,v_receipt_id
  );

  return v_receipt_id;
end;
$$;

revoke all on function public.erp_r49_create_purchase_receipt_multi(
  uuid,uuid,jsonb,text
) from public,anon;
grant execute on function public.erp_r49_create_purchase_receipt_multi(
  uuid,uuid,jsonb,text
) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
