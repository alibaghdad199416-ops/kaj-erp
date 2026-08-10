-- Quality Line ERP 22.9.8 R4 / V23.0.0 runtime closure
-- Atomic commercial draft RPCs, stable PostgREST contracts, and enterprise audit feed.
begin;

create or replace function public.erp_v2300_create_purchase_order(
  p_company_id uuid,
  p_payload jsonb
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_order_id uuid:=gen_random_uuid();
  v_number text:='PO-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');
  v_supplier_id text:=btrim(coalesce(p_payload->>'supplierId',''));
  v_currency text:=upper(btrim(coalesce(p_payload->>'currency','')));
  v_exchange_rate numeric:=coalesce(nullif(p_payload->>'exchangeRate','')::numeric,0);
  v_discount numeric:=coalesce(nullif(p_payload->>'discount','')::numeric,0);
  v_notes text:=nullif(btrim(coalesce(p_payload->>'notes','')),'');
  v_opportunity_id text:=nullif(btrim(coalesce(p_payload->>'opportunityId','')),'');
  v_effective_at timestamptz:=coalesce(nullif(p_payload->>'effectiveAt','')::timestamptz,now());
  v_items jsonb:=coalesce(p_payload->'items','[]'::jsonb);
  v_subtotal numeric;
  v_item jsonb;
  v_existing uuid;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant_denied' using errcode='42501'; end if;
  perform public.erp_validate_operational_date(p_company_id,'purchases',v_effective_at);
  if v_supplier_id='' then raise exception 'supplier_required' using errcode='22023'; end if;
  if v_currency not in ('USD','IQD') or v_exchange_rate<=0 then
    raise exception 'invalid_currency_or_exchange_rate' using errcode='22023';
  end if;
  if jsonb_typeof(v_items)<>'array' or jsonb_array_length(v_items)=0 then
    raise exception 'purchase_items_required' using errcode='22023';
  end if;
  if v_opportunity_id is not null then
    select id into v_existing from public.erp_purchase_orders_cloud
    where company_id=p_company_id and opportunity_id=v_opportunity_id and not is_deleted
    order by updated_at desc limit 1 for update;
    if v_existing is not null then return v_existing; end if;
  end if;
  perform 1 from public.erp_suppliers
  where company_id=p_company_id and id=v_supplier_id and not is_deleted;
  if not found then raise exception 'supplier_not_found' using errcode='23503'; end if;

  v_subtotal:=public.erp_cloud_commercial_items_subtotal(p_company_id,v_items,true);
  if v_discount<0 or v_discount>v_subtotal then
    raise exception 'invalid_discount' using errcode='22023';
  end if;

  insert into public.erp_purchase_orders_cloud(
    id,company_id,order_number,supplier_id,opportunity_id,status,currency,
    exchange_rate,subtotal,discount,total,notes,effective_at
  ) values(
    v_order_id,p_company_id,v_number,v_supplier_id,v_opportunity_id,'draft',v_currency,
    v_exchange_rate,v_subtotal,v_discount,v_subtotal-v_discount,v_notes,v_effective_at
  );

  for v_item in select value from jsonb_array_elements(v_items) loop
    insert into public.erp_purchase_order_items_cloud(
      company_id,order_id,item_type,item_id,description,quantity,unit_cost,line_total
    ) values(
      p_company_id,v_order_id,lower(btrim(v_item->>'itemType')),btrim(v_item->>'itemId'),
      coalesce(v_item->>'description',''),(v_item->>'quantity')::int,(v_item->>'unitCost')::numeric,
      (v_item->>'quantity')::numeric*(v_item->>'unitCost')::numeric
    );
  end loop;
  return v_order_id;
exception when unique_violation then
  if v_opportunity_id is not null then
    select id into v_existing from public.erp_purchase_orders_cloud
    where company_id=p_company_id and opportunity_id=v_opportunity_id and not is_deleted
    order by updated_at desc limit 1;
    if v_existing is not null then return v_existing; end if;
  end if;
  raise;
end;
$$;

