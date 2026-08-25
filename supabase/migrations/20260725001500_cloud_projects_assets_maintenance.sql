begin;
create extension if not exists pgcrypto;

create table if not exists public.erp_projects (
 id uuid primary key default gen_random_uuid(), company_id uuid not null, project_number text not null,
 name_ar text not null, name_en text not null default '', manager_employee_id uuid, start_date date not null,
 planned_end_date date, status text not null default 'planning', completion_percent numeric(5,2) not null default 0,
 budget_amount numeric(18,2) not null default 0, contract_value numeric(18,2) not null default 0,
 is_deleted boolean not null default false, deleted_at timestamptz, created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(), unique(company_id,project_number)
);
create table if not exists public.erp_project_tasks (
 id uuid primary key default gen_random_uuid(), company_id uuid not null, project_id uuid not null,
 task_number text not null, title text not null, status text not null default 'todo', planned_start_date date,
 planned_end_date date, estimated_hours numeric(12,2) not null default 0, assigned_employee_id uuid,
 is_deleted boolean not null default false, deleted_at timestamptz, created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(), unique(company_id,project_id,task_number)
);
create table if not exists public.erp_project_expenses (
 id uuid primary key default gen_random_uuid(), company_id uuid not null, project_id uuid not null,
 amount numeric(18,2) not null default 0, status text not null default 'posted', expense_date date not null default current_date,
 is_deleted boolean not null default false, deleted_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.erp_project_time_entries (
 id uuid primary key default gen_random_uuid(), company_id uuid not null, project_id uuid not null, employee_id uuid,
 hours numeric(12,2) not null default 0, hourly_cost numeric(18,2) not null default 0, status text not null default 'draft',
 work_date date not null default current_date, is_deleted boolean not null default false, deleted_at timestamptz,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists public.erp_asset_categories (
 id uuid primary key default gen_random_uuid(), company_id uuid not null, code text not null, name_ar text not null,
 name_en text not null default '', is_deleted boolean not null default false, deleted_at timestamptz,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(company_id,code)
);
create table if not exists public.erp_fixed_assets (
 id uuid primary key default gen_random_uuid(), company_id uuid not null, asset_number text not null, category_id uuid not null,
 name_ar text not null, acquisition_date date not null, acquisition_cost numeric(18,2) not null default 0,
 residual_value numeric(18,2) not null default 0, useful_life_months integer not null default 60,
 current_book_value numeric(18,2) not null default 0, status text not null default 'active',
 is_deleted boolean not null default false, deleted_at timestamptz, created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(), unique(company_id,asset_number)
);
create table if not exists public.erp_asset_maintenance_plans (
 id uuid primary key default gen_random_uuid(), company_id uuid not null, asset_id uuid not null,
 next_service_date date, is_active boolean not null default true, is_deleted boolean not null default false,
 deleted_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.erp_asset_work_orders (
 id uuid primary key default gen_random_uuid(), company_id uuid not null, work_order_number text not null,
 asset_id uuid not null, reported_at timestamptz not null default now(), problem_description text not null,
 status text not null default 'open', is_deleted boolean not null default false, deleted_at timestamptz,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(company_id,work_order_number)
);
create table if not exists public.erp_asset_depreciation_entries (
 id uuid primary key default gen_random_uuid(), company_id uuid not null, asset_id uuid not null, period_date date not null,
 opening_book_value numeric(18,2) not null, depreciation_amount numeric(18,2) not null,
 closing_book_value numeric(18,2) not null, created_at timestamptz not null default now(), unique(company_id,asset_id,period_date)
);


create table if not exists public.erp_car_history_events (
 id uuid primary key default gen_random_uuid(), company_id uuid not null, car_id text not null, event_type text not null,
 status_before text, status_after text, warehouse_before text, warehouse_after text, reference_type text, reference_id text,
 notes text, event_date timestamptz not null default now(), is_deleted boolean not null default false, deleted_at timestamptz,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists public.erp_maintenance_orders (
 id uuid primary key default gen_random_uuid(), company_id uuid not null, order_number text not null,
 car_id uuid not null, car_name text not null, customer_id uuid, customer_name text, warehouse_id uuid not null,
 is_sold_car boolean not null default false, pricing_type text not null default 'internal', status text not null default 'draft',
 workflow_stage text not null default 'order_draft', labor_cost numeric(18,2) not null default 0,
 parts_cost numeric(18,2) not null default 0, total_cost numeric(18,2) not null default 0,
 sale_price numeric(18,2) not null default 0, profit numeric(18,2) not null default 0,
 car_cost_added numeric(18,2) not null default 0, paid_amount numeric(18,2) not null default 0,
 maintenance_date timestamptz not null default now(), notes text, currency_code text not null default 'USD',
 exchange_rate numeric(18,6) not null default 1, amount_usd numeric(18,2) not null default 0,
 amount_iqd numeric(18,2) not null default 0, invoice_number text, stock_issue_number text,
 cancelled_at timestamptz, cancel_reason text, is_deleted boolean not null default false, deleted_at timestamptz,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(company_id,order_number)
);
create table if not exists public.erp_maintenance_parts (
 id uuid primary key default gen_random_uuid(), company_id uuid not null, maintenance_order_id uuid not null,
 product_id uuid not null, product_name text not null, warehouse_id uuid not null, quantity integer not null,
 unit_cost numeric(18,2) not null default 0, total_cost numeric(18,2) not null default 0,
 is_deleted boolean not null default false, deleted_at timestamptz, created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.erp_maintenance_payments (
 id uuid primary key default gen_random_uuid(), company_id uuid not null, maintenance_order_id uuid not null,
 amount numeric(18,2) not null, currency_code text not null, exchange_rate numeric(18,6) not null,
 amount_in_order_currency numeric(18,2) not null, payment_date timestamptz not null default now(), notes text,
 is_deleted boolean not null default false, deleted_at timestamptz, created_at timestamptz not null default now()
);

create index if not exists idx_erp_projects_status on public.erp_projects(company_id,status) where not is_deleted;
create index if not exists idx_erp_project_tasks_due on public.erp_project_tasks(company_id,planned_end_date,status) where not is_deleted;
create index if not exists idx_erp_assets_status on public.erp_fixed_assets(company_id,status) where not is_deleted;
create index if not exists idx_erp_maintenance_orders_car on public.erp_maintenance_orders(company_id,car_id,maintenance_date desc) where not is_deleted;

create or replace function public.erp_cloud_projects_dashboard(p_company_id uuid,p_day date)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_revenue numeric; v_cost numeric;
begin
 perform public.erp_active_company_context(p_company_id);
 select coalesce(sum(contract_value),0) into v_revenue from erp_projects where company_id=p_company_id and not is_deleted and status not in ('cancelled','closed');
 select coalesce((select sum(amount) from erp_project_expenses where company_id=p_company_id and not is_deleted and status<>'cancelled'),0)+
        coalesce((select sum(hours*hourly_cost) from erp_project_time_entries where company_id=p_company_id and not is_deleted and status='approved'),0) into v_cost;
 return jsonb_build_object('activeProjects',(select count(*) from erp_projects where company_id=p_company_id and not is_deleted and status in ('planning','active','on_hold')),
 'openTasks',(select count(*) from erp_project_tasks where company_id=p_company_id and not is_deleted and status not in ('done','cancelled')),
 'overdueTasks',(select count(*) from erp_project_tasks where company_id=p_company_id and not is_deleted and status not in ('done','cancelled') and planned_end_date<p_day),
 'revenue',v_revenue,'cost',v_cost,'profit',v_revenue-v_cost);
end $$;

create or replace function public.erp_list_cloud_projects(p_company_id uuid)
returns table(id uuid,"projectNumber" text,"nameAr" text,status text,"completionPercent" numeric,"managerName" text,"openTasks" bigint)
language sql security definer set search_path=public as $$
 select p.id,p.project_number,p.name_ar,p.status,p.completion_percent,
 coalesce(e.first_name_ar||' '||e.last_name_ar,e.first_name_en||' '||e.last_name_en,'—'),
 (select count(*) from erp_project_tasks t where t.company_id=p_company_id and t.project_id=p.id and not t.is_deleted and t.status not in ('done','cancelled'))
 from erp_projects p left join erp_hr_employees e on e.id=p.manager_employee_id and e.company_id=p.company_id and not e.is_deleted
 where p.company_id=p_company_id and not p.is_deleted and public.erp_active_company_context(p_company_id) is not null order by p.created_at desc;
$$;

create or replace function public.erp_create_cloud_project(p_company_id uuid,p_project_number text,p_name_ar text,p_start_date date,p_planned_end_date date,p_budget_amount numeric,p_contract_value numeric)
returns uuid language plpgsql security definer set search_path=public as $$ declare v_id uuid; begin
 perform public.erp_active_company_context(p_company_id);
 insert into erp_projects(company_id,project_number,name_ar,start_date,planned_end_date,budget_amount,contract_value)
 values(p_company_id,p_project_number,p_name_ar,p_start_date,p_planned_end_date,p_budget_amount,p_contract_value) returning id into v_id; return v_id; end $$;

create or replace function public.erp_add_cloud_project_task(p_company_id uuid,p_project_id uuid,p_title text,p_planned_start_date date,p_planned_end_date date,p_estimated_hours numeric)
returns uuid language plpgsql security definer set search_path=public as $$ declare v_id uuid; v_no text; begin
 perform public.erp_active_company_context(p_company_id); perform 1 from erp_projects where id=p_project_id and company_id=p_company_id and not is_deleted for update;
 if not found then raise exception 'Project not found'; end if;
 v_no:='T-'||(select count(*)+1 from erp_project_tasks where company_id=p_company_id and project_id=p_project_id and not is_deleted);
 insert into erp_project_tasks(company_id,project_id,task_number,title,planned_start_date,planned_end_date,estimated_hours)
 values(p_company_id,p_project_id,v_no,p_title,p_planned_start_date,p_planned_end_date,p_estimated_hours) returning id into v_id; return v_id; end $$;

create or replace function public.erp_cloud_project_profitability(p_company_id uuid,p_project_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$ declare r numeric; e numeric; l numeric; begin
 perform public.erp_active_company_context(p_company_id);
 select contract_value into r from erp_projects where id=p_project_id and company_id=p_company_id and not is_deleted;
 if not found then raise exception 'Project not found'; end if;
 select coalesce(sum(amount),0) into e from erp_project_expenses where company_id=p_company_id and project_id=p_project_id and not is_deleted and status<>'cancelled';
 select coalesce(sum(hours*hourly_cost),0) into l from erp_project_time_entries where company_id=p_company_id and project_id=p_project_id and not is_deleted and status='approved';
 return jsonb_build_object('revenue',r,'expense',e,'labor',l,'profit',r-e-l); end $$;

create or replace function public.erp_cloud_assets_dashboard(p_company_id uuid,p_due_date date)
returns jsonb language plpgsql security definer set search_path=public as $$ begin
 perform public.erp_active_company_context(p_company_id);
 return jsonb_build_object('activeAssets',(select count(*) from erp_fixed_assets where company_id=p_company_id and not is_deleted and status='active'),
 'bookValue',(select coalesce(sum(current_book_value),0) from erp_fixed_assets where company_id=p_company_id and not is_deleted and status='active'),
 'dueMaintenance',(select count(*) from erp_asset_maintenance_plans where company_id=p_company_id and not is_deleted and is_active and next_service_date<=p_due_date),
 'openWorkOrders',(select count(*) from erp_asset_work_orders where company_id=p_company_id and not is_deleted and status not in ('completed','cancelled'))); end $$;

create or replace function public.erp_list_cloud_fixed_assets(p_company_id uuid)
returns table(id uuid,"assetNumber" text,"nameAr" text,"categoryName" text,status text,"currentBookValue" numeric)
language sql security definer set search_path=public as $$
 select a.id,a.asset_number,a.name_ar,c.name_ar,a.status,a.current_book_value from erp_fixed_assets a join erp_asset_categories c on c.id=a.category_id and c.company_id=a.company_id
 where a.company_id=p_company_id and not a.is_deleted and not c.is_deleted and public.erp_active_company_context(p_company_id) is not null order by a.asset_number;
$$;

create or replace function public.erp_create_cloud_fixed_asset(p_company_id uuid,p_asset_number text,p_name_ar text,p_acquisition_date date,p_acquisition_cost numeric)
returns uuid language plpgsql security definer set search_path=public as $$ declare v_cat uuid; v_id uuid; begin
 perform public.erp_active_company_context(p_company_id); if p_acquisition_cost<0 then raise exception 'Invalid asset cost'; end if;
 select id into v_cat from erp_asset_categories where company_id=p_company_id and code='OFFICE' and not is_deleted limit 1;
 if v_cat is null then insert into erp_asset_categories(company_id,code,name_ar,name_en) values(p_company_id,'OFFICE','أصول مكتبية','Office assets') returning id into v_cat; end if;
 insert into erp_fixed_assets(company_id,asset_number,category_id,name_ar,acquisition_date,acquisition_cost,current_book_value)
 values(p_company_id,p_asset_number,v_cat,p_name_ar,p_acquisition_date,p_acquisition_cost,p_acquisition_cost) returning id into v_id; return v_id; end $$;

create or replace function public.erp_create_cloud_asset_work_order(p_company_id uuid,p_asset_id uuid,p_problem_description text)
returns uuid language plpgsql security definer set search_path=public as $$ declare v_id uuid; begin
 perform public.erp_active_company_context(p_company_id); perform 1 from erp_fixed_assets where id=p_asset_id and company_id=p_company_id and not is_deleted;
 if not found then raise exception 'Asset not found'; end if;
 insert into erp_asset_work_orders(company_id,work_order_number,asset_id,problem_description)
 values(p_company_id,'MWO-'||extract(epoch from clock_timestamp())::bigint,p_asset_id,p_problem_description) returning id into v_id; return v_id; end $$;

create or replace function public.erp_generate_cloud_asset_depreciation(p_company_id uuid,p_period_date date)
returns integer language plpgsql security definer set search_path=public as $$ declare a record; v_amount numeric; v_count integer:=0; begin
 perform public.erp_active_company_context(p_company_id); perform pg_advisory_xact_lock(hashtext(p_company_id::text||p_period_date::text));
 for a in select * from erp_fixed_assets where company_id=p_company_id and not is_deleted and status='active' for update loop
   if a.useful_life_months>0 then v_amount:=least(greatest((a.acquisition_cost-a.residual_value)/a.useful_life_months,0),greatest(a.current_book_value-a.residual_value,0)); else v_amount:=0; end if;
   if v_amount>0 then
    insert into erp_asset_depreciation_entries(company_id,asset_id,period_date,opening_book_value,depreciation_amount,closing_book_value)
    values(p_company_id,a.id,p_period_date,a.current_book_value,v_amount,a.current_book_value-v_amount) on conflict(company_id,asset_id,period_date) do nothing;
    if found then update erp_fixed_assets set current_book_value=current_book_value-v_amount,updated_at=now() where id=a.id; v_count:=v_count+1; end if;
   end if;
 end loop; return v_count; end $$;

create or replace function public.erp_list_cloud_maintenance_orders(p_company_id uuid)
returns table(id uuid,"orderNumber" text,"carId" uuid,"carName" text,"customerId" uuid,"customerName" text,"warehouseId" uuid,"isSoldCar" integer,"pricingType" text,status text,"laborCost" numeric,"partsCost" numeric,"totalCost" numeric,"salePrice" numeric,profit numeric,"carCostAdded" numeric,"maintenanceDate" timestamptz,notes text,"currencyCode" text,"exchangeRate" numeric,"workflowStage" text,"paidAmount" numeric,"invoiceNumber" text,"stockIssueNumber" text,"cancelReason" text)
language sql security definer set search_path=public as $$
 select o.id,o.order_number,o.car_id,o.car_name,o.customer_id,o.customer_name,o.warehouse_id,case when o.is_sold_car then 1 else 0 end,o.pricing_type,o.status,o.labor_cost,o.parts_cost,o.total_cost,o.sale_price,o.profit,o.car_cost_added,o.maintenance_date,o.notes,o.currency_code,o.exchange_rate,o.workflow_stage,o.paid_amount,o.invoice_number,o.stock_issue_number,o.cancel_reason
 from erp_maintenance_orders o where o.company_id=p_company_id and not o.is_deleted and public.erp_active_company_context(p_company_id) is not null order by o.maintenance_date desc;
$$;

create or replace function public.erp_prepare_cloud_maintenance_parts(p_company_id uuid,p_order_id uuid,p_warehouse_id text,p_parts jsonb)
returns numeric language plpgsql security definer set search_path=public as $$
declare x jsonb; v_product text; v_qty integer; v_name text; v_cost numeric; v_available numeric; v_total numeric:=0; v_stock public.erp_warehouse_stock%rowtype;
begin
 update erp_maintenance_parts set is_deleted=true,deleted_at=now(),updated_at=now() where company_id=p_company_id and maintenance_order_id=p_order_id and not is_deleted;
 for x in select * from jsonb_array_elements(p_parts) loop
  v_product:=x->>'product_id'; v_qty:=(x->>'quantity')::integer; if v_qty<=0 then raise exception 'Invalid part quantity'; end if;
  select data->>'name',coalesce((data->>'unitCost')::numeric,0) into v_name,v_cost from erp_inventory where company_id=p_company_id and id=v_product and not is_deleted;
  if not found then raise exception 'Part not found'; end if;
  select * into v_stock from erp_warehouse_stock where company_id=p_company_id and not is_deleted and data->>'warehouseId'=p_warehouse_id and data->>'productId'=v_product for update;
  v_available:=case when found then coalesce((v_stock.data->>'quantity')::numeric,0) else 0 end;
  if v_available<v_qty then raise exception 'Insufficient stock for %',v_name; end if;
  if found and coalesce((v_stock.data->>'averageUnitCost')::numeric,0)>0 then v_cost:=(v_stock.data->>'averageUnitCost')::numeric; end if;
  insert into erp_maintenance_parts(company_id,maintenance_order_id,product_id,product_name,warehouse_id,quantity,unit_cost,total_cost)
  values(p_company_id,p_order_id,v_product::uuid,v_name,p_warehouse_id::uuid,v_qty,v_cost,v_cost*v_qty); v_total:=v_total+v_cost*v_qty;
 end loop; return v_total; end $$;

create or replace function public.erp_create_cloud_maintenance_order(p_company_id uuid,p_car_id text,p_warehouse_id text,p_pricing_type text,p_labor_cost numeric,p_sale_price numeric,p_currency_code text,p_exchange_rate numeric,p_notes text,p_parts jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_car public.erp_cars%rowtype; v_parts numeric; v_sold boolean; v_effective text; v_price numeric; v_customer text; v_customer_name text;
begin
 perform public.erp_active_company_context(p_company_id); if p_exchange_rate<=0 or p_labor_cost<0 or p_sale_price<0 or jsonb_array_length(p_parts)=0 then raise exception 'Invalid maintenance data'; end if;
 select * into v_car from erp_cars where id=p_car_id and company_id=p_company_id and not is_deleted for update; if not found then raise exception 'Car not found'; end if;
 select data->>'customerId' into v_customer from erp_sales where company_id=p_company_id and not is_deleted and data->>'carId'=p_car_id order by coalesce((data->>'saleSequence')::int,0) desc, data->>'saleDate' desc limit 1;
 if v_customer is not null then select data->>'name' into v_customer_name from erp_customers where company_id=p_company_id and id=v_customer and not is_deleted; end if;
 v_sold:=v_customer is not null or lower(coalesce(v_car.data->>'status','')) in ('sold','مباعة','مباع'); v_effective:=case when v_sold then p_pricing_type else 'internal' end; v_price:=case when v_sold and v_effective='paid' then p_sale_price else 0 end;
 insert into erp_maintenance_orders(company_id,order_number,car_id,car_name,customer_id,customer_name,warehouse_id,is_sold_car,pricing_type,labor_cost,sale_price,maintenance_date,notes,currency_code,exchange_rate)
 values(p_company_id,'MO-'||extract(epoch from clock_timestamp())::bigint,p_car_id::uuid,concat_ws(' ',v_car.data->>'brand',v_car.data->>'model',v_car.data->>'year'),nullif(v_customer,'')::uuid,v_customer_name,p_warehouse_id::uuid,v_sold,v_effective,p_labor_cost,v_price,now(),p_notes,p_currency_code,p_exchange_rate) returning id into v_id;
 v_parts:=erp_prepare_cloud_maintenance_parts(p_company_id,v_id,p_warehouse_id,p_parts);
 update erp_maintenance_orders set parts_cost=v_parts,total_cost=v_parts+p_labor_cost,profit=v_price-(v_parts+p_labor_cost),amount_usd=case when p_currency_code='USD' then v_price else v_price/p_exchange_rate end,amount_iqd=case when p_currency_code='IQD' then v_price else v_price*p_exchange_rate end where id=v_id;
 return v_id; end $$;

create or replace function public.erp_update_cloud_maintenance_draft(p_company_id uuid,p_order_id uuid,p_warehouse_id text,p_pricing_type text,p_labor_cost numeric,p_sale_price numeric,p_currency_code text,p_exchange_rate numeric,p_notes text,p_parts jsonb)
returns void language plpgsql security definer set search_path=public as $$ declare o record; v_parts numeric; v_price numeric; begin
 perform public.erp_active_company_context(p_company_id); select * into o from erp_maintenance_orders where id=p_order_id and company_id=p_company_id and not is_deleted for update;
 if not found then raise exception 'Order not found'; end if; if o.workflow_stage not in ('order_draft','order_approved') then raise exception 'Order cannot be edited'; end if;
 v_price:=case when o.is_sold_car and p_pricing_type='paid' then p_sale_price else 0 end; v_parts:=erp_prepare_cloud_maintenance_parts(p_company_id,p_order_id,p_warehouse_id,p_parts);
 update erp_maintenance_orders set warehouse_id=p_warehouse_id::uuid,pricing_type=case when is_sold_car then p_pricing_type else 'internal' end,labor_cost=p_labor_cost,parts_cost=v_parts,total_cost=v_parts+p_labor_cost,sale_price=v_price,profit=v_price-(v_parts+p_labor_cost),currency_code=p_currency_code,exchange_rate=p_exchange_rate,amount_usd=case when p_currency_code='USD' then v_price else v_price/p_exchange_rate end,amount_iqd=case when p_currency_code='IQD' then v_price else v_price*p_exchange_rate end,notes=p_notes,updated_at=now() where id=p_order_id; end $$;

create or replace function public.erp_advance_cloud_maintenance_workflow(p_company_id uuid,p_order_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare o record; p record; s public.erp_warehouse_stock%rowtype; v_now timestamptz:=now();
begin
 perform public.erp_active_company_context(p_company_id); select * into o from erp_maintenance_orders where id=p_order_id and company_id=p_company_id and not is_deleted for update; if not found then raise exception 'Order not found'; end if;
 if o.workflow_stage='order_draft' then update erp_maintenance_orders set workflow_stage='order_approved',status='approved',updated_at=v_now where id=o.id;
 elsif o.workflow_stage='order_approved' then update erp_maintenance_orders set workflow_stage='stock_issue_draft',stock_issue_number='MSI-'||extract(epoch from clock_timestamp())::bigint,updated_at=v_now where id=o.id;
 elsif o.workflow_stage='stock_issue_draft' then
  for p in select * from erp_maintenance_parts where company_id=p_company_id and maintenance_order_id=o.id and not is_deleted loop
   select * into s from erp_warehouse_stock where company_id=p_company_id and not is_deleted and data->>'warehouseId'=o.warehouse_id::text and data->>'productId'=p.product_id::text for update;
   if not found or coalesce((s.data->>'quantity')::int,0)<p.quantity then raise exception 'Insufficient stock for %',p.product_name; end if;
   update erp_warehouse_stock set data=data||jsonb_build_object('quantity',((data->>'quantity')::int-p.quantity),'updatedAt',v_now),updated_at=v_now where company_id=p_company_id and id=s.id;
   perform erp_inventory_insert_movement(p_company_id,p.product_id::text,o.warehouse_id::text,'maintenance_out',-p.quantity,p.unit_cost,'maintenance_order',o.id::text,'Maintenance issue '||o.order_number);
   perform erp_inventory_refresh_product(p_company_id,p.product_id::text);
  end loop;
  if not o.is_sold_car then update erp_cars set data=data||jsonb_build_object('maintenanceCost',coalesce((data->>'maintenanceCost')::numeric,0)+o.total_cost,'updatedAt',v_now),updated_at=v_now where id=o.car_id::text and company_id=p_company_id; end if;
  update erp_maintenance_orders set workflow_stage='stock_issue_approved',car_cost_added=case when is_sold_car then 0 else total_cost end,updated_at=v_now where id=o.id;
 elsif o.workflow_stage='stock_issue_approved' then update erp_maintenance_orders set workflow_stage=case when pricing_type='paid' then 'invoice_draft' else 'completed' end,status=case when pricing_type='paid' then status else 'completed' end,invoice_number=case when pricing_type='paid' then 'MINV-'||extract(epoch from clock_timestamp())::bigint else invoice_number end,updated_at=v_now where id=o.id;
 elsif o.workflow_stage='invoice_draft' then update erp_maintenance_orders set workflow_stage='invoice_approved',updated_at=v_now where id=o.id;
 else raise exception 'No next workflow stage'; end if; end $$;

create or replace function public.erp_record_cloud_maintenance_payment(p_company_id uuid,p_order_id uuid,p_amount numeric,p_currency_code text default null,p_exchange_rate numeric default null,p_notes text default null)
returns uuid language plpgsql security definer set search_path=public as $$ declare o record; v_rate numeric; v_currency text; v_converted numeric; v_next numeric; v_id uuid; begin
 perform public.erp_active_company_context(p_company_id); if p_amount<=0 then raise exception 'Invalid payment amount'; end if;
 select * into o from erp_maintenance_orders where id=p_order_id and company_id=p_company_id and not is_deleted for update; if not found or o.workflow_stage<>'invoice_approved' then raise exception 'Approved invoice required'; end if;
 v_currency:=coalesce(p_currency_code,o.currency_code); v_rate:=coalesce(p_exchange_rate,o.exchange_rate); if v_rate<=0 then raise exception 'Invalid exchange rate'; end if;
 v_converted:=case when v_currency=o.currency_code then p_amount when v_currency='IQD' and o.currency_code='USD' then p_amount/v_rate else p_amount*v_rate end; v_next:=o.paid_amount+v_converted; if v_next>o.sale_price+0.001 then raise exception 'Payment exceeds balance'; end if;
 insert into erp_maintenance_payments(company_id,maintenance_order_id,amount,currency_code,exchange_rate,amount_in_order_currency,notes) values(p_company_id,o.id,p_amount,v_currency,v_rate,v_converted,p_notes) returning id into v_id;
 update erp_maintenance_orders set paid_amount=v_next,workflow_stage=case when v_next+0.001>=sale_price then 'paid' else 'invoice_approved' end,status=case when v_next+0.001>=sale_price then 'completed' else 'approved' end,updated_at=now() where id=o.id; return v_id; end $$;

create or replace function public.erp_cancel_cloud_maintenance_order(p_company_id uuid,p_order_id uuid,p_reason text default null)
returns void language plpgsql security definer set search_path=public as $$ declare o record; p record; s public.erp_warehouse_stock%rowtype; begin
 perform public.erp_active_company_context(p_company_id); select * into o from erp_maintenance_orders where id=p_order_id and company_id=p_company_id and not is_deleted for update; if not found then raise exception 'Order not found'; end if; if o.workflow_stage='cancelled' then return; end if;
 if o.workflow_stage in ('stock_issue_approved','invoice_draft','invoice_approved','paid','completed') and not exists(select 1 from erp_inventory_movements where company_id=p_company_id and data->>'referenceType'='maintenance_cancel' and data->>'referenceId'=o.id::text and not is_deleted) then
  for p in select * from erp_maintenance_parts where company_id=p_company_id and maintenance_order_id=o.id and not is_deleted loop
   select * into s from erp_warehouse_stock where company_id=p_company_id and not is_deleted and data->>'warehouseId'=o.warehouse_id::text and data->>'productId'=p.product_id::text for update;
   if found then update erp_warehouse_stock set data=data||jsonb_build_object('quantity',coalesce((data->>'quantity')::int,0)+p.quantity,'updatedAt',now()),updated_at=now() where company_id=p_company_id and id=s.id;
   else insert into erp_warehouse_stock(company_id,id,data,created_by,updated_by) values(p_company_id,o.warehouse_id::text||'::'||p.product_id::text,jsonb_build_object('warehouseId',o.warehouse_id::text,'productId',p.product_id::text,'quantity',p.quantity,'averageUnitCost',p.unit_cost,'expectedIncoming',0,'expectedOutgoing',0,'updatedAt',now()),auth.uid(),auth.uid()); end if;
   perform erp_inventory_insert_movement(p_company_id,p.product_id::text,o.warehouse_id::text,'maintenance_return',p.quantity,p.unit_cost,'maintenance_cancel',o.id::text,'Maintenance cancellation '||o.order_number);
   perform erp_inventory_refresh_product(p_company_id,p.product_id::text);
  end loop;
  if o.car_cost_added<>0 then update erp_cars set data=data||jsonb_build_object('maintenanceCost',greatest(coalesce((data->>'maintenanceCost')::numeric,0)-o.car_cost_added,0),'updatedAt',now()),updated_at=now() where id=o.car_id::text and company_id=p_company_id; end if;
 end if;
 update erp_maintenance_orders set workflow_stage='cancelled',status='cancelled',cancelled_at=now(),cancel_reason=nullif(trim(p_reason),''),updated_at=now() where id=o.id; end $$;

create or replace function public.erp_cloud_car_history(p_company_id uuid,p_car_id text)
returns table("eventType" text,"statusBefore" text,"statusAfter" text,"warehouseBeforeName" text,"warehouseAfterName" text,"referenceType" text,"referenceId" text,notes text,"eventDate" timestamptz)
language sql security definer set search_path=public as $$
 select e.event_type,e.status_before,e.status_after,coalesce(wb.data->>'name',e.warehouse_before),coalesce(wa.data->>'name',e.warehouse_after),e.reference_type,e.reference_id,e.notes,e.event_date
 from erp_car_history_events e left join erp_warehouses wb on wb.id=e.warehouse_before and wb.company_id=e.company_id left join erp_warehouses wa on wa.id=e.warehouse_after and wa.company_id=e.company_id
 where e.company_id=p_company_id and e.car_id=p_car_id and not e.is_deleted and public.erp_active_company_context(p_company_id) is not null order by e.event_date desc,e.id desc;
$$;
create or replace function public.erp_cloud_product_history(p_company_id uuid,p_product_id text)
returns table("movementType" text,quantity numeric,"unitCost" numeric,"totalCost" numeric,"referenceType" text,"referenceId" text,"movementDate" timestamptz,notes text,"movementNumber" text,"warehouseName" text)
language sql security definer set search_path=public as $$
 select m.data->>'movementType',coalesce((m.data->>'quantity')::numeric,0),coalesce((m.data->>'unitCost')::numeric,0),coalesce((m.data->>'totalCost')::numeric,0),m.data->>'referenceType',m.data->>'referenceId',(m.data->>'movementDate')::timestamptz,m.data->>'notes',m.data->>'movementNumber',coalesce(w.data->>'name',m.data->>'warehouseId')
 from erp_inventory_movements m left join erp_warehouses w on w.id=m.data->>'warehouseId' and w.company_id=m.company_id
 where m.company_id=p_company_id and m.data->>'productId'=p_product_id and not m.is_deleted and public.erp_active_company_context(p_company_id) is not null order by (m.data->>'movementDate')::timestamptz desc,m.created_at desc,m.id desc;
$$;

alter table erp_projects enable row level security; alter table erp_project_tasks enable row level security; alter table erp_project_expenses enable row level security; alter table erp_project_time_entries enable row level security;
alter table erp_asset_categories enable row level security; alter table erp_fixed_assets enable row level security; alter table erp_asset_maintenance_plans enable row level security; alter table erp_asset_work_orders enable row level security; alter table erp_asset_depreciation_entries enable row level security;
alter table erp_car_history_events enable row level security; alter table erp_maintenance_orders enable row level security; alter table erp_maintenance_parts enable row level security; alter table erp_maintenance_payments enable row level security;
do $$ declare t text; begin foreach t in array array['erp_projects','erp_project_tasks','erp_project_expenses','erp_project_time_entries','erp_asset_categories','erp_fixed_assets','erp_asset_maintenance_plans','erp_asset_work_orders','erp_asset_depreciation_entries','erp_car_history_events','erp_maintenance_orders','erp_maintenance_parts','erp_maintenance_payments'] loop execute format('drop policy if exists tenant_access on public.%I',t); execute format('create policy tenant_access on public.%I for all using (public.erp_active_company_context(company_id) is not null) with check (public.erp_active_company_context(company_id) is not null)',t); end loop; end $$;
commit;
