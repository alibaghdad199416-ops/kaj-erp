-- R56: canonical Opportunity -> Maintenance linkage, vehicle service card,
-- and permission-aware Business Partner 360 read models.
begin;

alter table public.erp_maintenance_orders
  add column if not exists opportunity_id text,
  add column if not exists opportunity_number text;

create unique index if not exists uq_r56_maintenance_active_opportunity
  on public.erp_maintenance_orders(company_id,opportunity_id)
  where opportunity_id is not null and not is_deleted
    and cancelled_at is null and workflow_stage<>'cancelled';

create index if not exists idx_r56_maintenance_vehicle_timeline
  on public.erp_maintenance_orders(company_id,source_car_id,maintenance_date desc,id)
  where not is_deleted;

create index if not exists idx_r56_maintenance_customer_timeline
  on public.erp_maintenance_orders(company_id,customer_id,maintenance_date desc,id)
  where not is_deleted;

create or replace function public.erp_r56_validate_maintenance_relationship()
returns trigger language plpgsql security definer set search_path=public as $$
declare
  v_slug text;
  v_opportunity jsonb;
  v_car_id text;
  v_customer_id text;
begin
  if tg_op='UPDATE' and
     (new.source_car_id is distinct from old.source_car_id or new.car_id is distinct from old.car_id) then
    raise exception 'maintenance_vehicle_immutable' using errcode='22023';
  end if;

  if nullif(btrim(coalesce(new.opportunity_id,'')),'') is null then return new; end if;
  select c.slug into v_slug from public.companies c
  where c.id=new.company_id and c.is_active;
  if v_slug is null then
    raise exception 'maintenance_company_not_found' using errcode='23503';
  end if;
  select r.payload into v_opportunity from public.erp_records r
  where r.company_id=v_slug and r.entity_type='opportunities'
    and r.record_id=new.opportunity_id and not r.is_deleted and r.deleted_at is null;
  if v_opportunity is null then
    raise exception 'maintenance_opportunity_not_found' using errcode='23503';
  end if;
  v_car_id:=nullif(btrim(coalesce(v_opportunity->>'carId','')),'');
  v_customer_id:=nullif(btrim(coalesce(v_opportunity->>'customerId','')),'');
  if v_car_id is null or v_car_id<>new.source_car_id then
    raise exception 'maintenance_opportunity_vehicle_mismatch' using errcode='23514';
  end if;
  if v_customer_id is not null and v_customer_id<>coalesce(new.customer_id::text,'') then
    raise exception 'maintenance_opportunity_customer_mismatch' using errcode='23514';
  end if;
  new.opportunity_number:=coalesce(nullif(v_opportunity->>'opportunityNumber',''),new.opportunity_id);
  return new;
end $$;

drop trigger if exists trg_r56_validate_maintenance_relationship on public.erp_maintenance_orders;
create trigger trg_r56_validate_maintenance_relationship
before insert or update of opportunity_id,source_car_id,car_id,customer_id
on public.erp_maintenance_orders for each row
execute function public.erp_r56_validate_maintenance_relationship();

revoke all on function public.erp_r56_validate_maintenance_relationship() from public,anon,authenticated;
grant execute on function public.erp_r56_validate_maintenance_relationship() to service_role;

create or replace function public.erp_r56_find_maintenance_by_opportunity(
  p_company_id uuid,p_opportunity_id text
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_result jsonb;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'maintenance.view') then
    raise exception 'permission_denied:maintenance.view' using errcode='42501';
  end if;
  select public.erp_r9_filter_result_json(p_company_id,'maintenance',
    to_jsonb(x)||jsonb_build_object('updatedAt',o.updated_at,'opportunityId',o.opportunity_id,
      'opportunityNumber',o.opportunity_number),'maintenance.view')
  into v_result
  from public.erp_list_cloud_maintenance_orders(p_company_id) x
  join public.erp_maintenance_orders o on o.company_id=p_company_id and o.id=x.id
  where o.opportunity_id=p_opportunity_id and not o.is_deleted
    and o.cancelled_at is null and o.workflow_stage<>'cancelled'
  order by o.maintenance_date desc limit 1;
  return v_result;
