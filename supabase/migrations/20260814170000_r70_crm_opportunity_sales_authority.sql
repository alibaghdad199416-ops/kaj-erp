-- Quality Line ERP R70 — authoritative CRM / Opportunity <-> Sales closure.
-- Forward-only. R61-R69 remain immutable.
begin;

-- One coherent CRM list projection. Sales linkage and downstream document values
-- are read from the canonical commercial tables in the same PostgreSQL statement
-- instead of trusting duplicated opportunity JSON fields.
create or replace function public.erp_r70_list_opportunities(p_company_id uuid)
returns setof jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_slug text;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'customer_service.view') then
    raise exception 'permission_denied:customer_service.view' using errcode='42501';
  end if;

  select slug into v_slug from public.companies where id=p_company_id and is_active;
  if v_slug is null then raise exception 'company_not_found' using errcode='23503'; end if;

  return query
  select public.erp_r9_filter_readable_json(
    p_company_id,
    'opportunities',
    (r.payload - array[
      'saleId','salesOrderId','salesOrderNumber','salesOrderStatus',
      'deliveryId','deliveryNumber','deliveryStatus',
      'invoiceId','invoiceNumber','invoiceStatus','invoiceCurrency',
      'paidAmount','remainingAmount','paymentStatus','workflowLinked',
      'workflowCanOpen','workflowCompleted'
    ]::text[]) ||
    jsonb_build_object(
      'id',r.record_id,
      'opportunityNumber',coalesce(nullif(r.payload->>'opportunityNumber',''),r.record_id),
      'salesOrderId',case when o.id is null then null else o.id::text end,
      'saleId',case when o.id is null then null else o.id::text end,
      'salesOrderNumber',o.order_number,
      'salesOrderStatus',o.status,
      'deliveryId',case when d.id is null then null else d.id::text end,
      'deliveryNumber',d.document_number,
      'deliveryStatus',d.status,
      'invoiceId',case when i.id is null then null else i.id::text end,
      'invoiceNumber',i.document_number,
      'invoiceStatus',i.status,
      'invoiceCurrency',i.payload->>'currency',
      'paidAmount',case when i.id is null then 0 else public.erp_try_numeric(i.payload->>'paidAmount',0) end,
      'remainingAmount',case when i.id is null then 0 else greatest(0,public.erp_try_numeric(
        i.payload->>'remainingAmount',
        public.erp_try_numeric(i.payload->>'totalAmount',0)-public.erp_try_numeric(i.payload->>'paidAmount',0)
      )) end,
      'paymentStatus',case
        when i.id is null then 'not_invoiced'
        when greatest(0,public.erp_try_numeric(i.payload->>'remainingAmount',
          public.erp_try_numeric(i.payload->>'totalAmount',0)-public.erp_try_numeric(i.payload->>'paidAmount',0)))<=0.001 then 'paid'
        when public.erp_try_numeric(i.payload->>'paidAmount',0)>0 then 'partial'
        else 'unpaid' end,
      'workflowLinked',o.id is not null,
      'workflowCanOpen',o.id is not null,
      'workflowCompleted',i.id is not null
        and lower(coalesce(i.status,'')) in ('approved','paid','completed')
        and greatest(0,public.erp_try_numeric(i.payload->>'remainingAmount',
          public.erp_try_numeric(i.payload->>'totalAmount',0)-public.erp_try_numeric(i.payload->>'paidAmount',0)))<=0.001,
      'updatedAt',r.updated_at,
      '_cloudUpdatedAt',r.updated_at
    )
  )
  from public.erp_records r
  left join lateral (
    select so.*
    from public.erp_sales_orders_cloud so
    where so.company_id=p_company_id
      and so.opportunity_id=r.record_id
      and not so.is_deleted
    order by so.updated_at desc,so.created_at desc,so.id desc
    limit 1
  ) o on true
  left join lateral (
    select doc.*
    from public.erp_commercial_workflow_documents doc
    where o.id is not null
      and doc.company_id=p_company_id
      and doc.parent_id=o.id
      and doc.module='sales'
      and doc.document_type='delivery'
      and not doc.is_deleted
    order by doc.updated_at desc,doc.created_at desc,doc.id desc
    limit 1
  ) d on true
  left join lateral (
    select doc.*
    from public.erp_commercial_workflow_documents doc
    where o.id is not null
      and doc.company_id=p_company_id
      and doc.parent_id=o.id
      and doc.module='sales'
      and doc.document_type='invoice'
      and not doc.is_deleted
    order by doc.updated_at desc,doc.created_at desc,doc.id desc
    limit 1
  ) i on true
  where r.company_id=v_slug
    and r.entity_type='opportunities'
    and r.deleted_at is null
  order by r.updated_at desc
  limit 500;
