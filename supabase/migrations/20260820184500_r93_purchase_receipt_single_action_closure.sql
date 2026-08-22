-- Quality Line ERP / KAJ ERP R93
-- Purchase receiving is one user action: create the warehouse receipt and
-- approve it atomically. Inventory still changes only inside the proven
-- approved-receipt implementation; any approval failure rolls the draft back.
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

  -- The single UI action owns both capabilities. In legacy action mode these
  -- helpers preserve the established broad purchase permission semantics; once
  -- granular actions are enabled both exact permissions are mandatory.
  perform public.erp_r88_require_restricted_action(
    p_company_id,'purchases','receipt.create'
  );
  perform public.erp_r88_require_restricted_action(
    p_company_id,'purchases','receipt.approve'
  );

  if p_allocations is null
     or jsonb_typeof(p_allocations)<>'array'
     or jsonb_array_length(p_allocations)=0 then
    raise exception 'purchase_receipt_allocations_required' using errcode='22023';
  end if;

  v_receipt_id:=public.erp_r49_create_purchase_receipt_multi_pre_r88(
    p_company_id,p_order_id,p_allocations,p_notes
  );

  -- The mature approval implementation owns quantity mutation, inventory
  -- movement, valuation timing and audit links. Both calls execute in this RPC
  -- transaction, so no orphan receipt draft survives an approval error.
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
