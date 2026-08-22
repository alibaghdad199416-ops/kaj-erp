begin;

-- Phase 10 corrective update:
-- 1) header/control accounts are never posting accounts;
-- 2) maintenance document currency is independent from inventory valuation currency;
-- 3) cross-currency maintenance cost summaries never add unlike currencies.

create or replace function public.erp_assert_postable_account(
  p_company_id uuid,
  p_account_id text
) returns text
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_account_id text;
begin
  v_account_id:=nullif(btrim(coalesce(p_account_id,'')),'');
  if v_account_id is null then
    raise exception 'account_required';
  end if;
  if not exists(
    select 1 from public.erp_accounts a
    where a.organization_id=p_company_id
      and a.account_id=v_account_id
      and a.is_active
  ) then
    raise exception 'account_not_found_or_inactive:%',v_account_id;
  end if;
  if exists(
    select 1 from public.erp_accounts child
    where child.organization_id=p_company_id
      and child.parent_account_id=v_account_id
  ) then
    raise exception 'non_postable_account:%',v_account_id;
  end if;
  return v_account_id;
end;
$$;

create or replace function public.erp_phase2_account_guard(
  p_company_id uuid,p_account_id text,p_expected_type text,p_currency text default null
) returns text
language plpgsql
security definer
set search_path=public
as $$
declare a public.erp_accounts%rowtype;
begin
  perform public.erp_assert_postable_account(p_company_id,p_account_id);
  select * into a
  from public.erp_accounts
  where organization_id=p_company_id
    and account_id=p_account_id
    and is_active
  limit 1;
  if lower(coalesce(a.account_type,''))<>lower(p_expected_type) then
    raise exception 'account_type_mismatch:%:%',p_account_id,p_expected_type;
  end if;
  if p_currency is not null
     and upper(coalesce(a.currency,'MULTI')) not in ('MULTI',upper(p_currency)) then
    raise exception 'account_currency_mismatch:%:%',p_account_id,upper(p_currency);
  end if;
  return a.account_id;
end;
$$;

create or replace function public.erp_r87_journal_line_postable_guard()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_account_id text;
begin
  if new.is_deleted then return new; end if;
  v_account_id:=nullif(btrim(coalesce(new.data->>'accountId',new.data->>'account_id','')),'');
  if v_account_id is not null then
    perform public.erp_assert_postable_account(new.company_id,v_account_id);
  end if;
  return new;
end;
$$;

drop trigger if exists erp_r87_journal_line_postable on public.erp_journal_lines;
create trigger erp_r87_journal_line_postable
before insert or update of data,is_deleted on public.erp_journal_lines
for each row execute function public.erp_r87_journal_line_postable_guard();

-- The old V2301 trigger incorrectly coupled maintenance document currency to
-- the product definition currency. Inventory valuation remains native to the
-- FIFO layer/product; billing remains in the maintenance document currency.
drop trigger if exists erp_v2301_maintenance_line_currency on public.erp_maintenance_parts;

alter table public.erp_maintenance_material_issues
  add column if not exists journal_entry_id text;

create or replace function public.erp_r87_maintenance_material_cost_totals(
  p_company_id uuid,
  p_order_id uuid,
  p_actual_only boolean default false
) returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  with line_values as (
    select
      public.erp_v764_definition_currency(
        mp.company_id,'product',coalesce(mp.source_product_id,mp.product_id::text)
      ) as cost_currency,
      case
        when exists(
          select 1
          from public.erp_maintenance_material_issue_lines il
          join public.erp_maintenance_material_issues i
            on i.company_id=il.company_id and i.id=il.issue_id and i.status='executed'
          where il.company_id=mp.company_id
            and il.maintenance_order_id=mp.maintenance_order_id
            and il.maintenance_part_id=mp.id
        ) then coalesce(mp.total_cost,0)
        when p_actual_only then 0
        else coalesce(mp.requested_total_cost,mp.total_cost,0)
      end as amount
    from public.erp_maintenance_parts mp
    where mp.company_id=p_company_id
      and mp.maintenance_order_id=p_order_id
      and not mp.is_deleted
      and mp.line_type<>'service'
  ), grouped as (
    select cost_currency,round(sum(amount),2) total
    from line_values
    group by cost_currency
  )
  select coalesce(jsonb_object_agg(cost_currency,total),'{}'::jsonb)
  from grouped;
$$;

create or replace function public.erp_r87_currency_total(
  p_totals jsonb,
  p_currency text
) returns numeric
language sql
immutable
set search_path=public
as $$
  select public.erp_try_numeric(
    coalesce(p_totals,'{}'::jsonb)->>upper(coalesce(p_currency,'')),0
  );
$$;

