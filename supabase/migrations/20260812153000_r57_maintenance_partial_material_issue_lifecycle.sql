begin;

create table public.erp_maintenance_material_issues(
  id uuid primary key,
  company_id uuid not null,
  maintenance_order_id uuid not null references public.erp_maintenance_orders(id),
  status text not null default 'executed' check(status in ('executed','reversed')),
  effective_at timestamptz not null,
  total_cost numeric(20,6) not null default 0,
  created_at timestamptz not null default now(),
  created_by uuid,
  reversed_at timestamptz,
  reversed_by uuid,
  reversal_reason text,
  unique(company_id,id)
);
create index erp_maintenance_material_issues_order_idx
  on public.erp_maintenance_material_issues(company_id,maintenance_order_id,status,created_at);
alter table public.erp_maintenance_material_issues enable row level security;

create table public.erp_maintenance_material_issue_lines(
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  issue_id uuid not null references public.erp_maintenance_material_issues(id),
  maintenance_order_id uuid not null references public.erp_maintenance_orders(id),
  maintenance_part_id uuid not null references public.erp_maintenance_parts(id),
  product_id text not null,
  warehouse_id text not null,
  quantity numeric(20,4) not null check(quantity>0),
  actual_cost numeric(20,6) not null default 0,
  created_at timestamptz not null default now(),
  unique(company_id,issue_id,maintenance_part_id,warehouse_id)
);
create index erp_maintenance_material_issue_lines_order_idx
  on public.erp_maintenance_material_issue_lines(company_id,maintenance_order_id,maintenance_part_id);
alter table public.erp_maintenance_material_issue_lines enable row level security;

create or replace function public.erp_r57_refresh_maintenance_issue_costs(
  p_company_id uuid,p_order_id uuid
) returns numeric language plpgsql security definer set search_path=public as $$
declare p record; v_line_cost numeric; v_total numeric:=0;
begin
  for p in select mp.id,mp.quantity from public.erp_maintenance_parts mp
    where mp.company_id=p_company_id and mp.maintenance_order_id=p_order_id
      and not mp.is_deleted and mp.line_type<>'service' for update
  loop
    select coalesce(sum(fc.total_cost),0) into v_line_cost
    from public.erp_maintenance_material_issue_lines il
    join public.erp_maintenance_material_issues i on i.company_id=il.company_id and i.id=il.issue_id and i.status='executed'
    join public.erp_inventory_fifo_consumptions fc on fc.company_id=il.company_id
      and fc.delivery_id=il.issue_id and fc.sales_order_id=il.maintenance_order_id
      and fc.item_id=il.product_id and fc.warehouse_id=il.warehouse_id and fc.status='active'
    where il.company_id=p_company_id and il.maintenance_order_id=p_order_id and il.maintenance_part_id=p.id;
    update public.erp_maintenance_parts set total_cost=round(v_line_cost,2),
      unit_cost=case when p.quantity>0 then round(v_line_cost/p.quantity,2) else 0 end,updated_at=now()
    where id=p.id;
    v_total:=v_total+v_line_cost;
  end loop;
  update public.erp_maintenance_orders set parts_cost=round(v_total,2),
    total_cost=round(labor_cost+v_total,2),profit=round(sale_price-(labor_cost+v_total),2),updated_at=now()
  where company_id=p_company_id and id=p_order_id;
  return v_total;
end $$;