create or replace function public.erp_v2300_create_sales_order(
  p_company_id uuid,
  p_payload jsonb
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_order_id uuid:=gen_random_uuid();
  v_number text:='SO-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');
  v_customer_id text:=btrim(coalesce(p_payload->>'customerId',''));
  v_currency text:=upper(btrim(coalesce(p_payload->>'currency','')));
  v_exchange_rate numeric:=coalesce(nullif(p_payload->>'exchangeRate','')::numeric,0);
  v_discount numeric:=coalesce(nullif(p_payload->>'discount','')::numeric,0);
  v_notes text:=nullif(btrim(coalesce(p_payload->>'notes','')),'');
  v_opportunity_id text:=nullif(btrim(coalesce(p_payload->>'opportunityId','')),'');
  v_effective_at timestamptz:=coalesce(nullif(p_payload->>'effectiveAt','')::timestamptz,now());
  v_items jsonb:=coalesce(p_payload->'items','[]'::jsonb);
  v_subtotal numeric;
  v_item jsonb;
  v_existing uuid;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant_denied' using errcode='42501'; end if;
  perform public.erp_validate_operational_date(p_company_id,'sales',v_effective_at);
  if v_customer_id='' then raise exception 'customer_required' using errcode='22023'; end if;
  if v_currency not in ('USD','IQD') or v_exchange_rate<=0 then
    raise exception 'invalid_currency_or_exchange_rate' using errcode='22023';
  end if;
  if jsonb_typeof(v_items)<>'array' or jsonb_array_length(v_items)=0 then
    raise exception 'sales_items_required' using errcode='22023';
  end if;
  if v_opportunity_id is not null then
    select id into v_existing from public.erp_sales_orders_cloud
    where company_id=p_company_id and opportunity_id=v_opportunity_id and not is_deleted
    order by updated_at desc limit 1 for update;
    if v_existing is not null then return v_existing; end if;
  end if;
  perform 1 from public.erp_customers
  where company_id=p_company_id and id=v_customer_id and not is_deleted;
  if not found then raise exception 'customer_not_found' using errcode='23503'; end if;

  v_subtotal:=public.erp_cloud_commercial_items_subtotal(p_company_id,v_items,false);
  if v_discount<0 or v_discount>v_subtotal then
    raise exception 'invalid_discount' using errcode='22023';
  end if;

  insert into public.erp_sales_orders_cloud(
    id,company_id,order_number,customer_id,opportunity_id,status,currency,
    exchange_rate,subtotal,discount,total,notes,effective_at
  ) values(
    v_order_id,p_company_id,v_number,v_customer_id,v_opportunity_id,'draft',v_currency,
    v_exchange_rate,v_subtotal,v_discount,v_subtotal-v_discount,v_notes,v_effective_at
  );

  for v_item in select value from jsonb_array_elements(v_items) loop
    insert into public.erp_sales_order_items_cloud(
      company_id,order_id,item_type,item_id,description,quantity,unit_price,line_total
    ) values(
      p_company_id,v_order_id,lower(btrim(v_item->>'itemType')),btrim(v_item->>'itemId'),
      coalesce(v_item->>'description',''),(v_item->>'quantity')::int,(v_item->>'unitPrice')::numeric,
      (v_item->>'quantity')::numeric*(v_item->>'unitPrice')::numeric
    );
  end loop;
  return v_order_id;
exception when unique_violation then
  if v_opportunity_id is not null then
    select id into v_existing from public.erp_sales_orders_cloud
    where company_id=p_company_id and opportunity_id=v_opportunity_id and not is_deleted
    order by updated_at desc limit 1;
    if v_existing is not null then return v_existing; end if;
  end if;
  raise;
end;
$$;

