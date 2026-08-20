\set ON_ERROR_STOP on
begin;

do $$
declare
  v_def text;
begin
  if to_regprocedure('public.erp_r9_get_cloud_maintenance_order_lines(uuid,uuid)') is null then
    raise exception 'r91_maintenance_line_reader_missing';
  end if;
  select pg_get_functiondef(
    'public.erp_r9_get_cloud_maintenance_order_lines(uuid,uuid)'::regprocedure
  ) into v_def;
  if v_def not like '%erp_inventory%'
     or v_def not like '%descriptionAr%'
     or v_def not like '%descriptionEn%'
     or v_def not like '%erp_cloud_user_can_view_field%'
     or v_def not like '%maintenance%items%' then
    raise exception 'r91_maintenance_description_boundary_incomplete';
  end if;

  select pg_get_functiondef(
    'public.erp_r88_maintenance_order_notification()'::regprocedure
  ) into v_def;
  if v_def like '%stock_issue_approved%maintenance_material_issue%' then
    raise exception 'r91_duplicate_material_issue_notification_branch_present';
  end if;
  if v_def not like '%invoice_approved%maintenance_invoice%'
     or v_def not like '%paid_amount%old.paid_amount%' then
    raise exception 'r91_invoice_or_payment_notification_regressed';
  end if;

  select pg_get_functiondef(
    'public.erp_r90_approve_maintenance_issue_draft(uuid,uuid)'::regprocedure
  ) into v_def;
  if v_def not like '%erp_r57_execute_maintenance_material_issue%'
     or v_def not like '%r90:maintenance_material_issue:%'
     or v_def not like '%status=''approved''%' then
    raise exception 'r91_r90_approval_owned_issue_contract_missing';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.erp_r57_execute_maintenance_material_issue(uuid,uuid,uuid,uuid,text,numeric,timestamptz)',
    'execute'
  ) then
    raise exception 'r91_direct_material_issue_execution_exposed';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.erp_r37_advance_maintenance_workflow(uuid,uuid)',
    'execute'
  ) then
    raise exception 'r91_approved_workflow_boundary_not_exposed';
  end if;
end $$;

rollback;
select 'R91 Phase 11 LOCAL PostgreSQL runtime PASS' as result;
