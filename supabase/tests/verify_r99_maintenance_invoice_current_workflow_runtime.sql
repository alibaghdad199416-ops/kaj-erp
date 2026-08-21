\set ON_ERROR_STOP on
\pset pager off

-- Current Maintenance invoice correctness contract. This gate deliberately
-- follows the installed wrapper chain instead of historical migration names:
-- R99 scope guard -> R90 issue approval -> R88/R37 business engine -> R87
-- invoice accounting ownership.
begin;

do $$
declare
  v_current_r37 text;
  v_pre_r99 text;
  v_pre_r90 text;
  v_pre_r88 text;
  v_r90_approve text;
  v_r57_issue text;
  v_engine text;
  v_invoice text;
  v_sig text;
begin
  foreach v_sig in array array[
    'public.erp_r37_advance_maintenance_workflow(uuid,uuid)',
    'public.erp_r37_advance_maintenance_workflow_pre_r99(uuid,uuid)',
    'public.erp_r37_advance_maintenance_workflow_pre_r90(uuid,uuid)',
    'public.erp_r37_advance_maintenance_workflow_pre_r88(uuid,uuid)',
    'public.erp_r90_approve_maintenance_issue_draft(uuid,uuid)',
    'public.erp_r57_execute_maintenance_material_issue(uuid,uuid,uuid,uuid,text,numeric,timestamptz)',
    'public.erp_r57_execute_maintenance_material_issue_pre_r88(uuid,uuid,uuid,uuid,text,numeric,timestamptz)',
    'public.erp_advance_cloud_maintenance_workflow(uuid,uuid)',
    'public.erp_v736_post_maintenance_invoice(uuid,uuid)'
  ] loop
    if to_regprocedure(v_sig) is null then
      raise exception 'maintenance_current_chain_missing:%',v_sig;
    end if;
  end loop;

  select pg_get_functiondef(
    'public.erp_r37_advance_maintenance_workflow(uuid,uuid)'::regprocedure
  ) into v_current_r37;
  select pg_get_functiondef(
    'public.erp_r37_advance_maintenance_workflow_pre_r99(uuid,uuid)'::regprocedure
  ) into v_pre_r99;
  select pg_get_functiondef(
    'public.erp_r37_advance_maintenance_workflow_pre_r90(uuid,uuid)'::regprocedure
  ) into v_pre_r90;
  select pg_get_functiondef(
    'public.erp_r37_advance_maintenance_workflow_pre_r88(uuid,uuid)'::regprocedure
  ) into v_pre_r88;
  select pg_get_functiondef(
    'public.erp_r90_approve_maintenance_issue_draft(uuid,uuid)'::regprocedure
  ) into v_r90_approve;
  select pg_get_functiondef(
    'public.erp_r57_execute_maintenance_material_issue_pre_r88(uuid,uuid,uuid,uuid,text,numeric,timestamptz)'::regprocedure
  ) into v_r57_issue;
  select pg_get_functiondef(
    'public.erp_advance_cloud_maintenance_workflow(uuid,uuid)'::regprocedure
  ) into v_engine;
  select pg_get_functiondef(
    'public.erp_v736_post_maintenance_invoice(uuid,uuid)'::regprocedure
  ) into v_invoice;

  -- Browser entry point must be the R99 scoped wrapper, not a legacy engine.
  if v_current_r37 not like '%erp_r99_require_maintenance_action%'
     or v_current_r37 not like '%erp_r37_advance_maintenance_workflow_pre_r99%' then
    raise exception 'maintenance_r99_scope_wrapper_not_active';
  end if;

  -- The preserved R90 layer owns stock_issue_draft approval, and all other
  -- stages continue through R88/R37. This is the exact draft != approval
  -- boundary required by Phase 11.
  if v_pre_r99 not like '%erp_r90_approve_maintenance_issue_draft%'
     or v_pre_r99 not like '%erp_r37_advance_maintenance_workflow_pre_r90%' then
    raise exception 'maintenance_r90_issue_boundary_not_active';
  end if;
  if v_pre_r90 not like '%erp_r88_require_restricted_action%'
     or v_pre_r90 not like '%erp_r37_advance_maintenance_workflow_pre_r88%' then
    raise exception 'maintenance_r88_action_guard_not_active';
  end if;
  if v_pre_r88 not like '%erp_advance_cloud_maintenance_workflow%' then
    raise exception 'maintenance_r37_business_engine_not_reached';
  end if;

  -- R90 approval, not draft save, is what calls the mature material-issue
  -- executor. Partial approvals remain in stock_issue_draft and obtain a fresh
  -- draft; only completed requested stock quantities can advance onward.
  if v_r90_approve not like '%erp_r57_execute_maintenance_material_issue%'
     or v_r90_approve not like '%erp_r90_ensure_maintenance_issue_draft%'
     or v_r90_approve not like '%stock_issue_draft%'
     or v_r90_approve not like '%stock_issue_approved%' then
    raise exception 'maintenance_r90_approval_contract_incomplete';
  end if;

  -- R87 moved inventory/COGS ownership to the executed material-issue event.
  -- The lower executor must retain FIFO + definition-bound account posting.
  if v_r57_issue not like '%erp_inventory_fifo_consumptions%'
     or v_r57_issue not like '%erp_maintenance_bound_accounts%'
     or v_r57_issue not like '%maintenance_material_issue_cost%'
     or v_r57_issue not like '%journal_entry_id%'
     or v_r57_issue not like '%maintenance_part_id%' then
    raise exception 'maintenance_material_issue_cost_owner_not_active';
  end if;

  -- After stock completion, the mature engine creates the invoice draft and
  -- approval delegates to the current invoice-owned revenue posting function.
  if v_engine not like '%stock_issue_approved%'
     or v_engine not like '%invoice_draft%'
     or v_engine not like '%erp_v736_post_maintenance_invoice%'
     or v_engine not like '%invoice_approved%' then
    raise exception 'maintenance_invoice_stage_engine_incomplete';
  end if;

  -- Invoice owns receivable/revenue only. Material issue owns inventory cost;
  -- the invoice may report FIFO traceability but must never post a second COGS
  -- journal for the same issue.
  if v_invoice not like '%Maintenance invoice receivable%'
     or v_invoice not like '%maintenance_invoice_revenue%'
     or v_invoice not like '%erp_maintenance_bound_accounts%'
     or v_invoice not like '%invoice_item_bindings%'
     or v_invoice not like '%material_issue_event%'
     or v_invoice not like '%boundLineBilling%'
     or v_invoice not like '%laborBilling%'
     or v_invoice like '%maintenance_invoice_cost%' then
    raise exception 'maintenance_invoice_accounting_ownership_incorrect';
  end if;

  -- Only the current guarded R37 entry is browser-executable. Lower issue and
  -- preserved wrapper engines are internal, closing bypasses around R90/R99.
  if not has_function_privilege(
       'authenticated','public.erp_r37_advance_maintenance_workflow(uuid,uuid)','execute'
     )
     or has_function_privilege(
       'authenticated','public.erp_r37_advance_maintenance_workflow_pre_r99(uuid,uuid)','execute'
     )
     or has_function_privilege(
       'authenticated','public.erp_r37_advance_maintenance_workflow_pre_r90(uuid,uuid)','execute'
     )
     or has_function_privilege(
       'authenticated','public.erp_r37_advance_maintenance_workflow_pre_r88(uuid,uuid)','execute'
     )
     or has_function_privilege(
       'authenticated','public.erp_r90_approve_maintenance_issue_draft(uuid,uuid)','execute'
     )
     or has_function_privilege(
       'authenticated','public.erp_r57_execute_maintenance_material_issue(uuid,uuid,uuid,uuid,text,numeric,timestamptz)','execute'
     )
     or has_function_privilege(
       'authenticated','public.erp_r57_execute_maintenance_material_issue_pre_r88(uuid,uuid,uuid,uuid,text,numeric,timestamptz)','execute'
     ) then
    raise exception 'maintenance_current_chain_acl_bypass_detected';
  end if;
end $$;

rollback;
select 'R99 Maintenance invoice current-workflow runtime PASS' as result;