create or replace function public.erp_v2300_update_purchase_order(
  p_company_id uuid,
  p_payload jsonb
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_order_id uuid:=(p_payload->>'orderId')::uuid;
  v_effective_at timestamptz:=coalesce(nullif(p_payload->>'effectiveAt','')::timestamptz,now());
begin
  perform public.erp_validate_operational_date(p_company_id,'purchases',v_effective_at);
  perform public.erp_update_cloud_purchase_order_with_links(
    p_company_id,v_order_id,btrim(p_payload->>'supplierId'),upper(btrim(p_payload->>'currency')),
    (p_payload->>'exchangeRate')::numeric,coalesce(nullif(p_payload->>'discount','')::numeric,0),
    coalesce(p_payload->'items','[]'::jsonb),nullif(btrim(coalesce(p_payload->>'notes','')),'')
  );
  perform public.erp_set_operational_effective_at(p_company_id,'purchases','order',v_order_id,v_effective_at);
  return jsonb_build_object('ok',true,'orderId',v_order_id,'effectiveAt',v_effective_at);
end;
$$;

create or replace function public.erp_v2300_update_sales_order(
  p_company_id uuid,
  p_payload jsonb
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_order_id uuid:=(p_payload->>'orderId')::uuid;
  v_effective_at timestamptz:=coalesce(nullif(p_payload->>'effectiveAt','')::timestamptz,now());
begin
  perform public.erp_validate_operational_date(p_company_id,'sales',v_effective_at);
  perform public.erp_update_cloud_sales_order_with_links(
    p_company_id,v_order_id,btrim(p_payload->>'customerId'),upper(btrim(p_payload->>'currency')),
    (p_payload->>'exchangeRate')::numeric,coalesce(nullif(p_payload->>'discount','')::numeric,0),
    coalesce(p_payload->'items','[]'::jsonb),nullif(btrim(coalesce(p_payload->>'notes','')),'')
  );
  perform public.erp_set_operational_effective_at(p_company_id,'sales','order',v_order_id,v_effective_at);
  return jsonb_build_object('ok',true,'orderId',v_order_id,'effectiveAt',v_effective_at);
end;
$$;

create or replace function public.erp_v2300_record_app_audit(
  p_company_id uuid,
  p_action text,
  p_module text,
  p_description text,
  p_entity_type text default null,
  p_entity_id text default null,
  p_outcome text default 'success',
  p_severity text default 'info',
  p_source text default 'application',
  p_user_name text default null,
  p_metadata jsonb default '{}'::jsonb,
  p_correlation_id text default null
) returns bigint
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id bigint;
  v_action text:=lower(btrim(coalesce(p_action,'other')));
  v_operation text;
  v_metadata jsonb;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'audit_company_access_denied' using errcode='42501'; end if;
  v_operation:=case v_action
    when 'login' then 'LOGIN'
    when 'logout' then 'LOGOUT'
    when 'export' then 'EXPORT'
    when 'restore' then 'RESTORE'
    else 'OTHER'
  end;
  v_metadata:=coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object(
    'action',v_action,'module',coalesce(nullif(btrim(p_module),''),'application'),
    'description',coalesce(p_description,''),'entityType',coalesce(nullif(btrim(p_entity_type),''),p_module),
    'outcome',coalesce(nullif(btrim(p_outcome),''),'success'),'severity',coalesce(nullif(btrim(p_severity),''),'info'),
    'userName',nullif(btrim(coalesce(p_user_name,'')),''),'correlationId',nullif(btrim(coalesce(p_correlation_id,'')),'')
  );
  insert into public.erp_audit_log(company_id,actor_uid,operation,table_name,record_id,source,metadata)
  values(p_company_id,public.erp_audit_actor_uid(),v_operation,coalesce(nullif(btrim(p_entity_type),''),nullif(btrim(p_module),''),'application'),
    nullif(btrim(coalesce(p_entity_id,'')),''),coalesce(nullif(btrim(p_source),''),'application'),v_metadata)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.erp_v2300_audit_feed(
  p_company_id uuid,
  p_limit integer default 1000,
  p_query text default null,
  p_outcome text default 'all'
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_slug text;
  v_query text:=lower(btrim(coalesce(p_query,'')));
  v_outcome text:=lower(btrim(coalesce(p_outcome,'all')));
  v_result jsonb;
begin
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'audit.view') then
    raise exception 'audit_view_permission_required' using errcode='42501';
  end if;
  select slug into v_slug from public.companies where id=p_company_id;

  select coalesce(jsonb_agg(row_obj order by occurred_at desc,audit_id desc),'[]'::jsonb)
  into v_result
  from (
    select
      a.occurred_at,
      a.id audit_id,
      jsonb_build_object(
        'id',a.id::text,
        'userName',coalesce(nullif(a.metadata->>'userName',''),
          (select nullif(r.payload->>'fullName','') from public.erp_records r
           where r.company_id=v_slug and r.entity_type='users' and r.deleted_at is null
             and nullif(r.payload->>'cloudAuthUid','')=a.actor_uid order by r.updated_at desc limit 1),
          a.actor_uid,'System'),
        'action',coalesce(nullif(a.metadata->>'action',''),lower(a.operation)),
        'module',coalesce(nullif(a.metadata->>'module',''),a.table_name),
        'description',coalesce(nullif(a.metadata->>'description',''),
          initcap(lower(a.operation))||' '||a.table_name||coalesce(' #'||a.record_id,'')),
        'entityType',coalesce(nullif(a.metadata->>'entityType',''),a.table_name),
        'entityId',a.record_id,
        'severity',coalesce(nullif(a.metadata->>'severity',''),'info'),
        'outcome',coalesce(nullif(a.metadata->>'outcome',''),'success'),
        'source',a.source,
        'correlationId',coalesce(nullif(a.metadata->>'correlationId',''),a.request_id),
        'metadataJson',jsonb_build_object(
          'changedFields',a.changed_fields,
          'metadata',a.metadata,
          'operation',a.operation,
          'table',a.table_name,
          'recordId',a.record_id
        )::text,
        'createdAt',a.occurred_at
      ) row_obj
    from public.erp_audit_log a
    where a.company_id=p_company_id
      and (v_outcome='all' or lower(coalesce(a.metadata->>'outcome','success'))=v_outcome)
      and (v_query='' or lower(concat_ws(' ',a.actor_uid,a.operation,a.table_name,a.record_id,
            a.metadata->>'userName',a.metadata->>'action',a.metadata->>'module',a.metadata->>'description')) like '%'||v_query||'%')
    order by a.occurred_at desc,a.id desc
    limit greatest(1,least(coalesce(p_limit,1000),1000))
  ) q;
  return v_result;
end;
$$;


-- Live commercial details: preserve the established rich payload while
-- exposing the parent operational timestamp explicitly for the UI.
create or replace function public.erp_v2300_get_commercial_order_complete_details(
  p_company_id uuid,p_order_id uuid,p_purchase boolean
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_result jsonb;
  v_effective_at timestamptz;
begin
  if not public.erp_is_company_member(p_company_id) then
    raise exception 'tenant denied' using errcode='42501';
  end if;
  v_result:=public.erp_get_cloud_commercial_order_complete_details(
    p_company_id,p_order_id,p_purchase);
  if p_purchase then
    select effective_at into v_effective_at
    from public.erp_purchase_orders_cloud
    where company_id=p_company_id and id=p_order_id and not is_deleted;
  else
    select effective_at into v_effective_at
    from public.erp_sales_orders_cloud
    where company_id=p_company_id and id=p_order_id and not is_deleted;
  end if;
  if v_result is null then v_result:='{}'::jsonb; end if;
  v_result:=jsonb_set(
    v_result,'{order}',coalesce(v_result->'order','{}'::jsonb)||jsonb_build_object(
      'effectiveAt',v_effective_at,'operationalDateTime',v_effective_at),true);
  return v_result;
end;
$$;

revoke all on function public.erp_v2300_get_commercial_order_complete_details(uuid,uuid,boolean) from public,anon;
grant execute on function public.erp_v2300_get_commercial_order_complete_details(uuid,uuid,boolean) to authenticated,service_role;

-- ---------------------------------------------------------------------------
-- Payment operational dates: every posted payment is checked against the
-- operational period before any cash/journal side effects are created.
-- ---------------------------------------------------------------------------
create or replace function public.erp_v2300_validate_payment_dates(
  p_company_id uuid,p_module text,p_payments jsonb
) returns void
language plpgsql security definer set search_path=public as $$
declare p jsonb; v_date timestamptz;
begin
  if p_payments is null or jsonb_typeof(p_payments)<>'array' or jsonb_array_length(p_payments)=0 then
    raise exception 'payment_batch_required';
  end if;
  for p in select value from jsonb_array_elements(p_payments) loop
    v_date:=public.erp_try_timestamptz(p->>'paymentDate',null);
    if v_date is null then raise exception 'payment_date_required'; end if;
    perform public.erp_validate_operational_date(p_company_id,lower(p_module),v_date);
  end loop;
end;
$$;

create or replace function public.erp_v2300_pay_cloud_workflow_invoice_batch(
  p_company_id uuid,p_invoice_id uuid,p_module text,p_payments jsonb
) returns jsonb
language plpgsql security definer set search_path=public as $$
begin
  if lower(p_module) not in ('sales','purchases') then raise exception 'invalid_workflow_module'; end if;
  perform public.erp_v2300_validate_payment_dates(p_company_id,lower(p_module),p_payments);
  return public.erp_v762_apply_workflow_payment(p_company_id,p_invoice_id,lower(p_module),p_payments);
end;
$$;

create or replace function public.erp_v2300_record_maintenance_payment_batch(
  p_company_id uuid,p_order_id uuid,p_payments jsonb
) returns jsonb
language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_v2300_validate_payment_dates(p_company_id,'maintenance',p_payments);
  return public.erp_record_cloud_maintenance_payment_batch(p_company_id,p_order_id,p_payments);
end;
$$;

revoke all on function public.erp_v2300_validate_payment_dates(uuid,text,jsonb) from public,anon;
revoke all on function public.erp_v2300_pay_cloud_workflow_invoice_batch(uuid,uuid,text,jsonb) from public,anon;
revoke all on function public.erp_v2300_record_maintenance_payment_batch(uuid,uuid,jsonb) from public,anon;
grant execute on function public.erp_v2300_validate_payment_dates(uuid,text,jsonb) to authenticated,service_role;
grant execute on function public.erp_v2300_pay_cloud_workflow_invoice_batch(uuid,uuid,text,jsonb) to authenticated,service_role;
grant execute on function public.erp_v2300_record_maintenance_payment_batch(uuid,uuid,jsonb) to authenticated,service_role;

create or replace function public.erp_v2300_transfer_cloud_cash(
  p_company_id uuid,
  p_from_cash_account_id text,
  p_to_cash_account_id text,
  p_source_amount numeric,
  p_target_amount numeric,
  p_exchange_rate numeric,
  p_transfer_date timestamptz,
  p_notes text default null
) returns jsonb
language plpgsql security definer set search_path=public as $$
begin
  if p_transfer_date is null then raise exception 'transfer_date_required'; end if;
  perform public.erp_validate_operational_date(p_company_id,'accounting',p_transfer_date);
  return public.erp_transfer_cloud_cash_v5(
    p_company_id,p_from_cash_account_id,p_to_cash_account_id,p_source_amount,
    p_target_amount,p_exchange_rate,p_transfer_date,p_notes
  );
end;
$$;

revoke all on function public.erp_v2300_transfer_cloud_cash(uuid,text,text,numeric,numeric,numeric,timestamptz,text) from public,anon;
grant execute on function public.erp_v2300_transfer_cloud_cash(uuid,text,text,numeric,numeric,numeric,timestamptz,text) to authenticated,service_role;

-- ---------------------------------------------------------------------------
-- Operational-dated warehouse transfers and definition-driven scrap posting.
-- ---------------------------------------------------------------------------
create or replace function public.erp_account_scrap_inventory_movement()
returns trigger language plpgsql security definer set search_path=public as $$
declare
  v_wh public.erp_warehouses%rowtype;
  v_type text;
  v_product_id text;
  v_qty numeric;
  v_cost numeric;
  v_amount numeric;
  v_currency text;
  v_definition jsonb;
  v_inventory_account text;
  v_expense_account text;
  v_direction text;
begin
  if new.is_deleted then return new; end if;
  v_type:=lower(coalesce(new.data->>'movementType',''));
  if v_type not in ('transfer_in','transfer_out') then return new; end if;

  select * into v_wh from public.erp_warehouses
   where company_id=new.company_id and id=new.data->>'warehouseId' and not is_deleted;
  if not found or lower(coalesce(v_wh.data->>'warehouseType',v_wh.data->>'type','normal'))
      not in ('scrap_consumption','scrap','damage') then
    return new;
  end if;

  v_product_id:=nullif(new.data->>'productId','');
  if v_product_id is null then raise exception 'scrap_product_required'; end if;
  v_definition:=public.erp_v764_definition_data(new.company_id,'product',v_product_id);
  v_currency:=public.erp_v764_definition_currency(new.company_id,'product',v_product_id);
  v_inventory_account:=nullif(coalesce(v_definition->>'inventoryAssetAccountId',
    v_definition->>'inventory_asset_account_id'),'');
  perform public.erp_phase2_account_guard(new.company_id,v_inventory_account,'asset',v_currency);
  v_expense_account:=public.erp_v764_scrap_expense_account(
    new.company_id,new.data->>'warehouseId',v_currency);

  v_qty:=abs(public.erp_try_numeric(new.data->>'quantity',0));
  v_cost:=abs(public.erp_try_numeric(new.data->>'unitCost',0));
  v_amount:=round(v_qty*v_cost,2);
  if v_amount<=0 then return new; end if;
  v_direction:=case when v_type='transfer_in' then 'in' else 'out' end;

  perform public.erp_post_scrap_warehouse_value(
    new.company_id,new.id,new.data->>'warehouseId',v_direction,
    v_amount,v_currency,v_inventory_account,v_expense_account,
    coalesce(new.data->>'notes','حركة مخزن توالف واستهلاك')
  );
  return new;
end;
$$;

drop trigger if exists erp_inventory_scrap_accounting on public.erp_inventory_movements;
create trigger erp_inventory_scrap_accounting
after insert on public.erp_inventory_movements for each row
execute function public.erp_account_scrap_inventory_movement();

create or replace function public.erp_v2300_transfer_inventory_stock_batch(
  p_company_id uuid,
  p_lines jsonb,
  p_notes text default null,
  p_effective_at timestamptz default now()
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_result jsonb;
  v_transfer_id text;
  v_effective_at timestamptz:=coalesce(p_effective_at,now());
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  perform public.erp_validate_operational_date(p_company_id,'inventory',v_effective_at);

  v_result:=public.erp_transfer_inventory_stock_batch(p_company_id,p_lines,p_notes);
  v_transfer_id:=nullif(v_result->>'transferId','');
  if v_transfer_id is null then raise exception 'inventory_transfer_id_missing'; end if;

  update public.erp_warehouse_transfers
  set data=data||jsonb_build_object(
        'transferDate',v_effective_at,'effectiveAt',v_effective_at,'updatedAt',now()),
      updated_at=now(),updated_by=auth.uid()
  where company_id=p_company_id and id=v_transfer_id and not is_deleted;

  update public.erp_inventory_movements
  set data=data||jsonb_build_object(
        'movementDate',v_effective_at,'effectiveAt',v_effective_at),
      updated_at=now(),updated_by=auth.uid()
  where company_id=p_company_id and not is_deleted
    and data->>'referenceType'='warehouse_transfer'
    and data->>'referenceId'=v_transfer_id;

  update public.erp_journal_entries j
  set data=j.data||jsonb_build_object(
        'entryDate',v_effective_at,'effectiveAt',v_effective_at),
      updated_at=now(),updated_by=auth.uid()
  where j.company_id=p_company_id and not j.is_deleted
    and j.data->>'referenceType'='scrap_warehouse'
    and j.data->>'referenceId' in (
      select m.id from public.erp_inventory_movements m
      where m.company_id=p_company_id and not m.is_deleted
        and m.data->>'referenceType'='warehouse_transfer'
        and m.data->>'referenceId'=v_transfer_id
    );

  return v_result||jsonb_build_object('transferDate',v_effective_at,'effectiveAt',v_effective_at);
end;
$$;

create or replace function public.erp_v2300_create_car_warehouse_transfer(
  p_company_id uuid,
  p_car_id text,
  p_to_warehouse_id text,
  p_user_name text,
  p_notes text default null,
  p_effective_at timestamptz default now()
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_transfer_id text;
  v_effective_at timestamptz:=coalesce(p_effective_at,now());
  v_row jsonb;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  perform public.erp_validate_operational_date(p_company_id,'inventory',v_effective_at);
  v_transfer_id:=public.erp_create_car_warehouse_transfer(
    p_company_id,p_car_id,p_to_warehouse_id,p_user_name,p_notes);

  update public.erp_car_warehouse_transfers
  set data=data||jsonb_build_object(
        'transferDate',v_effective_at,'effectiveAt',v_effective_at,'updatedAt',now()),
      updated_at=now(),updated_by=auth.uid()
  where company_id=p_company_id and id=v_transfer_id and not is_deleted;

  select data||jsonb_build_object('id',id) into v_row
  from public.erp_car_warehouse_transfers
  where company_id=p_company_id and id=v_transfer_id and not is_deleted;
  return coalesce(v_row,jsonb_build_object('id',v_transfer_id,'transferDate',v_effective_at));
end;
$$;


create or replace function public.erp_v2300_create_car_warehouse_transfer_batch(
  p_company_id uuid,
  p_lines jsonb,
  p_to_warehouse_id uuid,
  p_user_name text,
  p_notes text default null,
  p_effective_at timestamptz default now()
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_result jsonb;
  v_transfer_id text;
  v_effective_at timestamptz:=coalesce(p_effective_at,now());
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  perform public.erp_validate_operational_date(p_company_id,'inventory',v_effective_at);
  v_result:=public.erp_create_car_warehouse_transfer_batch(
    p_company_id,p_lines,p_to_warehouse_id,p_user_name,p_notes);

  for v_transfer_id in
    select jsonb_array_elements_text(coalesce(v_result->'transferIds','[]'::jsonb))
  loop
    update public.erp_car_warehouse_transfers
    set data=data||jsonb_build_object(
          'transferDate',v_effective_at,'effectiveAt',v_effective_at,'updatedAt',now()),
        updated_at=now(),updated_by=auth.uid()
    where company_id=p_company_id and id=v_transfer_id and not is_deleted;
  end loop;

  return v_result||jsonb_build_object(
    'transferDate',v_effective_at,'effectiveAt',v_effective_at,'createdAt',v_effective_at);
end;
$$;

revoke all on function public.erp_v2300_create_car_warehouse_transfer_batch(uuid,jsonb,uuid,text,text,timestamptz) from public,anon;
grant execute on function public.erp_v2300_create_car_warehouse_transfer_batch(uuid,jsonb,uuid,text,text,timestamptz) to authenticated,service_role;

revoke all on function public.erp_v2300_transfer_inventory_stock_batch(uuid,jsonb,text,timestamptz) from public,anon;
revoke all on function public.erp_v2300_create_car_warehouse_transfer(uuid,text,text,text,text,timestamptz) from public,anon;
grant execute on function public.erp_v2300_transfer_inventory_stock_batch(uuid,jsonb,text,timestamptz) to authenticated,service_role;
grant execute on function public.erp_v2300_create_car_warehouse_transfer(uuid,text,text,text,text,timestamptz) to authenticated,service_role;

revoke all on function public.erp_v2300_create_purchase_order(uuid,jsonb) from public,anon;
revoke all on function public.erp_v2300_create_sales_order(uuid,jsonb) from public,anon;
revoke all on function public.erp_v2300_update_purchase_order(uuid,jsonb) from public,anon;
revoke all on function public.erp_v2300_update_sales_order(uuid,jsonb) from public,anon;
revoke all on function public.erp_v2300_record_app_audit(uuid,text,text,text,text,text,text,text,text,text,jsonb,text) from public,anon;
revoke all on function public.erp_v2300_audit_feed(uuid,integer,text,text) from public,anon;
grant execute on function public.erp_v2300_create_purchase_order(uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_v2300_create_sales_order(uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_v2300_update_purchase_order(uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_v2300_update_sales_order(uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_v2300_record_app_audit(uuid,text,text,text,text,text,text,text,text,text,jsonb,text) to authenticated,service_role;
grant execute on function public.erp_v2300_audit_feed(uuid,integer,text,text) to authenticated,service_role;

-- Reinstall audit triggers so tables added by later migrations are covered too.
select public.erp_install_audit_triggers();
notify pgrst,'reload schema';
commit;