create or replace function public.erp_r57_execute_maintenance_material_issue(
  p_company_id uuid,p_order_id uuid,p_issue_id uuid,p_part_id uuid,
  p_warehouse_id text,p_quantity numeric,p_effective_at timestamptz default now()
) returns jsonb language plpgsql security definer set search_path=public as $$
declare o public.erp_maintenance_orders%rowtype; mp public.erp_maintenance_parts%rowtype;
  ws public.erp_warehouse_stock%rowtype; w record; l record; v_product text;
  v_issued numeric; v_remaining numeric; v_needed numeric; v_take numeric;
  v_cost numeric:=0; v_existing public.erp_maintenance_material_issues%rowtype;
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['maintenance.approve','maintenance.update']);
  if p_issue_id is null then raise exception 'maintenance_issue_id_required'; end if;
  if coalesce(p_quantity,0)<=0 then raise exception 'maintenance_issue_quantity_must_be_positive'; end if;
  if nullif(btrim(coalesce(p_warehouse_id,'')),'') is null then raise exception 'maintenance_issue_warehouse_required'; end if;

  select * into v_existing from public.erp_maintenance_material_issues
   where company_id=p_company_id and id=p_issue_id;
  if found then
    select * into l from public.erp_maintenance_material_issue_lines
     where company_id=p_company_id and issue_id=p_issue_id;
    if v_existing.status='executed' and l.maintenance_order_id=p_order_id
       and l.maintenance_part_id=p_part_id and l.warehouse_id=p_warehouse_id
       and l.quantity=p_quantity then
      return jsonb_build_object('issueId',p_issue_id,'idempotent',true,'status','executed');
    end if;
    raise exception 'maintenance_issue_id_conflict';
  end if;

  select * into o from public.erp_maintenance_orders
   where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found then raise exception 'maintenance_order_not_found'; end if;
  if o.workflow_stage<>'stock_issue_draft' then raise exception 'maintenance_issue_stage_invalid:%',o.workflow_stage; end if;
  select * into mp from public.erp_maintenance_parts
   where company_id=p_company_id and id=p_part_id and maintenance_order_id=p_order_id
     and not is_deleted and line_type<>'service' for update;
  if not found then raise exception 'maintenance_part_not_found'; end if;
  v_product:=coalesce(mp.source_product_id,mp.product_id::text);

  select coalesce(sum(il.quantity),0) into v_issued
  from public.erp_maintenance_material_issue_lines il join public.erp_maintenance_material_issues i
    on i.company_id=il.company_id and i.id=il.issue_id and i.status='executed'
  where il.company_id=p_company_id and il.maintenance_part_id=p_part_id;
  v_remaining:=mp.quantity-v_issued;
  if p_quantity>v_remaining then raise exception 'maintenance_issue_exceeds_remaining:%',v_remaining; end if;

  select * into w from public.erp_warehouses
   where company_id=p_company_id and id=p_warehouse_id and not is_deleted for update;
  if not found then raise exception 'maintenance_issue_warehouse_invalid'; end if;
  if lower(coalesce(w.data->>'isActive',w.data->>'active','true')) in ('false','0','no') then
    raise exception 'maintenance_issue_warehouse_inactive';
  end if;
  select * into ws from public.erp_warehouse_stock where company_id=p_company_id and not is_deleted
    and coalesce(data->>'warehouseId',data->>'warehouse_id')=p_warehouse_id
    and coalesce(data->>'productId',data->>'product_id')=v_product for update;
  if not found or public.erp_try_numeric(ws.data->>'quantity',0)-public.erp_try_numeric(ws.data->>'reservedQuantity',0)<p_quantity then
    raise exception 'maintenance_insufficient_stock:%',mp.product_name;
  end if;

  insert into public.erp_maintenance_material_issues(id,company_id,maintenance_order_id,effective_at,created_by)
  values(p_issue_id,p_company_id,p_order_id,coalesce(p_effective_at,now()),auth.uid());
  insert into public.erp_maintenance_material_issue_lines(company_id,issue_id,maintenance_order_id,
    maintenance_part_id,product_id,warehouse_id,quantity)
  values(p_company_id,p_issue_id,p_order_id,p_part_id,v_product,p_warehouse_id,p_quantity);

  update public.erp_warehouse_stock set data=data||jsonb_build_object(
    'quantity',public.erp_try_numeric(data->>'quantity',0)-p_quantity,'updatedAt',now()),
    updated_at=now(),updated_by=auth.uid() where id=ws.id;

  v_needed:=p_quantity;
  for l in select * from public.erp_inventory_cost_layers q
    where q.company_id=p_company_id and q.item_type='product' and q.item_id=v_product
      and q.warehouse_id=p_warehouse_id and q.status in ('active','consumed')
      and q.remaining_quantity>0 and q.effective_at<=coalesce(p_effective_at,now())
    order by q.effective_at,q.created_at,q.id for update
  loop
    exit when v_needed<=0; v_take:=least(v_needed,l.remaining_quantity);
    update public.erp_inventory_cost_layers set remaining_quantity=remaining_quantity-v_take,
      status=case when remaining_quantity-v_take<=0 then 'consumed' else 'active' end,
      updated_at=now(),updated_by=auth.uid() where id=l.id;
    insert into public.erp_inventory_fifo_consumptions(company_id,delivery_id,sales_order_id,layer_id,
      item_type,item_id,warehouse_id,quantity,unit_cost,effective_at,status)
    values(p_company_id,p_issue_id,p_order_id,l.id,'product',v_product,p_warehouse_id,v_take,l.unit_cost,
      coalesce(p_effective_at,now()),'active');
    v_cost:=v_cost+v_take*l.unit_cost; v_needed:=v_needed-v_take;
  end loop;
  if v_needed>0 then raise exception 'insufficient_maintenance_cost_layers:%',v_product; end if;

  update public.erp_maintenance_material_issue_lines set actual_cost=v_cost
   where company_id=p_company_id and issue_id=p_issue_id;
  update public.erp_maintenance_material_issues set total_cost=v_cost where company_id=p_company_id and id=p_issue_id;
  perform public.erp_inventory_insert_movement(p_company_id,v_product,p_warehouse_id,'maintenance_out',-p_quantity,
    v_cost/p_quantity,'maintenance_issue',p_issue_id::text,'Maintenance material issue '||o.order_number);
  perform public.erp_inventory_refresh_product(p_company_id,v_product);
  perform public.erp_r57_refresh_maintenance_issue_costs(p_company_id,p_order_id);

  if not exists(
    select 1 from public.erp_maintenance_parts x where x.company_id=p_company_id
      and x.maintenance_order_id=p_order_id and not x.is_deleted and x.line_type<>'service'
      and x.quantity>(select coalesce(sum(il.quantity),0) from public.erp_maintenance_material_issue_lines il
        join public.erp_maintenance_material_issues i on i.company_id=il.company_id and i.id=il.issue_id and i.status='executed'
        where il.company_id=p_company_id and il.maintenance_part_id=x.id)
  ) then
    update public.erp_maintenance_orders set workflow_stage='stock_issue_approved',
      stock_issue_number=case when stock_issue_number is null or stock_issue_number='PENDING' then
        public.erp_next_document_number(p_company_id,'maintenance_stock_issue','MSI',o.maintenance_date)
        else stock_issue_number end,updated_at=now() where id=p_order_id;
  end if;
  return jsonb_build_object('issueId',p_issue_id,'idempotent',false,'quantity',p_quantity,
    'actualCost',round(v_cost,6),'remaining',v_remaining-p_quantity);
