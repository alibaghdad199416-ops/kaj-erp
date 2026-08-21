-- Quality Line ERP / KAJ ERP R99.1
-- Close remaining maintenance SECURITY DEFINER mutation bypasses.
-- Authorization and record scope must be proven before FIFO/stock/workflow side effects.
begin;

-- R90 is the supported material-issue approval boundary. The lower R57 execute
-- engine remains callable by SECURITY DEFINER owners/service_role only so an
-- authenticated client cannot bypass the draft/approval contract.
revoke all on function public.erp_r57_execute_maintenance_material_issue(
  uuid,uuid,uuid,uuid,text,numeric,timestamptz
) from public,anon,authenticated;
grant execute on function public.erp_r57_execute_maintenance_material_issue(
  uuid,uuid,uuid,uuid,text,numeric,timestamptz
) to service_role;

-- Some historical installations may still carry a legacy approve overload even
-- though the current migration chain no longer defines one. Fail closed for any
-- such overload instead of leaving a browser-executable compatibility endpoint.
do $$
declare
  v_function regprocedure;
begin
  for v_function in
    select p.oid::regprocedure
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname='erp_r57_approve_maintenance_material_issue'
  loop
    execute format(
      'revoke all on function %s from public,anon,authenticated',
      v_function
    );
    execute format(
      'grant execute on function %s to service_role',
      v_function
    );
  end loop;
end;
$$;

-- Preserve the proven event reversal body, but remove direct browser access.
alter function public.erp_r57_reverse_maintenance_material_issue(
  uuid,uuid,text
) rename to erp_r57_reverse_maintenance_material_issue_pre_r99_1;

revoke all on function public.erp_r57_reverse_maintenance_material_issue_pre_r99_1(
  uuid,uuid,text
) from public,anon,authenticated;
grant execute on function public.erp_r57_reverse_maintenance_material_issue_pre_r99_1(
  uuid,uuid,text
) to service_role;

create or replace function public.erp_r57_reverse_maintenance_material_issue(
  p_company_id uuid,
  p_issue_id uuid,
  p_reason text default null
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_order_id uuid;
begin
  perform public.erp_active_company_context(p_company_id);

  -- Read-only ownership lookup is allowed before authorization; no lock or
  -- mutation is taken until the owning order passes the R98/R95 guard.
  select i.maintenance_order_id
    into v_order_id
  from public.erp_maintenance_material_issues i
  where i.company_id=p_company_id and i.id=p_issue_id;

  if v_order_id is null then
    raise exception 'maintenance_issue_not_found' using errcode='P0002';
  end if;

  perform public.erp_r99_require_maintenance_action(
    p_company_id,
    v_order_id,
    'material_issue.reverse',
    array['maintenance.approve','maintenance.update']
  );

  perform public.erp_r57_reverse_maintenance_material_issue_pre_r99_1(
    p_company_id,p_issue_id,p_reason
  );
end;
$$;

revoke all on function public.erp_r57_reverse_maintenance_material_issue(
  uuid,uuid,text
) from public,anon;
grant execute on function public.erp_r57_reverse_maintenance_material_issue(
  uuid,uuid,text
) to authenticated,service_role;

-- V7.3 exposed component actions directly. Keep its mature delete/reversal
-- behavior internal, but route approvals through the current R37/R90 workflow
-- and authorize component deletions before the legacy body takes its first lock.
alter function public.erp_manage_maintenance_order_component(
  uuid,uuid,text,text,text
) rename to erp_manage_maintenance_order_component_pre_r99_1;

revoke all on function public.erp_manage_maintenance_order_component_pre_r99_1(
  uuid,uuid,text,text,text
) from public,anon,authenticated;
grant execute on function public.erp_manage_maintenance_order_component_pre_r99_1(
  uuid,uuid,text,text,text
) to service_role;

create or replace function public.erp_manage_maintenance_order_component(
  p_company_id uuid,
  p_order_id uuid,
  p_component_type text,
  p_action text,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_component text:=lower(btrim(coalesce(p_component_type,'')));
  v_operation text:=lower(btrim(coalesce(p_action,'')));
  v_granular_action text;
  v_result jsonb;
begin
  perform public.erp_active_company_context(p_company_id);
  perform public.erp_r98_require_maintenance_order_visible(
    p_company_id,p_order_id
  );

  if v_operation='approve' then
    -- The current workflow wrapper derives the granular permission from the
    -- authoritative order stage and delegates to the R90-aware engine.
    v_result:=public.erp_r37_advance_maintenance_workflow(
      p_company_id,p_order_id
    );
    return jsonb_build_object(
      'ok',true,
      'action','approve',
      'componentType',v_component,
      'linksUpdated',true,
      'workflow',coalesce(v_result,'{}'::jsonb)
    );
  end if;

  if v_operation<>'delete' then
    raise exception 'invalid_component_action' using errcode='22023';
  end if;

  v_granular_action:=case v_component
    when 'order' then 'order.delete'
    when 'order_approval' then 'order.reopen'
    when 'stock' then 'material_issue.reverse'
    when 'invoice' then 'invoice.delete'
    when 'payment' then null
    else null
  end;

  if v_component='payment' then
    raise exception 'delete_payment_from_cashbox_first' using errcode='P0001';
  end if;
  if v_granular_action is null then
    raise exception 'invalid_component_type' using errcode='22023';
  end if;

  perform public.erp_r99_require_maintenance_action(
    p_company_id,
    p_order_id,
    v_granular_action,
    array['maintenance.update','maintenance.delete']
  );

  return public.erp_manage_maintenance_order_component_pre_r99_1(
    p_company_id,p_order_id,p_component_type,p_action,p_reason
  );
end;
$$;

revoke all on function public.erp_manage_maintenance_order_component(
  uuid,uuid,text,text,text
) from public,anon;
grant execute on function public.erp_manage_maintenance_order_component(
  uuid,uuid,text,text,text
) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
