begin;

create or replace function public.erp_manage_commercial_order_component_v3(
  p_company_id uuid,
  p_module text,
  p_order_id uuid,
  p_component_type text,
  p_component_id uuid,
  p_action text,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_module text := lower(btrim(coalesce(p_module,'')));
  v_type text := lower(btrim(coalesce(p_component_type,'')));
  v_action text := lower(btrim(coalesce(p_action,'')));
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
    return jsonb_build_object('ok',false,'code','invalid_workflow_module','error','Unsupported workflow module.','module',v_module);
  end if;
  if v_type not in ('order','delivery','receipt','invoice','payment') then
    return jsonb_build_object('ok',false,'code','invalid_component_type','error','Unsupported workflow component.','componentType',v_type);
  end if;
  if v_action not in ('approve','delete','cancel','reverse','reopen') then
    return jsonb_build_object('ok',false,'code','invalid_component_action','error','Unsupported workflow action.','action',v_action);
  end if;

  if v_type='invoice' and v_action='approve' then
    v_result := public.erp_v762_approve_workflow_invoice(
      p_company_id,
      p_component_id,
      v_module
    );
  else
    v_result := public.erp_manage_commercial_order_component_v2(
      p_company_id,
      v_module,
      p_order_id,
      v_type,
      p_component_id,
      v_action,
      p_reason
    );
  end if;

  return coalesce(v_result,'{}'::jsonb) || jsonb_build_object(
    'ok',true,
    'module',v_module,
    'orderId',p_order_id,
    'componentType',v_type,
    'componentId',p_component_id,
    'action',v_action
  );
exception when others then
  return jsonb_build_object(
    'ok',false,
    'code',sqlstate,
    'error',sqlerrm,
    'details',jsonb_build_object(
      'module',v_module,
      'orderId',p_order_id,
      'componentType',v_type,
      'componentId',p_component_id,
      'action',v_action
    )::text,
    'hint','Refresh the order, verify the linked workflow document, and retry.'
  );
end;
$$;

revoke all on function public.erp_manage_commercial_order_component_v3(uuid,text,uuid,text,uuid,text,text) from public,anon;
grant execute on function public.erp_manage_commercial_order_component_v3(uuid,text,uuid,text,uuid,text,text) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