end $$;

create or replace function public.erp_r56_create_cloud_maintenance_order(
  p_company_id uuid,p_car_id text,p_warehouse_id text,p_pricing_type text,
  p_labor_cost numeric,p_sale_price numeric,p_currency_code text,p_exchange_rate numeric,
  p_notes text,p_parts jsonb,p_opportunity_id text default null,
  p_maintenance_expense_account_id text default null,p_effective_at timestamptz default now()
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_existing uuid; v_id uuid;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'maintenance.create') then
    raise exception 'permission_denied:maintenance.create' using errcode='42501';
  end if;
  if nullif(btrim(coalesce(p_opportunity_id,'')),'') is not null then
    select id into v_existing from public.erp_maintenance_orders
    where company_id=p_company_id and opportunity_id=p_opportunity_id
      and not is_deleted and cancelled_at is null and workflow_stage<>'cancelled'
    for update;
    if v_existing is not null then return v_existing; end if;
  end if;
  v_id:=public.erp_r39_create_cloud_maintenance_order(
    p_company_id,p_car_id,p_warehouse_id,p_pricing_type,p_labor_cost,p_sale_price,
    p_currency_code,p_exchange_rate,p_notes,p_parts,p_maintenance_expense_account_id,p_effective_at);
  update public.erp_maintenance_orders set opportunity_id=nullif(btrim(p_opportunity_id),''),updated_at=now()
  where company_id=p_company_id and id=v_id;
  return v_id;
exception when unique_violation then
  select id into v_existing from public.erp_maintenance_orders
  where company_id=p_company_id and opportunity_id=p_opportunity_id
    and not is_deleted and cancelled_at is null and workflow_stage<>'cancelled';
  if v_existing is not null then return v_existing; end if;
  raise;
end $$;

create or replace function public.erp_r56_vehicle_service_card(p_company_id uuid,p_car_id text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_car jsonb; v_history jsonb;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and (not public.erp_cloud_user_has_permission(p_company_id,'cars.view')
       or not public.erp_cloud_user_has_permission(p_company_id,'maintenance.view')) then
    raise exception 'permission_denied:vehicle_service_card' using errcode='42501';
  end if;
  select jsonb_build_object('id',c.id,'carNumber',c.data->>'carNumber','brand',c.data->>'brand',
    'model',c.data->>'model','year',c.data->>'year','chassis',coalesce(c.data->>'chassis',c.data->>'vin'),
    'plateNumber',c.data->>'plateNumber','color',c.data->>'color') into v_car
  from public.erp_cars c where c.company_id=p_company_id and c.id=p_car_id and not c.is_deleted;
  if v_car is null then raise exception 'vehicle_not_found' using errcode='P0002'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',o.id,'orderNumber',o.order_number,'maintenanceDate',o.maintenance_date,
    'workflowStage',o.workflow_stage,'status',o.status,'pricingType',o.pricing_type,
    'customerId',o.customer_id,'customerName',o.customer_name,'currencyCode',o.currency_code,
    'salePrice',o.sale_price,'paidAmount',o.paid_amount,'invoiceNumber',o.invoice_number,
    'stockIssueNumber',o.stock_issue_number,'notes',o.notes,'cancelReason',o.cancel_reason,
    'opportunityId',o.opportunity_id,'opportunityNumber',o.opportunity_number,
    'items',coalesce((select jsonb_agg(jsonb_build_object('name',p.product_name,
      'quantity',p.quantity,'unitPrice',p.unit_price,'lineType',p.line_type) order by p.created_at)
      from public.erp_maintenance_parts p where p.company_id=o.company_id
      and p.maintenance_order_id=o.id and not p.is_deleted),'[]'::jsonb)
  ) order by o.maintenance_date desc,o.id),'[]'::jsonb) into v_history
  from public.erp_maintenance_orders o where o.company_id=p_company_id
    and o.source_car_id=p_car_id and not o.is_deleted;
  return jsonb_build_object('vehicle',v_car,'maintenanceHistory',v_history);
