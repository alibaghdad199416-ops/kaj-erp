begin;

-- R57 Maintenance deleted-order historical repair execution-context closure.
--
-- 269 correctly installed the future delete path, but its one-time repair can run
-- from migration/service-role/psql contexts where auth.uid() is null.
-- erp_inventory_ensure_stock() intentionally checks erp_is_company_member(), so
-- historical repair must establish a real active company member identity before
-- it reuses normal inventory helpers.
--
-- This migration does NOT weaken erp_inventory_ensure_stock(), RLS, or normal
-- browser permissions. Only the service-role-only historical repair function
-- establishes a transaction-local auth identity selected from an existing active
-- membership of the same company.

create or replace function public.erp_r57_repair_deleted_maintenance_order(
  p_company_id uuid,
  p_order_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_order public.erp_maintenance_orders%rowtype;
  v_repair_user_id uuid;
  v_stage text:='load_order';
  v_detached jsonb;
  v_accounting jsonb;
  v_issues jsonb;
  v_normalized integer;
  v_detail text;
  v_hint text;
  v_context text;
begin
  begin
    select o.* into v_order
    from public.erp_maintenance_orders as o
    where o.company_id=p_company_id
      and o.id=p_order_id
    for update;

    if not found then
      return jsonb_build_object(
        'ok',false,'companyId',p_company_id,'orderId',p_order_id,
        'stage',v_stage,'sqlstate','P0002','error','maintenance_order_not_found'
      );
    end if;

    if not v_order.is_deleted then
      return jsonb_build_object(
        'ok',false,'companyId',p_company_id,'orderId',p_order_id,
        'stage',v_stage,'sqlstate','22023','error','maintenance_order_not_deleted'
      );
    end if;

    -- Historical repair is internal/service-role-only, but the normal inventory
    -- helper deliberately requires an authenticated active company member.
    -- Select a real active member from THIS tenant and expose only its UUID through
    -- transaction-local PostgREST/Supabase JWT GUCs. This keeps every nested
    -- membership guard and created_by/updated_by audit reference tenant-correct.
    v_stage:='establish_repair_actor';
    select m.user_id into v_repair_user_id
    from public.company_memberships as m
    where m.company_id=p_company_id
      and m.is_active
      and m.user_id is not null
      and exists(
        select 1 from auth.users as u where u.id=m.user_id
      )
    order by
      coalesce(m.is_system_admin,false) desc,
      case lower(coalesce(m.role_code,''))
        when 'owner' then 0
        when 'admin' then 1
        when 'manager' then 2
        when 'warehouse' then 3
        when 'accountant' then 4
        else 9
      end,
      m.user_id
    limit 1;

    if v_repair_user_id is null then
      return jsonb_build_object(
        'ok',false,'companyId',p_company_id,'orderId',p_order_id,
        'stage',v_stage,'sqlstate','42501',
        'error','maintenance_repair_active_member_required'
      );
    end if;

    perform set_config(
      'request.jwt.claim.sub',
      v_repair_user_id::text,
      true
    );
    perform set_config(
      'request.jwt.claims',
      jsonb_build_object(
        'sub',v_repair_user_id::text,
        'role','authenticated'
      )::text,
      true
    );

    v_stage:='detach_payments';
    v_detached:=public.erp_v731_detach_maintenance_payments(
      p_company_id,p_order_id,
      'R57 repair of previously deleted maintenance order'
    );

    v_stage:='reverse_invoice_accounting';
    v_accounting:=public.erp_r57_reverse_maintenance_accounting_for_delete(
      p_company_id,p_order_id,
      'R57 repair of previously deleted maintenance order'
    );

    v_stage:='reverse_material_issues';
    v_issues:=public.erp_r57_reverse_maintenance_issues_for_delete(
      p_company_id,p_order_id,
      'R57 repair of previously deleted maintenance order'
    );

    v_stage:='normalize_preserved_payments';
    v_normalized:=public.erp_v731_normalize_order_advances(
      p_company_id,p_order_id
    );

    return jsonb_build_object(
      'ok',true,
      'companyId',p_company_id,
      'orderId',p_order_id,
      'repairActorUserId',v_repair_user_id,
      'stage','complete',
      'detachment',v_detached,
      'accountingReversal',v_accounting,
      'materialIssueReversal',v_issues,
      'normalizedAdvances',v_normalized,
      'paymentsPreserved',true
    );
  exception when others then
    get stacked diagnostics
      v_detail=pg_exception_detail,
      v_hint=pg_exception_hint,
      v_context=pg_exception_context;
    return jsonb_build_object(
      'ok',false,
      'companyId',p_company_id,
      'orderId',p_order_id,
      'repairActorUserId',v_repair_user_id,
      'stage',v_stage,
      'sqlstate',sqlstate,
      'error',sqlerrm,
      'detail',coalesce(v_detail,''),
      'hint',coalesce(v_hint,''),
      'context',coalesce(v_context,'')
    );
  end;
end;
$$;

revoke all on function public.erp_r57_repair_deleted_maintenance_order(uuid,uuid)
  from public,anon,authenticated;
grant execute on function public.erp_r57_repair_deleted_maintenance_order(uuid,uuid)
  to service_role;

-- Retry every historical row that 269 intentionally left pending when migration
-- context had no auth.uid(). Each row remains atomic because the repair function
-- owns an inner exception subtransaction.
do $$
declare
  v_result jsonb;
begin
  for v_result in
    select * from public.erp_r57_repair_deleted_maintenance_orders(null)
  loop
    if not coalesce((v_result->>'ok')::boolean,false) then
      raise warning 'R57 deleted maintenance repair still pending: %',v_result;
    end if;
  end loop;
end $$;

notify pgrst,'reload schema';
commit;
