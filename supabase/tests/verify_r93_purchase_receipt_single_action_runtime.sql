\set ON_ERROR_STOP on
begin;

do $$
declare
  v_def text;
begin
  if to_regprocedure(
    'public.erp_r49_create_purchase_receipt_multi(uuid,uuid,jsonb,text)'
  ) is null then
    raise exception 'r93_purchase_single_action_endpoint_missing';
  end if;

  select pg_get_functiondef(
    'public.erp_r49_create_purchase_receipt_multi(uuid,uuid,jsonb,text)'::regprocedure
  ) into v_def;

  if v_def not like '%receipt.create%'
     or v_def not like '%receipt.approve%'
     or v_def not like '%erp_r49_create_purchase_receipt_multi_pre_r88%'
     or v_def not like '%erp_phase2_approve_purchase_receipt_pre_r88%'
     or v_def not like '%purchase_receipt_allocations_required%' then
    raise exception 'r93_purchase_single_action_contract_incomplete';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.erp_r49_create_purchase_receipt_multi(uuid,uuid,jsonb,text)',
    'execute'
  ) then
    raise exception 'r93_purchase_single_action_not_executable';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.erp_r49_create_purchase_receipt_multi_pre_r88(uuid,uuid,jsonb,text)',
    'execute'
  ) then
    raise exception 'r93_purchase_create_pre_r88_bypass_exposed';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.erp_phase2_approve_purchase_receipt_pre_r88(uuid,uuid)',
    'execute'
  ) then
    raise exception 'r93_purchase_approve_pre_r88_bypass_exposed';
  end if;
end $$;

rollback;
select 'R93 purchase receipt single-action LOCAL PostgreSQL runtime PASS' as result;