end $$;

revoke all on function public.erp_r70_list_opportunities(uuid) from public,anon;
grant execute on function public.erp_r70_list_opportunities(uuid) to authenticated,service_role;

-- R70 command keeps the existing CloudFeatureCommand client boundary while
-- making CRM validation and server-owned fields explicit.
create or replace function public.erp_r70_opportunity_command(
  p_action text,
  p_payload jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_company uuid;
  v_slug text;
  v_admin boolean;
  v_payload jsonb:=coalesce(p_payload,'{}'::jsonb);
  v_record jsonb:=coalesce(p_payload->'record','{}'::jsonb);
  v_existing jsonb:='{}'::jsonb;
  v_result jsonb;
  v_id text;
  v_customer text;
  v_currency text;
  v_assignee text;
  v_stage text;
  v_expected numeric:=0;
  v_probability numeric:=0;
begin
  select company_uuid,company_slug,is_admin into v_company,v_slug,v_admin
  from public.erp_active_company_context();
  if v_company is null then raise exception 'membership_not_found' using errcode='42501'; end if;

  if p_action='list' then
    if not v_admin and not public.erp_cloud_user_has_permission(v_company,'customer_service.view') then
      raise exception 'permission_denied:customer_service.view' using errcode='42501';
    end if;
    select coalesce(jsonb_agg(t.value),'[]'::jsonb) into v_result
    from public.erp_r70_list_opportunities(v_company) as t(value);
    return v_result;
  end if;

  if p_action='save' then
    v_id:=coalesce(nullif(btrim(v_record->>'id'),''),gen_random_uuid()::text);
    select coalesce(r.payload,'{}'::jsonb) into v_existing
    from public.erp_records r
    where r.company_id=v_slug and r.entity_type='opportunities'
      and r.record_id=v_id and r.deleted_at is null
    limit 1;
    v_existing:=coalesce(v_existing,'{}'::jsonb);

    v_customer:=nullif(btrim(v_record->>'customerId'),'');
    if v_customer is null then raise exception 'opportunity_customer_required' using errcode='22023'; end if;
    if not exists(select 1 from public.erp_customers c
      where c.company_id=v_company and c.id=v_customer and not c.is_deleted) then
      raise exception 'opportunity_customer_mismatch' using errcode='23503';
    end if;

    v_currency:=upper(btrim(coalesce(v_record->>'currency','')));
    if v_currency not in ('USD','IQD') then
      raise exception 'opportunity_currency_invalid' using errcode='22023';
    end if;

    begin
      v_expected:=coalesce(nullif(btrim(v_record->>'expectedValue'),'')::numeric,0);
    exception when others then
      raise exception 'opportunity_expected_value_invalid' using errcode='22023';
    end;
    if v_expected<0 then raise exception 'opportunity_expected_value_invalid' using errcode='22023'; end if;

    begin
      v_probability:=coalesce(nullif(btrim(v_record->>'probability'),'')::numeric,0);
    exception when others then
      raise exception 'opportunity_probability_invalid' using errcode='22023';
    end;
    if v_probability<0 or v_probability>100 then
      raise exception 'opportunity_probability_invalid' using errcode='22023';
    end if;

    v_assignee:=nullif(btrim(v_record->>'assignedUserId'),'');
    if v_assignee is not null then
      begin
        if not exists(select 1 from public.company_memberships m
          where m.company_id=v_company and m.user_id=v_assignee::uuid and m.is_active) then
          raise exception 'opportunity_responsible_user_invalid' using errcode='23503';
        end if;
      exception when invalid_text_representation then
        raise exception 'opportunity_responsible_user_invalid' using errcode='23503';
      end;
    end if;

    v_stage:=lower(btrim(coalesce(v_record->>'stage','new')));
    if v_stage in ('won','closed') then
      raise exception 'opportunity_terminal_stage_sales_owned' using errcode='22023';
    end if;
    if v_stage='lost' and lower(coalesce(v_existing->>'status','pending'))<>'lost' then
      raise exception 'opportunity_lost_requires_transition' using errcode='22023';
    end if;

    -- Once a canonical sales order exists, customer and currency become
    -- commercial identity and cannot silently diverge in CRM.
    if exists(select 1 from public.erp_sales_orders_cloud o
      where o.company_id=v_company and o.opportunity_id=v_id and not o.is_deleted) then
      if coalesce(nullif(v_existing->>'customerId',''),v_customer)<>v_customer then
        raise exception 'opportunity_sales_customer_locked' using errcode='P0001';
      end if;
      if upper(coalesce(nullif(v_existing->>'currency',''),v_currency))<>v_currency then
        raise exception 'opportunity_sales_currency_locked' using errcode='P0001';
      end if;
    end if;

    -- Sales/document/payment state is server-owned. A client edit cannot forge
    -- a Won state or a linked invoice/payment projection.
    v_record:=(v_record - array[
      'status','closedAt','saleId','salesOrderId','salesOrderNumber','salesOrderStatus',
      'deliveryId','deliveryNumber','deliveryStatus','invoiceId','invoiceNumber',
      'invoiceStatus','invoiceCurrency','paidAmount','remainingAmount','paymentStatus',
      'workflowLinked','workflowCanOpen','workflowCompleted','opportunityStatusSource'
    ]::text[]) || jsonb_build_object(
      'id',v_id,'customerId',v_customer,'currency',v_currency,
      'expectedValue',v_expected,'probability',v_probability,
      'status',case when v_existing='{}'::jsonb then 'pending'
                    else coalesce(nullif(v_existing->>'status',''),'pending') end,
      'closedAt',case when v_existing='{}'::jsonb then null else v_existing->'closedAt' end
    );
    v_payload:=jsonb_set(v_payload,'{record}',v_record,true);
    v_result:=public.erp_r49_opportunity_command('save',v_payload);
    perform public.erp_sync_opportunity_sales_lifecycle(v_company,v_id);
    select t.value into v_result
    from public.erp_r70_list_opportunities(v_company) as t(value)
    where t.value->>'id'=v_id limit 1;
    return coalesce(v_result,'{}'::jsonb);
  end if;

  if p_action='mark_lost' then
    -- R49 already enforces optimistic concurrency and rejects active Sales.
    v_result:=public.erp_r49_opportunity_command('mark_lost',v_payload);
    return v_result;
  end if;

  if p_action='delete' then
    v_id:=nullif(btrim(v_payload->>'id'),'');
    if v_id is null then raise exception 'opportunity_id_required' using errcode='22023'; end if;
    if exists(select 1 from public.erp_sales_orders_cloud o
      where o.company_id=v_company and o.opportunity_id=v_id and not o.is_deleted) then
      raise exception 'opportunity_has_sales_history' using errcode='P0001';
    end if;
    return public.erp_r49_opportunity_command('delete',v_payload);
  end if;

  if p_action='mark_won' then
    -- Explicitly close the pre-normalized shortcut that created a generic sale,
    -- fake invoice number and changed the car to sold directly from CRM.
    raise exception 'opportunity_won_owned_by_sales_workflow' using errcode='0A000';
  end if;

  raise exception 'unsupported_opportunity_action:%',p_action using errcode='22023';
end $$;

revoke all on function public.erp_r70_opportunity_command(text,jsonb) from public,anon;
grant execute on function public.erp_r70_opportunity_command(text,jsonb) to authenticated,service_role;

-- Keep the established client RPC name. Only the opportunity area is advanced
-- to R70; all other cloud modules retain their verified R35/R69 routing.
create or replace function public.erp_r37_cloud_command(
  p_area text,p_action text,p_payload jsonb
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
begin
  if p_area='opportunity' then
    return public.erp_r70_opportunity_command(p_action,coalesce(p_payload,'{}'::jsonb));
  end if;
  return public.erp_r35_cloud_command(p_area,p_action,coalesce(p_payload,'{}'::jsonb));
end $$;
revoke all on function public.erp_r37_cloud_command(text,text,jsonb) from public,anon;
grant execute on function public.erp_r37_cloud_command(text,text,jsonb) to authenticated,service_role;

-- Harden the actual SalesOrderDraftPage runtime endpoint. The opportunity row is
-- locked before lookup/creation, making retry/double-click conversion idempotent.
create or replace function public.erp_r49_create_sales_order(
  p_company_id uuid,p_payload jsonb
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_opportunity text:=nullif(btrim(coalesce(p_payload->>'opportunityId','')),'');
  v_slug text;
  v_opp jsonb;
  v_existing uuid;
  v_customer text;
  v_currency text;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'sales.create') then
    raise exception 'permission_denied:sales.create' using errcode='42501';
  end if;

  if v_opportunity is null then
    return public.erp_v2300_create_sales_order(p_company_id,coalesce(p_payload,'{}'::jsonb));
  end if;

  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'customer_service.update') then
    raise exception 'permission_denied:customer_service.update' using errcode='42501';
  end if;

  select slug into v_slug from public.companies where id=p_company_id and is_active;
  if v_slug is null then raise exception 'company_not_found' using errcode='23503'; end if;

  select r.payload into v_opp
  from public.erp_records r
  where r.company_id=v_slug and r.entity_type='opportunities'
    and r.record_id=v_opportunity and r.deleted_at is null
  for update;
  if v_opp is null then raise exception 'opportunity_not_found' using errcode='23503'; end if;

  -- Locking the opportunity serializes concurrent conversion attempts. Reuse the
  -- existing active order instead of creating a duplicate on retry/double-click.
  select o.id into v_existing
  from public.erp_sales_orders_cloud o
  where o.company_id=p_company_id and o.opportunity_id=v_opportunity and not o.is_deleted
  order by o.updated_at desc,o.created_at desc,o.id desc limit 1;
  if v_existing is not null then return v_existing; end if;

  if lower(coalesce(v_opp->>'status','pending'))='lost' then
    raise exception 'opportunity_is_lost' using errcode='P0001';
  end if;
  if lower(coalesce(v_opp->>'status','pending'))='won' then
    raise exception 'opportunity_already_won' using errcode='P0001';
  end if;

  v_customer:=nullif(btrim(v_opp->>'customerId'),'');
  if v_customer is null then raise exception 'opportunity_customer_required' using errcode='22023'; end if;
  if nullif(btrim(p_payload->>'customerId'),'') is distinct from v_customer then
    raise exception 'opportunity_customer_mismatch' using errcode='P0001';
  end if;

  v_currency:=upper(btrim(coalesce(v_opp->>'currency','')));
  if v_currency not in ('USD','IQD') then
    raise exception 'opportunity_currency_invalid' using errcode='22023';
  end if;
  if upper(btrim(coalesce(p_payload->>'currency','')))<>v_currency then
    raise exception 'opportunity_currency_mismatch' using errcode='P0001';
  end if;

  v_existing:=public.erp_v2300_create_sales_order(
    p_company_id,
    coalesce(p_payload,'{}'::jsonb)||jsonb_build_object(
      'opportunityId',v_opportunity,
      'customerId',v_customer,
      'currency',v_currency
    )
  );
  perform public.erp_sync_opportunity_sales_lifecycle(p_company_id,v_opportunity);
  return v_existing;
end $$;

revoke all on function public.erp_r49_create_sales_order(uuid,jsonb) from public,anon;
grant execute on function public.erp_r49_create_sales_order(uuid,jsonb) to authenticated,service_role;

-- Make the server ownership rule explicit for existing records as well: legacy
-- fake invoice/order aliases are cleared only when a canonical active Sales
-- Order is present, after which the canonical synchronizer writes true values.
do $$ declare r record; begin
  for r in
    select distinct o.company_id,o.opportunity_id
    from public.erp_sales_orders_cloud o
    where not o.is_deleted and nullif(btrim(coalesce(o.opportunity_id,'')),'') is not null
  loop
    perform public.erp_sync_opportunity_sales_lifecycle(r.company_id,r.opportunity_id);
  end loop;
end $$;

notify pgrst,'reload schema';
commit;