end $$;

create or replace function public.erp_r57_reverse_maintenance_material_issue(
  p_company_id uuid,p_issue_id uuid,p_reason text default null
) returns void language plpgsql security definer set search_path=public as $$
declare i public.erp_maintenance_material_issues%rowtype; il record; fc record; ws public.erp_warehouse_stock%rowtype;
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['maintenance.approve','maintenance.update']);
  select * into i from public.erp_maintenance_material_issues where company_id=p_company_id and id=p_issue_id for update;
  if not found then raise exception 'maintenance_issue_not_found'; end if;
  if i.status='reversed' then return; end if;
  if exists(select 1 from public.erp_maintenance_orders where company_id=p_company_id and id=i.maintenance_order_id
    and workflow_stage in ('invoice_approved','paid','completed')) then raise exception 'maintenance_issue_has_later_financial_stage'; end if;
  for fc in select * from public.erp_inventory_fifo_consumptions where company_id=p_company_id
    and delivery_id=p_issue_id and status='active' for update
  loop
    update public.erp_inventory_cost_layers set remaining_quantity=least(original_quantity,remaining_quantity+fc.quantity),
      status='active',updated_at=now(),updated_by=auth.uid() where id=fc.layer_id;
  end loop;
  update public.erp_inventory_fifo_consumptions set status='reversed',reversed_at=now()
   where company_id=p_company_id and delivery_id=p_issue_id and status='active';
  for il in select * from public.erp_maintenance_material_issue_lines where company_id=p_company_id and issue_id=p_issue_id
  loop
    ws:=public.erp_inventory_ensure_stock(p_company_id,il.warehouse_id,il.product_id);
    update public.erp_warehouse_stock set data=data||jsonb_build_object(
      'quantity',public.erp_try_numeric(data->>'quantity',0)+il.quantity,'updatedAt',now()),
      updated_at=now(),updated_by=auth.uid() where id=ws.id;
    perform public.erp_inventory_insert_movement(p_company_id,il.product_id,il.warehouse_id,
      'maintenance_return',il.quantity,case when il.quantity>0 then il.actual_cost/il.quantity else 0 end,
      'maintenance_issue_reversal',p_issue_id::text,coalesce(nullif(btrim(p_reason),''),'Maintenance issue reversal'));
    perform public.erp_inventory_refresh_product(p_company_id,il.product_id);
  end loop;
  update public.erp_maintenance_material_issues set status='reversed',reversed_at=now(),
    reversed_by=auth.uid(),reversal_reason=nullif(btrim(coalesce(p_reason,'')),'') where id=p_issue_id;
  update public.erp_maintenance_orders set workflow_stage='stock_issue_draft',updated_at=now()
   where company_id=p_company_id and id=i.maintenance_order_id and workflow_stage='stock_issue_approved';
  perform public.erp_r57_refresh_maintenance_issue_costs(p_company_id,i.maintenance_order_id);