end $$;

create or replace function public.erp_r56_business_partner_360(
  p_company_id uuid,p_partner_kind text,p_partner_id text
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_kind text:=lower(btrim(coalesce(p_partner_kind,''))); v_base jsonb; v_slug text;
  v_crm jsonb:='[]'::jsonb; v_maintenance jsonb:='[]'::jsonb; v_chain jsonb:='[]'::jsonb;
begin
  perform public.erp_active_company_context(p_company_id);
  if v_kind not in ('customer','supplier') then raise exception 'unsupported_partner_kind' using errcode='22023'; end if;
  v_base:=public.erp_r49_business_partner_card_summary(p_company_id,v_kind,p_partner_id);
  select slug into v_slug from public.companies where id=p_company_id and is_active;
  if v_kind='customer' then
    if public.is_company_admin(p_company_id) or public.erp_cloud_user_has_permission(p_company_id,'customer_service.view') then
      select coalesce(jsonb_agg(r.payload order by r.updated_at desc),'[]'::jsonb) into v_crm
      from public.erp_records r where r.company_id=v_slug and r.entity_type='opportunities'
        and not r.is_deleted and r.deleted_at is null and r.payload->>'customerId'=p_partner_id;
    end if;
    if public.is_company_admin(p_company_id) or public.erp_cloud_user_has_permission(p_company_id,'maintenance.view') then
      select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'orderNumber',o.order_number,
        'carId',o.source_car_id,'carName',o.car_name,'maintenanceDate',o.maintenance_date,
        'workflowStage',o.workflow_stage,'currencyCode',o.currency_code,'salePrice',o.sale_price,
        'paidAmount',o.paid_amount) order by o.maintenance_date desc),'[]'::jsonb) into v_maintenance
      from public.erp_maintenance_orders o where o.company_id=p_company_id
        and o.customer_id::text=p_partner_id and not o.is_deleted;
    end if;
    if public.is_company_admin(p_company_id) or public.erp_cloud_user_has_permission(p_company_id,'sales.view') then
      select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'orderNumber',o.order_number,
        'status',o.status,'currency',o.currency,'total',o.total,'opportunityId',o.opportunity_id)
        order by o.created_at desc),'[]'::jsonb) into v_chain
      from public.erp_sales_orders_cloud o where o.company_id=p_company_id
        and o.customer_id=p_partner_id and not o.is_deleted;
    end if;
  else
    if public.is_company_admin(p_company_id) or public.erp_cloud_user_has_permission(p_company_id,'purchases.view') then
      select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'orderNumber',o.order_number,
        'status',o.status,'currency',o.currency,'total',o.total) order by o.created_at desc),'[]'::jsonb) into v_chain
      from public.erp_purchase_orders_cloud o where o.company_id=p_company_id
        and o.supplier_id=p_partner_id and not o.is_deleted;
    end if;
  end if;
  return coalesce(v_base,'{}'::jsonb)||jsonb_build_object('crmOpportunities',v_crm,
    'commercialChain',v_chain,'maintenanceHistory',v_maintenance,'profileVersion','R56');
end $$;

revoke all on function public.erp_r56_find_maintenance_by_opportunity(uuid,text) from public,anon;
revoke all on function public.erp_r56_create_cloud_maintenance_order(uuid,text,text,text,numeric,numeric,text,numeric,text,jsonb,text,text,timestamptz) from public,anon;
revoke all on function public.erp_r56_vehicle_service_card(uuid,text) from public,anon;
revoke all on function public.erp_r56_business_partner_360(uuid,text,text) from public,anon;
grant execute on function public.erp_r56_find_maintenance_by_opportunity(uuid,text) to authenticated,service_role;
grant execute on function public.erp_r56_create_cloud_maintenance_order(uuid,text,text,text,numeric,numeric,text,numeric,text,jsonb,text,text,timestamptz) to authenticated,service_role;
grant execute on function public.erp_r56_vehicle_service_card(uuid,text) to authenticated,service_role;
grant execute on function public.erp_r56_business_partner_360(uuid,text,text) to authenticated,service_role;

commit;