-- Draft request valuation can contain products whose inventory cost currency
-- differs from the document currency. costTotal remains a compatibility scalar
-- for the document currency only; costTotalsByCurrency is authoritative.
create or replace function public.erp_phase3_prepare_maintenance_lines(
  p_company_id uuid,
  p_order_id uuid,
  p_currency text,
  p_lines jsonb
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  x jsonb;
  v_product text;
  v_warehouse text;
  v_qty numeric;
  v_name text;
  v_cost numeric;
  v_price numeric;
  v_type text;
  v_cost_currency text;
  v_document_currency text:=upper(coalesce(nullif(btrim(p_currency),''),'USD'));
  v_stock public.erp_warehouse_stock%rowtype;
  v_cost_total numeric:=0;
  v_price_total numeric:=0;
  v_cost_totals jsonb:='{}'::jsonb;
begin
  perform public.erp_active_company_context(p_company_id);
  if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then
    raise exception 'maintenance_line_required';
  end if;

  update public.erp_maintenance_parts
     set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid()
   where company_id=p_company_id
     and maintenance_order_id=p_order_id
     and not is_deleted;

  for x in select value from jsonb_array_elements(p_lines) loop
    v_product:=nullif(btrim(coalesce(x->>'product_id',x->>'productId','')),'');
    v_warehouse:=nullif(btrim(coalesce(x->>'warehouse_id',x->>'warehouseId','')),'');
    v_qty:=public.erp_try_numeric(x->>'quantity',0);
    v_price:=public.erp_try_numeric(coalesce(x->>'unit_price',x->>'unitPrice'),0);
    if v_product is null or v_qty<=0 or v_price<0 then
      raise exception 'maintenance_line_invalid';
    end if;

    select coalesce(
             nullif(data->>'name',''),nullif(data->>'nameAr',''),
             nullif(data->>'name_ar',''),nullif(data->>'nameEn',''),id
           ),
           lower(coalesce(nullif(data->>'itemType',''),nullif(data->>'item_type',''),'stock')),
           public.erp_try_numeric(
             coalesce(data->>'unitCost',data->>'purchasePrice',data->>'averageUnitCost'),0
           )
      into v_name,v_type,v_cost
      from public.erp_inventory
     where company_id=p_company_id and id=v_product and not is_deleted
     limit 1;
    if not found then raise exception 'maintenance_item_not_found:%',v_product; end if;

    if v_type='service' then
      v_warehouse:=null;
      v_cost:=0;
      v_cost_currency:=v_document_currency;
    else
      if v_warehouse is null then raise exception 'maintenance_warehouse_required'; end if;
      v_cost_currency:=public.erp_v764_definition_currency(
        p_company_id,'product',v_product
      );
      select * into v_stock
      from public.erp_warehouse_stock
      where company_id=p_company_id and not is_deleted
        and coalesce(data->>'warehouseId',data->>'warehouse_id')=v_warehouse
        and coalesce(data->>'productId',data->>'product_id')=v_product
      limit 1;
      if found and public.erp_try_numeric(
        coalesce(v_stock.data->>'averageUnitCost',v_stock.data->>'average_unit_cost'),0
      )>0 then
        v_cost:=public.erp_try_numeric(
          coalesce(v_stock.data->>'averageUnitCost',v_stock.data->>'average_unit_cost'),0
        );
      end if;
      v_cost_totals:=jsonb_set(
        v_cost_totals,array[v_cost_currency],
        to_jsonb(round(
          public.erp_r87_currency_total(v_cost_totals,v_cost_currency)
          +coalesce(v_cost,0)*v_qty,2
        )),true
      );
      if v_cost_currency=v_document_currency then
        v_cost_total:=v_cost_total+coalesce(v_cost,0)*v_qty;
      end if;
    end if;

    insert into public.erp_maintenance_parts(
      company_id,maintenance_order_id,product_id,source_product_id,product_name,
      warehouse_id,source_warehouse_id,quantity,unit_cost,total_cost,line_type,
      unit_price,line_total_price
    ) values(
      p_company_id,p_order_id,public.erp_stage3_stable_uuid(v_product),v_product,
      coalesce(v_name,v_product),
      case when v_warehouse is null then null else public.erp_stage3_stable_uuid(v_warehouse) end,
      v_warehouse,v_qty::integer,coalesce(v_cost,0),coalesce(v_cost,0)*v_qty,
      v_type,v_price,v_price*v_qty
    );
    v_price_total:=v_price_total+v_price*v_qty;
  end loop;

  return jsonb_build_object(
    'costTotal',round(v_cost_total,2),
    'costTotalsByCurrency',v_cost_totals,
    'priceTotal',round(v_price_total,2),
    'documentCurrency',v_document_currency
  );
end;
$$;

create or replace function public.erp_maintenance_bound_accounts(
  p_company_id uuid,
  p_item_id text,
  p_currency text,
  p_service boolean default false
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  d jsonb;
  invoice_currency text:=upper(coalesce(nullif(btrim(p_currency),''),'USD'));
  cost_currency text;
  revenue_id text;
  asset_id text;
  cost_id text;
begin
  d:=public.erp_v764_definition_data(p_company_id,'product',p_item_id);
  if d is null then raise exception 'maintenance_item_not_found:%',p_item_id; end if;
  cost_currency:=public.erp_v764_definition_currency(p_company_id,'product',p_item_id);

  revenue_id:=nullif(coalesce(
    case when invoice_currency='USD' then coalesce(d->>'salesRevenueUsdAccountId',d->>'sales_revenue_usd_account_id')
         when invoice_currency='IQD' then coalesce(d->>'salesRevenueIqdAccountId',d->>'sales_revenue_iqd_account_id') end,
    d->>'salesRevenueAccountId',d->>'sales_revenue_account_id'), '');
  if revenue_id is null then
    if p_service then raise exception 'maintenance_service_revenue_account_missing:%',p_item_id;
    else raise exception 'maintenance_material_revenue_account_missing:%',p_item_id; end if;
  end if;
  perform public.erp_phase2_account_guard(
    p_company_id,revenue_id,'revenue',invoice_currency
  );

  if not p_service then
    asset_id:=nullif(coalesce(
      d->>'inventoryAssetAccountId',d->>'inventory_asset_account_id'
    ),'');
    cost_id:=nullif(coalesce(
      d->>'salesCostExpenseAccountId',d->>'sales_cost_expense_account_id',
      d->>'costOfSalesAccountId',d->>'costOfSaleAccountId',
      d->>'cost_of_sales_account_id',d->>'cost_of_sale_account_id'
    ),'');
    if asset_id is null then raise exception 'maintenance_material_inventory_account_missing:%',p_item_id; end if;
    if cost_id is null then raise exception 'maintenance_material_cost_account_missing:%',p_item_id; end if;
    perform public.erp_phase2_account_guard(p_company_id,asset_id,'asset',cost_currency);
    perform public.erp_phase2_account_guard(p_company_id,cost_id,'expense',cost_currency);
  end if;

  return jsonb_build_object(
    'currency',invoice_currency,
    'invoiceCurrency',invoice_currency,
    'costCurrency',cost_currency,
    'revenueAccountId',revenue_id,
    'assetAccountId',asset_id,
    'costExpenseAccountId',cost_id
  );
end;
$$;

-- FIFO consumptions must never reinterpret a product cost layer in the document
-- currency. This is a generic inventory valuation invariant and protects Sales
-- as well as Maintenance from accidental currency relabeling.
create or replace function public.erp_r87_fifo_definition_currency_guard()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_layer_currency text;
  v_definition_currency text;
begin
  if lower(coalesce(new.item_type,''))<>'product' then return new; end if;
  select upper(currency) into v_layer_currency
  from public.erp_inventory_cost_layers
  where company_id=new.company_id and id=new.layer_id;
  if v_layer_currency is null then raise exception 'inventory_cost_layer_missing:%',new.layer_id; end if;
  v_definition_currency:=public.erp_v764_definition_currency(
    new.company_id,'product',new.item_id
  );
  if v_layer_currency<>v_definition_currency then
    raise exception 'inventory_cost_currency_definition_mismatch:%:%:%',
      new.item_id,v_layer_currency,v_definition_currency;
  end if;
  return new;
end;
$$;

drop trigger if exists erp_r87_fifo_definition_currency on public.erp_inventory_fifo_consumptions;
create trigger erp_r87_fifo_definition_currency
before insert or update of layer_id,item_type,item_id on public.erp_inventory_fifo_consumptions
for each row execute function public.erp_r87_fifo_definition_currency_guard();

-- Inventory cost accounting belongs to the material movement event, not to the
-- later commercial invoice. Each issue is a single product and therefore a
-- single native inventory-cost currency.
create or replace function public.erp_r57_execute_maintenance_material_issue(
  p_company_id uuid,p_order_id uuid,p_issue_id uuid,p_part_id uuid,
  p_warehouse_id text,p_quantity numeric,p_effective_at timestamptz default now()
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  o public.erp_maintenance_orders%rowtype;
  mp public.erp_maintenance_parts%rowtype;
  ws public.erp_warehouse_stock%rowtype;
  w record;
  l record;
  v_product text;
  v_issued numeric;
  v_remaining numeric;
  v_needed numeric;
  v_take numeric;
  v_cost numeric:=0;
  v_existing public.erp_maintenance_material_issues%rowtype;
  v_cost_currency text;
  v_accounts jsonb;
  v_cost_lines jsonb;
  v_cost_journal text;
  v_effective timestamptz:=coalesce(p_effective_at,now());
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['maintenance.approve','maintenance.update']
  );
  if p_issue_id is null then raise exception 'maintenance_issue_id_required'; end if;
  if coalesce(p_quantity,0)<=0 then
    raise exception 'maintenance_issue_quantity_must_be_positive';
  end if;
  if nullif(btrim(coalesce(p_warehouse_id,'')),'') is null then
    raise exception 'maintenance_issue_warehouse_required';
  end if;

  select * into v_existing
  from public.erp_maintenance_material_issues
  where company_id=p_company_id and id=p_issue_id;
  if found then
    select * into l
    from public.erp_maintenance_material_issue_lines
    where company_id=p_company_id and issue_id=p_issue_id;
    if v_existing.status='executed'
       and l.maintenance_order_id=p_order_id
       and l.maintenance_part_id=p_part_id
       and l.warehouse_id=p_warehouse_id
       and l.quantity=p_quantity then
      return jsonb_build_object(
        'issueId',p_issue_id,'idempotent',true,'status','executed',
        'journalEntryId',v_existing.journal_entry_id
      );
    end if;
    raise exception 'maintenance_issue_id_conflict';
  end if;

  select * into o
  from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id and not is_deleted
  for update;
  if not found then raise exception 'maintenance_order_not_found'; end if;
  if o.workflow_stage<>'stock_issue_draft' then
    raise exception 'maintenance_issue_stage_invalid:%',o.workflow_stage;
  end if;

  select * into mp
  from public.erp_maintenance_parts
  where company_id=p_company_id and id=p_part_id
    and maintenance_order_id=p_order_id
    and not is_deleted and line_type<>'service'
  for update;
  if not found then raise exception 'maintenance_part_not_found'; end if;
  v_product:=coalesce(mp.source_product_id,mp.product_id::text);
  v_cost_currency:=public.erp_v764_definition_currency(
    p_company_id,'product',v_product
  );

  select coalesce(sum(il.quantity),0) into v_issued
  from public.erp_maintenance_material_issue_lines il
  join public.erp_maintenance_material_issues i
    on i.company_id=il.company_id and i.id=il.issue_id and i.status='executed'
  where il.company_id=p_company_id and il.maintenance_part_id=p_part_id;
  v_remaining:=mp.quantity-v_issued;
  if p_quantity>v_remaining then
    raise exception 'maintenance_issue_exceeds_remaining:%',v_remaining;
  end if;

  select * into w
  from public.erp_warehouses
  where company_id=p_company_id and id=p_warehouse_id and not is_deleted
  for update;
  if not found then raise exception 'maintenance_issue_warehouse_invalid'; end if;
  if lower(coalesce(w.data->>'isActive',w.data->>'active','true')) in ('false','0','no') then
    raise exception 'maintenance_issue_warehouse_inactive';
  end if;

  select * into ws
  from public.erp_warehouse_stock
  where company_id=p_company_id and not is_deleted
    and coalesce(data->>'warehouseId',data->>'warehouse_id')=p_warehouse_id
    and coalesce(data->>'productId',data->>'product_id')=v_product
  for update;
  if not found or public.erp_try_numeric(ws.data->>'quantity',0)
      -public.erp_try_numeric(ws.data->>'reservedQuantity',0)<p_quantity then
    raise exception 'maintenance_insufficient_stock:%',mp.product_name;
  end if;

  insert into public.erp_maintenance_material_issues(
    id,company_id,maintenance_order_id,effective_at,created_by
  ) values(p_issue_id,p_company_id,p_order_id,v_effective,auth.uid());
  insert into public.erp_maintenance_material_issue_lines(
    company_id,issue_id,maintenance_order_id,maintenance_part_id,
    product_id,warehouse_id,quantity
  ) values(
    p_company_id,p_issue_id,p_order_id,p_part_id,
    v_product,p_warehouse_id,p_quantity
  );

  update public.erp_warehouse_stock
  set data=data||jsonb_build_object(
      'quantity',public.erp_try_numeric(data->>'quantity',0)-p_quantity,
      'updatedAt',now()
    ),
    updated_at=now(),updated_by=auth.uid()
  where id=ws.id;

  v_needed:=p_quantity;
  for l in
    select * from public.erp_inventory_cost_layers q
    where q.company_id=p_company_id and q.item_type='product'
      and q.item_id=v_product and q.warehouse_id=p_warehouse_id
      and q.status in ('active','consumed') and q.remaining_quantity>0
      and q.effective_at<=v_effective
    order by q.effective_at,q.created_at,q.id
    for update
  loop
    exit when v_needed<=0;
    if upper(l.currency)<>v_cost_currency then
      raise exception 'maintenance_fifo_currency_definition_mismatch:%:%:%',
        v_product,upper(l.currency),v_cost_currency;
    end if;
    v_take:=least(v_needed,l.remaining_quantity);
    update public.erp_inventory_cost_layers
    set remaining_quantity=remaining_quantity-v_take,
        status=case when remaining_quantity-v_take<=0 then 'consumed' else 'active' end,
        updated_at=now(),updated_by=auth.uid()
    where id=l.id;
    insert into public.erp_inventory_fifo_consumptions(
      company_id,delivery_id,sales_order_id,layer_id,item_type,item_id,
      warehouse_id,quantity,unit_cost,effective_at,status
    ) values(
      p_company_id,p_issue_id,p_order_id,l.id,'product',v_product,
      p_warehouse_id,v_take,l.unit_cost,v_effective,'active'
    );
    v_cost:=v_cost+v_take*l.unit_cost;
    v_needed:=v_needed-v_take;
  end loop;
  if v_needed>0 then
    raise exception 'insufficient_maintenance_cost_layers:%',v_product;
  end if;

  if v_cost>0 then
    v_accounts:=public.erp_maintenance_bound_accounts(
      p_company_id,v_product,coalesce(o.currency_code,v_cost_currency),false
    );
    if upper(v_accounts->>'costCurrency')<>v_cost_currency then
      raise exception 'maintenance_cost_account_currency_mismatch:%:%:%',
        v_product,v_accounts->>'costCurrency',v_cost_currency;
    end if;
    v_cost_lines:=jsonb_build_array(
      jsonb_build_object(
        'accountId',v_accounts->>'costExpenseAccountId',
        'debit',round(v_cost,6),'credit',0,'currency',v_cost_currency,
        'description','Maintenance material issue cost',
        'itemId',v_product,'maintenanceOrderId',p_order_id,
        'maintenanceIssueId',p_issue_id,'quantity',p_quantity
      ),
      jsonb_build_object(
        'accountId',v_accounts->>'assetAccountId',
        'debit',0,'credit',round(v_cost,6),'currency',v_cost_currency,
        'description','Maintenance inventory issue',
        'itemId',v_product,'maintenanceOrderId',p_order_id,
        'maintenanceIssueId',p_issue_id,'quantity',p_quantity
      )
    );
    v_cost_journal:=public.erp_phase2_insert_journal_at(
      p_company_id,'maintenance_material_issue_cost',p_issue_id::text,
      public.erp_next_document_number(
        p_company_id,'maintenance_material_issue_cost_journal','MMIC',v_effective
      ),
      'Maintenance material issue '||o.order_number,
      v_cost_currency,v_cost_lines,v_effective
    );
    update public.erp_inventory_fifo_consumptions
    set journal_entry_id=v_cost_journal
    where company_id=p_company_id and delivery_id=p_issue_id
      and sales_order_id=p_order_id and status='active';
  end if;

  update public.erp_maintenance_material_issue_lines
  set actual_cost=v_cost
  where company_id=p_company_id and issue_id=p_issue_id;
  update public.erp_maintenance_material_issues
  set total_cost=v_cost,journal_entry_id=v_cost_journal
  where company_id=p_company_id and id=p_issue_id;

  perform public.erp_inventory_insert_movement(
    p_company_id,v_product,p_warehouse_id,'maintenance_out',-p_quantity,
    v_cost/p_quantity,'maintenance_issue',p_issue_id::text,
    'Maintenance material issue '||o.order_number
  );
  perform public.erp_inventory_refresh_product(p_company_id,v_product);
  perform public.erp_r57_refresh_maintenance_issue_costs(p_company_id,p_order_id);

  if not exists(
    select 1 from public.erp_maintenance_parts x
    where x.company_id=p_company_id and x.maintenance_order_id=p_order_id
      and not x.is_deleted and x.line_type<>'service'
      and x.quantity>(
        select coalesce(sum(il.quantity),0)
        from public.erp_maintenance_material_issue_lines il
        join public.erp_maintenance_material_issues i
          on i.company_id=il.company_id and i.id=il.issue_id and i.status='executed'
        where il.company_id=p_company_id and il.maintenance_part_id=x.id
      )
  ) then
    update public.erp_maintenance_orders
    set workflow_stage='stock_issue_approved',
        stock_issue_number=case
          when stock_issue_number is null or stock_issue_number='PENDING' then
            public.erp_next_document_number(
              p_company_id,'maintenance_stock_issue','MSI',o.maintenance_date
            )
          else stock_issue_number
        end,
        updated_at=now()
    where id=p_order_id;
  end if;

  return jsonb_build_object(
    'issueId',p_issue_id,'idempotent',false,'quantity',p_quantity,
    'actualCost',round(v_cost,6),'costCurrency',v_cost_currency,
    'journalEntryId',v_cost_journal,'remaining',v_remaining-p_quantity
  );
end;
$$;

create or replace function public.erp_r57_reverse_maintenance_material_issue(
  p_company_id uuid,p_issue_id uuid,p_reason text default null
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  i public.erp_maintenance_material_issues%rowtype;
  il record;
  fc record;
  ws public.erp_warehouse_stock%rowtype;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['maintenance.approve','maintenance.update']
  );
  select * into i
  from public.erp_maintenance_material_issues
  where company_id=p_company_id and id=p_issue_id
  for update;
  if not found then raise exception 'maintenance_issue_not_found'; end if;
  if i.status='reversed' then return; end if;
  if exists(
    select 1 from public.erp_maintenance_orders
    where company_id=p_company_id and id=i.maintenance_order_id
      and workflow_stage in ('invoice_approved','paid','completed')
  ) then
    raise exception 'maintenance_issue_has_later_financial_stage';
  end if;

  perform public.erp_v736_void_journal_id(p_company_id,i.journal_entry_id);
  for fc in
    select * from public.erp_inventory_fifo_consumptions
    where company_id=p_company_id and delivery_id=p_issue_id and status='active'
    for update
  loop
    update public.erp_inventory_cost_layers
    set remaining_quantity=least(original_quantity,remaining_quantity+fc.quantity),
        status='active',updated_at=now(),updated_by=auth.uid()
    where id=fc.layer_id;
  end loop;
  update public.erp_inventory_fifo_consumptions
  set status='reversed',reversed_at=now()
  where company_id=p_company_id and delivery_id=p_issue_id and status='active';

  for il in
    select * from public.erp_maintenance_material_issue_lines
    where company_id=p_company_id and issue_id=p_issue_id
  loop
    ws:=public.erp_inventory_ensure_stock(
      p_company_id,il.warehouse_id,il.product_id
    );
    update public.erp_warehouse_stock
    set data=data||jsonb_build_object(
        'quantity',public.erp_try_numeric(data->>'quantity',0)+il.quantity,
        'updatedAt',now()
      ),
      updated_at=now(),updated_by=auth.uid()
    where id=ws.id;
    perform public.erp_inventory_insert_movement(
      p_company_id,il.product_id,il.warehouse_id,
      'maintenance_return',il.quantity,
      case when il.quantity>0 then il.actual_cost/il.quantity else 0 end,
      'maintenance_issue_reversal',p_issue_id::text,
      coalesce(nullif(btrim(p_reason),''),'Maintenance issue reversal')
    );
    perform public.erp_inventory_refresh_product(p_company_id,il.product_id);
  end loop;

  update public.erp_maintenance_material_issues
  set status='reversed',reversed_at=now(),reversed_by=auth.uid(),
      reversal_reason=nullif(btrim(coalesce(p_reason,'')),'')
  where id=p_issue_id;
  update public.erp_maintenance_orders
  set workflow_stage='stock_issue_draft',updated_at=now()
  where company_id=p_company_id and id=i.maintenance_order_id
    and workflow_stage='stock_issue_approved';
  perform public.erp_r57_refresh_maintenance_issue_costs(
    p_company_id,i.maintenance_order_id
  );
end;
$$;

-- Keep legacy scalar cost columns strictly in the maintenance document currency.
-- Native inventory values are retained in the per-currency payload/map.
create or replace function public.erp_r57_refresh_maintenance_issue_costs(
  p_company_id uuid,p_order_id uuid
) returns numeric
language plpgsql
security definer
set search_path=public
as $$
declare
  p record;
  v_line_cost numeric;
  v_document_currency text;
  v_line_currency text;
  v_document_total numeric:=0;
  v_totals jsonb:='{}'::jsonb;
begin
  select upper(currency_code) into v_document_currency
  from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id and not is_deleted;
  if v_document_currency is null then raise exception 'maintenance_order_not_found'; end if;

  for p in select mp.id,mp.quantity,coalesce(mp.source_product_id,mp.product_id::text) product_id
    from public.erp_maintenance_parts mp
    where mp.company_id=p_company_id and mp.maintenance_order_id=p_order_id
      and not mp.is_deleted and mp.line_type<>'service' for update
  loop
    select coalesce(sum(fc.total_cost),0) into v_line_cost
    from public.erp_maintenance_material_issue_lines il
    join public.erp_maintenance_material_issues i
      on i.company_id=il.company_id and i.id=il.issue_id and i.status='executed'
    join public.erp_inventory_fifo_consumptions fc
      on fc.company_id=il.company_id and fc.delivery_id=il.issue_id
      and fc.sales_order_id=il.maintenance_order_id and fc.item_id=il.product_id
      and fc.warehouse_id=il.warehouse_id and fc.status='active'
    where il.company_id=p_company_id
      and il.maintenance_order_id=p_order_id
      and il.maintenance_part_id=p.id;

    v_line_currency:=public.erp_v764_definition_currency(
      p_company_id,'product',p.product_id
    );
    update public.erp_maintenance_parts
    set total_cost=round(v_line_cost,2),
      unit_cost=case when p.quantity>0 then round(v_line_cost/p.quantity,2) else 0 end,
      updated_at=now()
    where id=p.id;

    v_totals:=jsonb_set(
      v_totals,array[v_line_currency],
      to_jsonb(round(
        public.erp_r87_currency_total(v_totals,v_line_currency)+v_line_cost,2
      )),true
    );
    if v_line_currency=v_document_currency then
      v_document_total:=v_document_total+v_line_cost;
    end if;
  end loop;

  update public.erp_maintenance_orders
  set parts_cost=round(v_document_total,2),
      total_cost=round(labor_cost+v_document_total,2),
      profit=round(sale_price-(labor_cost+v_document_total),2),
      accounting_payload=coalesce(accounting_payload,'{}'::jsonb)||jsonb_build_object(
        'materialCostTotalsByCurrency',v_totals,
        'costScalarCurrency',v_document_currency,
        'crossCurrencyMaterialCost',exists(
          select 1 from jsonb_each_text(v_totals) e
          where upper(e.key)<>v_document_currency and public.erp_try_numeric(e.value,0)<>0
        )
      ),
      updated_at=now()
  where company_id=p_company_id and id=p_order_id;
  return round(v_document_total,2);
end;
$$;

create or replace function public.erp_v736_post_maintenance_invoice(
  p_company_id uuid,p_order_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  o public.erp_maintenance_orders%rowtype;
  p record;
  ac jsonb;
  defaults jsonb;
  v_currency text;
  v_effective timestamptz;
  v_partner_account text;
  v_labor_revenue_account text;
  v_revenue_lines jsonb:='[]'::jsonb;
  v_entry text;
  v_line_amount numeric;
  v_bound_billing numeric:=0;
  v_labor_amount numeric;
  v_doc_fifo_cost numeric:=0;
  v_cost_totals jsonb:='{}'::jsonb;
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['maintenance.approve']);
  select * into o from public.erp_maintenance_orders
   where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found then raise exception 'maintenance_order_not_found'; end if;
  if o.invoice_journal_entry_id is not null then
    return jsonb_build_object(
      'journalEntryId',o.invoice_journal_entry_id,
      'costJournalEntries',o.cost_journal_entry_ids,
      'capitalizationApplied',false,'fifoValuationApplied',true,
      'accountingOwner','invoice_item_bindings'
    );
  end if;
  if o.pricing_type<>'paid' or o.sale_price<=0 then raise exception 'paid_maintenance_invoice_required'; end if;
  if o.customer_id is null then raise exception 'paid_maintenance_customer_required'; end if;
  v_currency:=upper(coalesce(o.currency_code,''));
  if v_currency not in ('USD','IQD') then raise exception 'maintenance_currency_invalid:%',v_currency; end if;
  v_effective:=coalesce(o.maintenance_date,now());
  perform public.erp_validate_operational_date(p_company_id,'maintenance',v_effective);
  perform public.erp_v764_assert_partner_dual_ledgers(p_company_id,o.customer_id::text,'customer');
  v_partner_account:=public.erp_workflow_partner_account(
    p_company_id,'customer',o.customer_id::text,v_currency
  );
  if v_partner_account is null then raise exception 'maintenance_receivable_account_missing'; end if;
  perform public.erp_phase2_account_guard(p_company_id,v_partner_account,'asset',v_currency);
  v_revenue_lines:=jsonb_build_array(jsonb_build_object(
    'accountId',v_partner_account,'debit',o.sale_price,'credit',0,'currency',v_currency,
    'description','Maintenance invoice receivable','maintenanceOrderId',p_order_id,
    'invoiceNumber',o.invoice_number
  ));

  for p in select * from public.erp_maintenance_parts
    where company_id=p_company_id and maintenance_order_id=p_order_id and not is_deleted
    order by id
  loop
    ac:=public.erp_maintenance_bound_accounts(
      p_company_id,coalesce(p.source_product_id,p.product_id::text),
      v_currency,p.line_type='service'
    );
    v_line_amount:=round(coalesce(p.line_total_price,p.unit_price*p.quantity,0),2);
    if v_line_amount<0 then raise exception 'maintenance_line_billing_invalid:%',p.id; end if;
    if v_line_amount>0 then
      v_revenue_lines:=v_revenue_lines||jsonb_build_array(jsonb_build_object(
        'accountId',ac->>'revenueAccountId','debit',0,'credit',v_line_amount,
        'currency',v_currency,
        'description',case when p.line_type='service' then 'Maintenance service - ' else 'Maintenance material - ' end||p.product_name,
        'itemId',coalesce(p.source_product_id,p.product_id::text),
        'maintenanceLineId',p.id,'quantity',p.quantity,'unitPrice',p.unit_price
      ));
      v_bound_billing:=v_bound_billing+v_line_amount;
    end if;
  end loop;
  if v_bound_billing>o.sale_price+0.01 then
    raise exception 'maintenance_invoice_line_total_exceeds_invoice:%:%',v_bound_billing,o.sale_price;
  end if;
  v_labor_amount:=round(greatest(o.sale_price-v_bound_billing,0),2);
  if v_labor_amount>0 then
    defaults:=public.erp_v736_ensure_currency_revenue_accounts(p_company_id);
    v_labor_revenue_account:=case when v_currency='IQD'
      then defaults->>'maintenanceRevenueIqdAccountId'
      else defaults->>'maintenanceRevenueUsdAccountId' end;
    if v_labor_revenue_account is null then raise exception 'maintenance_labor_revenue_account_missing'; end if;
    perform public.erp_phase2_account_guard(
      p_company_id,v_labor_revenue_account,'revenue',v_currency
    );
    v_revenue_lines:=v_revenue_lines||jsonb_build_array(jsonb_build_object(
      'accountId',v_labor_revenue_account,'debit',0,'credit',v_labor_amount,
      'currency',v_currency,'description','Maintenance labor',
      'maintenanceOrderId',p_order_id
    ));
  end if;

  v_entry:=public.erp_phase2_insert_journal_at(
    p_company_id,'maintenance_invoice_revenue',p_order_id::text,
    public.erp_next_document_number(
      p_company_id,'maintenance_invoice_journal','MIJ',v_effective
    ),
    'Maintenance invoice '||coalesce(o.invoice_number,o.order_number),
    v_currency,v_revenue_lines,v_effective
  );

  v_cost_totals:=public.erp_r87_maintenance_material_cost_totals(
    p_company_id,p_order_id,true
  );
  v_doc_fifo_cost:=public.erp_r87_currency_total(v_cost_totals,v_currency);

  update public.erp_maintenance_orders
  set invoice_journal_entry_id=v_entry,
      cost_journal_entry_ids='[]'::jsonb,
      car_cost_added=0,
      accounting_payload=coalesce(accounting_payload,'{}'::jsonb)||jsonb_build_object(
        'accountingOwner','invoice_item_bindings',
        'actualFifoCost',round(v_doc_fifo_cost,6),
        'actualFifoCostByCurrency',v_cost_totals,
        'boundLineBilling',round(v_bound_billing,2),
        'laborBilling',v_labor_amount,'carCostAdded',0,
        'capitalizationApplied',false,'capitalizationPolicy','disabled',
        'postedAt',now(),'effectiveAt',v_effective,
        'invoiceCurrency',v_currency,
        'inventoryCostPostingOwner','material_issue_event'
      ),
      updated_at=now()
  where company_id=p_company_id and id=p_order_id;

  return jsonb_build_object(
    'journalEntryId',v_entry,'costJournalEntries','[]'::jsonb,
    'actualFifoCostByCurrency',v_cost_totals,
    'capitalizationApplied',false,'fifoValuationApplied',true,
    'fifoValuationOwner','material_issue_event',
    'accountingOwner','invoice_item_bindings','effectiveAt',v_effective
  );
end;
$$;

-- The delete path has a specialized stock/FIFO reconciler. Preserve that mature
-- implementation and add exact issue-journal reversal around it.
do $$
begin
  if to_regprocedure(
    'public.erp_r87_reverse_maintenance_issue_for_delete_legacy(uuid,uuid,uuid,text)'
  ) is null then
    execute 'alter function public.erp_r57_reverse_maintenance_issue_for_delete(uuid,uuid,uuid,text) '
      'rename to erp_r87_reverse_maintenance_issue_for_delete_legacy';
  end if;
end;
$$;

create or replace function public.erp_r57_reverse_maintenance_issue_for_delete(
  p_company_id uuid,p_order_id uuid,p_issue_id uuid,p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_journal text;
  v_result jsonb;
begin
  select journal_entry_id into v_journal
  from public.erp_maintenance_material_issues
  where company_id=p_company_id and id=p_issue_id
    and maintenance_order_id=p_order_id;
  v_result:=public.erp_r87_reverse_maintenance_issue_for_delete_legacy(
    p_company_id,p_order_id,p_issue_id,p_reason
  );
  perform public.erp_v736_void_journal_id(p_company_id,v_journal);
  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'costJournalEntryId',v_journal,'costJournalReversed',v_journal is not null
  );
end;
$$;

-- Enrich the existing governed R9 maintenance listing without bypassing its
-- record-scope/field-permission filtering.
create or replace function public.erp_r87_list_cloud_maintenance_orders(
  p_company_id uuid
) returns setof jsonb
language sql
stable
security definer
set search_path=public
as $$
  select row_value || case
    when row_value ? 'totalCost' then jsonb_build_object(
      'materialCostTotalsByCurrency',
      public.erp_r87_maintenance_material_cost_totals(
        p_company_id,(row_value->>'id')::uuid,false
      )
    )
    else '{}'::jsonb
  end
  from public.erp_r9_list_cloud_maintenance_orders(p_company_id) row_value;
$$;

-- Preserve the mature reconciliation implementation and normalize its scalar
-- compatibility fields when material valuation spans currencies.
do $$
begin
  if to_regprocedure('public.erp_r87_maintenance_cost_reconciliation_legacy(uuid,uuid)') is null then
    execute 'alter function public.erp_r57_maintenance_cost_reconciliation(uuid,uuid) '
      'rename to erp_r87_maintenance_cost_reconciliation_legacy';
  end if;
end;
$$;

create or replace function public.erp_r57_maintenance_cost_reconciliation(
  p_company_id uuid,p_order_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_result jsonb;
  v_requested jsonb;
  v_actual jsonb;
  v_currency text;
  v_labor numeric;
  v_cross boolean;
begin
  v_result:=public.erp_r87_maintenance_cost_reconciliation_legacy(
    p_company_id,p_order_id
  );
  v_currency:=upper(coalesce(v_result->>'currency',''));
  v_labor:=public.erp_try_numeric(v_result->>'laborCost',0);
  v_requested:=public.erp_r87_maintenance_material_cost_totals(
    p_company_id,p_order_id,false
  );
  v_actual:=public.erp_r87_maintenance_material_cost_totals(
    p_company_id,p_order_id,true
  );
  v_cross:=exists(
    select 1 from jsonb_each_text(v_requested) e
    where upper(e.key)<>v_currency and public.erp_try_numeric(e.value,0)<>0
  ) or exists(
    select 1 from jsonb_each_text(v_actual) e
    where upper(e.key)<>v_currency and public.erp_try_numeric(e.value,0)<>0
  );
  return v_result||jsonb_build_object(
    'requestedMaterialsCostByCurrency',v_requested,
    'issuedMaterialsActualCostByCurrency',v_actual,
    'requestedMaterialsCost',public.erp_r87_currency_total(v_requested,v_currency),
    'issuedMaterialsActualCost',public.erp_r87_currency_total(v_actual,v_currency),
    'totalOperationalCost',round(
      v_labor+public.erp_r87_currency_total(v_actual,v_currency),2
    ),
    'crossCurrencyMaterials',v_cross,
    'materialDiscrepancy',case when v_cross then false
      else coalesce((v_result->>'materialDiscrepancy')::boolean,false) end,
    'issuedNotInvoicedCost',case when v_cross then 0
      else public.erp_try_numeric(v_result->>'issuedNotInvoicedCost',0) end,
    'invoicedNotIssuedValue',case when v_cross then 0
      else public.erp_try_numeric(v_result->>'invoicedNotIssuedValue',0) end
  );
end;
$$;

do $$
begin
  if to_regprocedure('public.erp_r87_maintenance_material_issue_state_legacy(uuid,uuid)') is null then
    execute 'alter function public.erp_r57_maintenance_material_issue_state(uuid,uuid) '
      'rename to erp_r87_maintenance_material_issue_state_legacy';
  end if;
end;
$$;

create or replace function public.erp_r57_maintenance_material_issue_state(
  p_company_id uuid,p_order_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_result jsonb;
  v_currency text;
  v_actual jsonb;
begin
  v_result:=public.erp_r87_maintenance_material_issue_state_legacy(
    p_company_id,p_order_id
  );
  select upper(currency_code) into v_currency
  from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id and not is_deleted;
  v_actual:=public.erp_r87_maintenance_material_cost_totals(
    p_company_id,p_order_id,true
  );
  return v_result||jsonb_build_object(
    'issuedMaterialsActualCostByCurrency',v_actual,
    'issuedMaterialsActualCost',public.erp_r87_currency_total(v_actual,v_currency)
  );
end;
$$;

-- Keep the authoritative one-statement details snapshot on the enriched list.
create or replace function public.erp_r64_get_maintenance_order_snapshot(
  p_company_id uuid,p_order_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_order jsonb;
  v_lines jsonb;
  v_reconciliation jsonb;
  v_issue_state jsonb;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'maintenance.view') then
    raise exception 'permission_denied:maintenance.view' using errcode='42501';
  end if;
  select row_value into v_order
  from public.erp_r87_list_cloud_maintenance_orders(p_company_id) row_value
  where row_value->>'id'=p_order_id::text
  limit 1;
  if v_order is null then
    raise exception 'maintenance_order_not_found' using errcode='P0002';
  end if;
  select coalesce(jsonb_agg(row_value),'[]'::jsonb) into v_lines
  from public.erp_r9_get_cloud_maintenance_order_lines(
    p_company_id,p_order_id
  ) row_value;
  v_reconciliation:=public.erp_r57_maintenance_cost_reconciliation(
    p_company_id,p_order_id
  );
  v_issue_state:=public.erp_r57_maintenance_material_issue_state(
    p_company_id,p_order_id
  );
  return jsonb_build_object(
    'order',v_order,'lines',coalesce(v_lines,'[]'::jsonb),
    'reconciliation',coalesce(v_reconciliation,'{}'::jsonb),
    'issueState',coalesce(v_issue_state,'{}'::jsonb),
    'snapshotAt',statement_timestamp()
  );
end;
$$;

revoke all on function public.erp_assert_postable_account(uuid,text) from public,anon,authenticated;
revoke all on function public.erp_r87_journal_line_postable_guard() from public,anon,authenticated;
revoke all on function public.erp_r87_fifo_definition_currency_guard() from public,anon,authenticated;
revoke all on function public.erp_r87_maintenance_material_cost_totals(uuid,uuid,boolean) from public,anon,authenticated;
revoke all on function public.erp_r87_currency_total(jsonb,text) from public,anon,authenticated;
revoke all on function public.erp_r57_execute_maintenance_material_issue(uuid,uuid,uuid,uuid,text,numeric,timestamptz) from public,anon;
revoke all on function public.erp_r57_reverse_maintenance_material_issue(uuid,uuid,text) from public,anon;
revoke all on function public.erp_r57_reverse_maintenance_issue_for_delete(uuid,uuid,uuid,text) from public,anon,authenticated,service_role;
revoke all on function public.erp_r87_reverse_maintenance_issue_for_delete_legacy(uuid,uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.erp_r57_execute_maintenance_material_issue(uuid,uuid,uuid,uuid,text,numeric,timestamptz) to authenticated,service_role;
grant execute on function public.erp_r57_reverse_maintenance_material_issue(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.erp_r87_reverse_maintenance_issue_for_delete_legacy(uuid,uuid,uuid,text) to service_role;

revoke all on function public.erp_r87_list_cloud_maintenance_orders(uuid) from public,anon;
revoke all on function public.erp_r87_maintenance_cost_reconciliation_legacy(uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_r87_maintenance_material_issue_state_legacy(uuid,uuid) from public,anon,authenticated;

grant execute on function public.erp_assert_postable_account(uuid,text) to service_role;
grant execute on function public.erp_r87_journal_line_postable_guard() to service_role;
grant execute on function public.erp_r87_fifo_definition_currency_guard() to service_role;
grant execute on function public.erp_r87_maintenance_material_cost_totals(uuid,uuid,boolean) to authenticated,service_role;
grant execute on function public.erp_r87_currency_total(jsonb,text) to authenticated,service_role;
grant execute on function public.erp_r87_list_cloud_maintenance_orders(uuid) to authenticated,service_role;
grant execute on function public.erp_r57_maintenance_cost_reconciliation(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r57_maintenance_material_issue_state(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r64_get_maintenance_order_snapshot(uuid,uuid) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