end $$;

create or replace function public.erp_r57_maintenance_material_issue_state(
  p_company_id uuid,p_order_id uuid
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_lines jsonb; v_warehouses jsonb; v_events jsonb; v_cost numeric;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id) and not public.erp_cloud_user_has_permission(p_company_id,'maintenance.view') then
    raise exception 'permission_denied:maintenance.view' using errcode='42501'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('lineId',mp.id,'productId',coalesce(mp.source_product_id,mp.product_id::text),
    'description',mp.product_name,'requestedQuantity',mp.quantity,'issuedQuantity',coalesce(q.issued,0),
    'remainingQuantity',greatest(mp.quantity-coalesce(q.issued,0),0),'issuedActualCost',coalesce(q.cost,0)) order by mp.id),'[]')
  into v_lines from public.erp_maintenance_parts mp left join lateral(
    select sum(il.quantity) issued,sum(il.actual_cost) cost from public.erp_maintenance_material_issue_lines il
    join public.erp_maintenance_material_issues i on i.company_id=il.company_id and i.id=il.issue_id and i.status='executed'
    where il.company_id=mp.company_id and il.maintenance_part_id=mp.id)q on true
  where mp.company_id=p_company_id and mp.maintenance_order_id=p_order_id and not mp.is_deleted and mp.line_type<>'service';
  select coalesce(jsonb_agg(jsonb_build_object('warehouseId',q.warehouse_id,'warehouseName',q.warehouse_name,
    'issuedQuantity',q.quantity,'issuedActualCost',q.cost) order by q.warehouse_name),'[]') into v_warehouses from(
    select il.warehouse_id,coalesce(w.data->>'name',w.data->>'nameAr',w.data->>'nameEn',il.warehouse_id) warehouse_name,
      sum(il.quantity) quantity,sum(il.actual_cost) cost from public.erp_maintenance_material_issue_lines il
    join public.erp_maintenance_material_issues i on i.company_id=il.company_id and i.id=il.issue_id and i.status='executed'
    left join public.erp_warehouses w on w.company_id=il.company_id and w.id=il.warehouse_id and not w.is_deleted
    where il.company_id=p_company_id and il.maintenance_order_id=p_order_id group by 1,2)q;
  select coalesce(jsonb_agg(jsonb_build_object('issueId',i.id,'status',i.status,'effectiveAt',i.effective_at,
    'totalCost',i.total_cost,'lineId',il.maintenance_part_id,'productId',il.product_id,'warehouseId',il.warehouse_id,
    'warehouseName',coalesce(w.data->>'name',w.data->>'nameAr',w.data->>'nameEn',il.warehouse_id),'quantity',il.quantity)
    order by i.created_at),'[]') into v_events from public.erp_maintenance_material_issues i
    join public.erp_maintenance_material_issue_lines il on il.company_id=i.company_id and il.issue_id=i.id
    left join public.erp_warehouses w on w.company_id=il.company_id and w.id=il.warehouse_id and not w.is_deleted
    where i.company_id=p_company_id and i.maintenance_order_id=p_order_id;
  select coalesce(sum(total_cost),0) into v_cost from public.erp_maintenance_material_issues
   where company_id=p_company_id and maintenance_order_id=p_order_id and status='executed';
  return jsonb_build_object('issuedMaterialsActualCost',v_cost,'lines',v_lines,'warehouses',v_warehouses,'events',v_events);
