-- Quality Line ERP R70.1 — Sales -> Opportunity authoritative readback.
begin;

create or replace function public.erp_r70_get_sales_opportunity_context(
  p_company_id uuid,p_order_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_slug text;
  v_opportunity_id text;
  v_payload jsonb;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'sales.view') then
    raise exception 'permission_denied:sales.view' using errcode='42501';
  end if;

  select slug into v_slug from public.companies where id=p_company_id and is_active;
  if v_slug is null then raise exception 'company_not_found' using errcode='23503'; end if;

  select nullif(btrim(o.opportunity_id),'') into v_opportunity_id
  from public.erp_sales_orders_cloud o
  where o.company_id=p_company_id and o.id=p_order_id and not o.is_deleted;
  if v_opportunity_id is null then return '{}'::jsonb; end if;

  select jsonb_build_object(
    'id',r.record_id,
    'opportunityId',r.record_id,
    'opportunityNumber',coalesce(nullif(r.payload->>'opportunityNumber',''),r.record_id),
    'title',r.payload->>'title',
    'customerId',r.payload->>'customerId',
    'customerName',r.payload->>'customerName',
    'stage',r.payload->>'stage',
    'status',r.payload->>'status',
    'expectedValue',public.erp_try_numeric(r.payload->>'expectedValue',0),
    'currency',upper(coalesce(nullif(r.payload->>'currency',''),'USD')),
    'probability',greatest(0,least(100,public.erp_try_numeric(r.payload->>'probability',0))),
    'assignedUserId',r.payload->>'assignedUserId',
    'assignedUserName',r.payload->>'assignedUserName',
    'expectedCloseDate',r.payload->>'expectedCloseDate',
    'closedAt',r.payload->>'closedAt',
    'updatedAt',r.updated_at
  ) into v_payload
  from public.erp_records r
  where r.company_id=v_slug and r.entity_type='opportunities'
    and r.record_id=v_opportunity_id and r.deleted_at is null
  limit 1;

  return coalesce(v_payload,'{}'::jsonb);
end $$;

revoke all on function public.erp_r70_get_sales_opportunity_context(uuid,uuid)
  from public,anon;
grant execute on function public.erp_r70_get_sales_opportunity_context(uuid,uuid)
  to authenticated,service_role;

-- R62 remains the stable Flutter endpoint. R70.1 extends the coherent snapshot
-- in the same PostgreSQL statement with the CRM context of a Sales order.
create or replace function public.erp_r62_get_commercial_order_snapshot(
  p_company_id uuid,p_order_id uuid,p_purchase boolean
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_details jsonb;
  v_reconciliation jsonb;
  v_opportunity jsonb:='{}'::jsonb;
begin
  perform public.erp_active_company_context(p_company_id);
  v_details:=public.erp_r28_get_commercial_order_complete_details(
    p_company_id,p_order_id,p_purchase
  );
  select coalesce(jsonb_agg(row_value),'[]'::jsonb)
    into v_reconciliation
  from public.erp_r57_commercial_reconciliation(
    p_company_id,p_order_id,case when p_purchase then 'purchases' else 'sales' end
  ) as row_value;

  if not p_purchase then
    v_opportunity:=public.erp_r70_get_sales_opportunity_context(p_company_id,p_order_id);
    if v_opportunity<>'{}'::jsonb then
      v_details:=jsonb_set(
        coalesce(v_details,'{}'::jsonb),
        '{order}',
        coalesce(v_details->'order','{}'::jsonb)||jsonb_build_object(
          'opportunityId',v_opportunity->>'opportunityId',
          'opportunityNumber',v_opportunity->>'opportunityNumber',
          'opportunityTitle',v_opportunity->>'title',
          'opportunityStage',v_opportunity->>'stage',
          'opportunityStatus',v_opportunity->>'status',
          'opportunityProbability',v_opportunity->'probability',
          'opportunityResponsibleUser',v_opportunity->>'assignedUserName'
        ),true
      );
    end if;
  end if;

  return jsonb_set(
    jsonb_set(
      coalesce(v_details,'{}'::jsonb),
      '{reconciliation}',coalesce(v_reconciliation,'[]'::jsonb),true
    ),
    '{opportunity}',coalesce(v_opportunity,'{}'::jsonb),true
  );
end $$;

revoke all on function public.erp_r62_get_commercial_order_snapshot(uuid,uuid,boolean)
  from public,anon;
grant execute on function public.erp_r62_get_commercial_order_snapshot(uuid,uuid,boolean)
  to authenticated,service_role;

-- The existing CRM lookup is also enriched so opening the linked Sales order
-- can show a human Opportunity reference without another client RPC.
create or replace function public.erp_r9_find_sales_order_by_opportunity(
  p_company_id uuid,p_opportunity_id text
) returns setof jsonb
language sql
stable
security definer
set search_path=public
as $$
  select public.erp_r9_filter_result_json(
    p_company_id,'sales',
    jsonb_build_object(
      'id',o.id,'orderNumber',o.order_number,'status',o.status,
      'opportunityId',o.opportunity_id,
      'opportunityNumber',coalesce(nullif(r.payload->>'opportunityNumber',''),o.opportunity_id),
      'opportunityStage',r.payload->>'stage','opportunityStatus',r.payload->>'status',
      'customerId',o.customer_id,'currency',o.currency,
      'updatedAt',o.updated_at
    ),'sales.view'
  )
  from public.erp_sales_orders_cloud o
  join public.companies c on c.id=o.company_id
  left join public.erp_records r
    on r.company_id=c.slug and r.entity_type='opportunities'
   and r.record_id=o.opportunity_id and r.deleted_at is null
  where o.company_id=p_company_id
    and o.opportunity_id=p_opportunity_id
    and not o.is_deleted
    and public.is_active_company_member(p_company_id)
  order by o.updated_at desc,o.created_at desc,o.id desc
  limit 1;
$$;

revoke all on function public.erp_r9_find_sales_order_by_opportunity(uuid,text)
  from public,anon;
grant execute on function public.erp_r9_find_sales_order_by_opportunity(uuid,text)
  to authenticated,service_role;

notify pgrst,'reload schema';
commit;