end $$;

create or replace function public.erp_r57_maintenance_issue_warehouse_options(
  p_company_id uuid,p_part_id uuid
) returns table(warehouse_id text,warehouse_name text,available_quantity numeric)
language plpgsql stable security definer set search_path=public as $$
declare v_product text;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'maintenance.view') then
    raise exception 'permission_denied:maintenance.view' using errcode='42501'; end if;
  select coalesce(source_product_id,product_id::text) into v_product
    from public.erp_maintenance_parts where company_id=p_company_id and id=p_part_id and not is_deleted;
  if not found then raise exception 'maintenance_part_not_found'; end if;
  return query select w.id,
    coalesce(w.data->>'name',w.data->>'nameAr',w.data->>'nameEn',w.id),
    public.erp_try_numeric(s.data->>'quantity',0)-public.erp_try_numeric(s.data->>'reservedQuantity',0)
  from public.erp_warehouses w join public.erp_warehouse_stock s on s.company_id=w.company_id and not s.is_deleted
    and coalesce(s.data->>'warehouseId',s.data->>'warehouse_id')=w.id
    and coalesce(s.data->>'productId',s.data->>'product_id')=v_product
  where w.company_id=p_company_id and not w.is_deleted
    and lower(coalesce(w.data->>'isActive',w.data->>'active','true')) not in ('false','0','no')
  order by 2;
end $$;

-- Advancing from an issue draft may only close a material-free order. Real
-- material orders are advanced by execution of their final persisted issue.
create or replace function public.erp_advance_cloud_maintenance_workflow(
  p_company_id uuid,p_order_id uuid
) returns void language plpgsql security definer set search_path=public as $$
declare v_before text; v_after text; v_effective timestamptz;
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['maintenance.approve']);
  select workflow_stage,coalesce(maintenance_date,now()) into v_before,v_effective
    from public.erp_maintenance_orders where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found then raise exception 'maintenance_order_not_found'; end if;
  if v_before='stock_issue_draft' then
    if exists(select 1 from public.erp_maintenance_parts where company_id=p_company_id and maintenance_order_id=p_order_id
      and not is_deleted and line_type<>'service') then raise exception 'maintenance_material_issue_action_required'; end if;
    update public.erp_maintenance_orders set workflow_stage='stock_issue_approved',updated_at=now() where id=p_order_id;
    return;
  end if;
  perform public.erp_advance_cloud_maintenance_workflow_pre_r54_valuation(p_company_id,p_order_id);
  select workflow_stage into v_after from public.erp_maintenance_orders where company_id=p_company_id and id=p_order_id;
end $$;

-- Invoice posting consumes no stock. It posts from the FIFO rows already owned
-- by explicit issue events and only attaches the resulting journal identities.
create or replace function public.erp_v736_post_maintenance_invoice(
  p_company_id uuid,p_order_id uuid
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_order public.erp_maintenance_orders%rowtype; v_currency text;
  v_partner_account text; v_result jsonb; v_entry jsonb;
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['maintenance.approve']);
  select * into v_order from public.erp_maintenance_orders
   where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found then raise exception 'maintenance_order_not_found'; end if;
  if v_order.invoice_journal_entry_id is not null then
    return public.erp_v736_post_maintenance_invoice_pre_r49_identity(p_company_id,p_order_id); end if;
  if v_order.pricing_type='paid' then
    if v_order.customer_id is null then raise exception 'paid_maintenance_customer_required'; end if;
    v_currency:=upper(coalesce(v_order.currency_code,''));
    if v_currency not in ('USD','IQD') then raise exception 'maintenance_currency_invalid:%',v_currency; end if;
    perform public.erp_v764_assert_partner_dual_ledgers(p_company_id,v_order.customer_id::text,'customer');
    v_partner_account:=public.erp_workflow_partner_account(p_company_id,'customer',v_order.customer_id::text,v_currency);
    perform public.erp_phase2_account_guard(p_company_id,v_partner_account,'asset',v_currency);
  end if;
  v_result:=public.erp_v736_post_maintenance_invoice_pre_r49_identity(p_company_id,p_order_id);
  for v_entry in select value from jsonb_array_elements(coalesce(v_result->'costJournalEntries','[]'::jsonb)) loop
    update public.erp_inventory_fifo_consumptions fc set journal_entry_id=v_entry->>'journalEntryId'
    from public.erp_inventory_cost_layers l where fc.company_id=p_company_id
      and fc.sales_order_id=p_order_id and fc.status='active' and l.id=fc.layer_id
      and upper(l.currency)=upper(v_entry->>'currency');
  end loop;
  return v_result||jsonb_build_object('fifoValuationApplied',true,'fifoValuationOwner','material_issue_event');
end $$;

revoke all on table public.erp_maintenance_material_issues,public.erp_maintenance_material_issue_lines from public,anon,authenticated;
grant select,insert,update,delete on table public.erp_maintenance_material_issues,public.erp_maintenance_material_issue_lines to service_role;
revoke all on function public.erp_r57_refresh_maintenance_issue_costs(uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_r57_execute_maintenance_material_issue(uuid,uuid,uuid,uuid,text,numeric,timestamptz) from public,anon;
revoke all on function public.erp_r57_reverse_maintenance_material_issue(uuid,uuid,text) from public,anon;
revoke all on function public.erp_r57_maintenance_material_issue_state(uuid,uuid) from public,anon;
revoke all on function public.erp_r57_maintenance_issue_warehouse_options(uuid,uuid) from public,anon;
grant execute on function public.erp_r57_refresh_maintenance_issue_costs(uuid,uuid) to service_role;
grant execute on function public.erp_r57_execute_maintenance_material_issue(uuid,uuid,uuid,uuid,text,numeric,timestamptz) to authenticated,service_role;
grant execute on function public.erp_r57_reverse_maintenance_material_issue(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.erp_r57_maintenance_material_issue_state(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r57_maintenance_issue_warehouse_options(uuid,uuid) to authenticated,service_role;
notify pgrst,'reload schema';
commit;
