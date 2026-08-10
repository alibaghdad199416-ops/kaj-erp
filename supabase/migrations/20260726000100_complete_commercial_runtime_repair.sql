-- Quality Line ERP: complete commercial runtime repair.
-- Repairs safe dashboard/search projections, realtime invalidation, warehouse
-- initialization, inventory posting, invoice accounting, payments and details.

begin;

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Safe legacy JSON conversion helpers. One malformed imported value must never
-- make an entire dashboard, catalog or search RPC fail.
-- ---------------------------------------------------------------------------
create or replace function public.erp_try_numeric(p_value text, p_default numeric default 0)
returns numeric
language plpgsql immutable
as $$
begin
  if nullif(btrim(coalesce(p_value,'')),'') is null then return p_default; end if;
  return p_value::numeric;
exception when others then
  return p_default;
end;
$$;

create or replace function public.erp_try_integer(p_value text, p_default integer default 0)
returns integer
language plpgsql immutable
as $$
begin
  if nullif(btrim(coalesce(p_value,'')),'') is null then return p_default; end if;
  return p_value::numeric::integer;
exception when others then
  return p_default;
end;
$$;

create or replace function public.erp_try_date(p_value text, p_default date default null)
returns date
language plpgsql immutable
as $$
begin
  if nullif(btrim(coalesce(p_value,'')),'') is null then return p_default; end if;
  return p_value::timestamptz::date;
exception when others then
  begin
    return p_value::date;
  exception when others then
    return p_default;
  end;
end;
$$;

create or replace function public.erp_try_timestamptz(p_value text, p_default timestamptz default null)
returns timestamptz
language plpgsql immutable
as $$
begin
  if nullif(btrim(coalesce(p_value,'')),'') is null then return p_default; end if;
  return p_value::timestamptz;
exception when others then
  return p_default;
end;
$$;

create or replace function public.erp_try_boolean(p_value text, p_default boolean default false)
returns boolean
language plpgsql immutable
as $$
begin
  if nullif(btrim(coalesce(p_value,'')),'') is null then return p_default; end if;
  return lower(btrim(p_value)) in ('1','true','yes','on','active','enabled');
exception when others then
  return p_default;
end;
$$;

-- ---------------------------------------------------------------------------
-- Workflow audit records used by the UI, PDF and troubleshooting.
-- ---------------------------------------------------------------------------
create table if not exists public.erp_commercial_workflow_audit (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  module text not null,
  parent_id uuid not null,
  document_id uuid,
  document_number text,
  action text not null,
  from_status text,
  to_status text,
  reason text,
  performed_by uuid default auth.uid(),
  performed_at timestamptz not null default now()
);
create index if not exists erp_commercial_workflow_audit_parent_idx
  on public.erp_commercial_workflow_audit(company_id,module,parent_id,performed_at desc);
alter table public.erp_commercial_workflow_audit enable row level security;
drop policy if exists erp_commercial_workflow_audit_tenant on public.erp_commercial_workflow_audit;
create policy erp_commercial_workflow_audit_tenant
  on public.erp_commercial_workflow_audit for all to authenticated
  using (public.erp_is_company_member(company_id))
  with check (public.erp_is_company_member(company_id));
grant select,insert on public.erp_commercial_workflow_audit to authenticated;

-- Keep journal-line JSON compatible with the strict Flutter model. Older
-- posting functions stored the relational row id only, while the UI reads id,
-- accountCode and accountName from the JSON payload. Enrich all new rows and
-- repair existing rows without deleting historical journals.
create or replace function public.erp_enrich_journal_line_payload()
returns trigger
language plpgsql security definer set search_path=public as $$
declare
  v_code text;
  v_name text;
begin
  select a.code,a.name into v_code,v_name
  from public.erp_accounts a
  where a.organization_id=new.company_id
    and a.account_id=new.data->>'accountId'
  limit 1;
  new.data:=coalesce(new.data,'{}'::jsonb)||jsonb_build_object(
    'id',new.id,
    'accountCode',coalesce(v_code,new.data->>'accountCode',''),
    'accountName',coalesce(v_name,new.data->>'accountName','')
  );
  return new;
end;
$$;

drop trigger if exists erp_journal_lines_payload_compat on public.erp_journal_lines;
create trigger erp_journal_lines_payload_compat
before insert or update of data on public.erp_journal_lines
for each row execute function public.erp_enrich_journal_line_payload();

update public.erp_journal_lines l
set data=coalesce(l.data,'{}'::jsonb)||jsonb_build_object(
      'id',l.id,
      'accountCode',coalesce((
        select a.code from public.erp_accounts a
        where a.organization_id=l.company_id and a.account_id=l.data->>'accountId'
        limit 1
      ),l.data->>'accountCode',''),
      'accountName',coalesce((
        select a.name from public.erp_accounts a
        where a.organization_id=l.company_id and a.account_id=l.data->>'accountId'
        limit 1
      ),l.data->>'accountName','')
    )
where coalesce(l.data->>'id','')<>l.id
   or coalesce(l.data->>'accountCode','')=''
   or coalesce(l.data->>'accountName','')='';

create or replace function public.erp_commercial_audit(
  p_company_id uuid,
  p_module text,
  p_parent_id uuid,
  p_document_id uuid,
  p_document_number text,
  p_action text,
  p_from_status text,
  p_to_status text,
  p_reason text default null
) returns void
language plpgsql security definer set search_path=public as $$
begin
  insert into public.erp_commercial_workflow_audit(
    company_id,module,parent_id,document_id,document_number,action,
    from_status,to_status,reason,performed_by,performed_at
  ) values(
    p_company_id,p_module,p_parent_id,p_document_id,p_document_number,p_action,
    p_from_status,p_to_status,p_reason,auth.uid(),now()
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Dashboard: safe against legacy values and aware of the new workflow tables.
-- ---------------------------------------------------------------------------
create or replace function public.erp_cloud_dashboard_snapshot(
  p_company_id uuid,
  p_reference_day date default current_date
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_total_sales numeric := 0;
  v_today_sales numeric := 0;
  v_total_purchases numeric := 0;
  v_total_expenses numeric := 0;
  v_total_receivables numeric := 0;
  v_total_payables numeric := 0;
  v_sales_trend jsonb := '[]'::jsonb;
  v_recent jsonb := '[]'::jsonb;
  v_upcoming jsonb := '[]'::jsonb;
begin
  if not public.erp_is_company_member(p_company_id) then
    raise exception 'access denied';
  end if;

  select coalesce(sum(public.erp_try_numeric(s.data->>'salePrice',0)),0),
         coalesce(sum(case when public.erp_try_date(s.data->>'saleDate',null)=p_reference_day
                           then public.erp_try_numeric(s.data->>'salePrice',0) else 0 end),0),
         coalesce(sum(public.erp_try_numeric(s.data->>'remainingAmount',0)),0)
    into v_total_sales,v_today_sales,v_total_receivables
  from public.erp_sales s
  where s.company_id=p_company_id and not coalesce(s.is_deleted,false);

  select v_total_sales + coalesce(sum(public.erp_try_numeric(d.payload->>'totalAmount',0)),0),
         v_today_sales + coalesce(sum(case when d.created_at::date=p_reference_day
                                           then public.erp_try_numeric(d.payload->>'totalAmount',0) else 0 end),0),
         v_total_receivables + coalesce(sum(public.erp_try_numeric(d.payload->>'remainingAmount',0)),0)
    into v_total_sales,v_today_sales,v_total_receivables
  from public.erp_commercial_workflow_documents d
  where d.company_id=p_company_id and d.module='sales' and d.document_type='invoice'
    and d.status='approved' and not d.is_deleted;

  select coalesce(sum(public.erp_try_numeric(p.data->>'totalAmount',0)),0),
         coalesce(sum(public.erp_try_numeric(p.data->>'remainingAmount',0)),0)
    into v_total_purchases,v_total_payables
  from public.erp_purchases p
  where p.company_id=p_company_id and not coalesce(p.is_deleted,false);

  select v_total_purchases + coalesce(sum(public.erp_try_numeric(d.payload->>'totalAmount',0)),0),
         v_total_payables + coalesce(sum(public.erp_try_numeric(d.payload->>'remainingAmount',0)),0)
    into v_total_purchases,v_total_payables
  from public.erp_commercial_workflow_documents d
  where d.company_id=p_company_id and d.module='purchases' and d.document_type='invoice'
    and d.status='approved' and not d.is_deleted;

  select coalesce(sum(public.erp_try_numeric(e.data->>'amount',0)),0)
    into v_total_expenses
  from public.erp_expenses e
  where e.company_id=p_company_id and not coalesce(e.is_deleted,false);

  select coalesce(jsonb_agg(jsonb_build_object('date',days.d::date::text,'amount',coalesce(t.amount,0)) order by days.d),'[]'::jsonb)
    into v_sales_trend
  from generate_series(p_reference_day-6,p_reference_day,'1 day'::interval) days(d)
  left join lateral (
    select coalesce(sum(x.amount),0) amount
    from (
      select public.erp_try_numeric(s.data->>'salePrice',0) amount
      from public.erp_sales s
      where s.company_id=p_company_id and not s.is_deleted
        and public.erp_try_date(s.data->>'saleDate',null)=days.d::date
      union all
      select public.erp_try_numeric(d.payload->>'totalAmount',0)
      from public.erp_commercial_workflow_documents d
      where d.company_id=p_company_id and d.module='sales' and d.document_type='invoice'
        and d.status='approved' and not d.is_deleted and d.created_at::date=days.d::date
    ) x
  ) t on true;

  select coalesce(jsonb_agg(jsonb_build_object(
      'action',a.action,'module',a.module,
      'description',coalesce(a.document_number,'')||' • '||coalesce(a.from_status,'-')||' → '||coalesce(a.to_status,'-'),
      'userName',coalesce(u.email,'النظام'),'createdAt',a.performed_at::text
    ) order by a.performed_at desc),'[]'::jsonb)
    into v_recent
  from (
    select * from public.erp_commercial_workflow_audit
    where company_id=p_company_id
    order by performed_at desc limit 12
  ) a
  left join auth.users u on u.id=a.performed_by;

  select coalesce(jsonb_agg(jsonb_build_object(
      'customerName',coalesce(i.data->>'customerName',''),
      'installmentNo',public.erp_try_integer(i.data->>'installmentNo',0),
      'dueDate',public.erp_try_date(i.data->>'dueDate',p_reference_day)::text,
      'remainingAmount',public.erp_try_numeric(i.data->>'remainingAmount',0),
      'isOverdue',public.erp_try_date(i.data->>'dueDate',p_reference_day)<p_reference_day
    ) order by public.erp_try_date(i.data->>'dueDate',p_reference_day)),'[]'::jsonb)
    into v_upcoming
  from (
    select * from public.erp_installments
    where company_id=p_company_id and not is_deleted
      and public.erp_try_numeric(data->>'remainingAmount',0)>0
      and public.erp_try_date(data->>'dueDate',null) is not null
    order by public.erp_try_date(data->>'dueDate',p_reference_day)
    limit 12
  ) i;

  return jsonb_build_object(
    'totalCars',(select count(*) from public.erp_cars where company_id=p_company_id and not is_deleted),
    'availableCars',(select count(*) from public.erp_cars where company_id=p_company_id and not is_deleted and lower(coalesce(data->>'status','')) in ('available','متاحة','متوفر','متوفرة')),
    'reservedCars',(select count(*) from public.erp_cars where company_id=p_company_id and not is_deleted and lower(coalesce(data->>'status','')) in ('selling','pending_sale','قيد البيع','reserved','محجوزة','محجوز')),
    'soldCars',(select count(*) from public.erp_cars where company_id=p_company_id and not is_deleted and lower(coalesce(data->>'status','')) in ('sold','مباعة','مباع')),
    'totalCustomers',(select count(*) from public.erp_customers where company_id=p_company_id and not is_deleted),
    'totalSuppliers',(select count(*) from public.erp_suppliers where company_id=p_company_id and not is_deleted),
    'totalSales',v_total_sales,
    'todaySales',v_today_sales,
    'totalPurchases',v_total_purchases,
    'totalExpenses',v_total_expenses,
    'netProfit',v_total_sales-v_total_purchases-v_total_expenses,
    'cashBalanceUsd',(select coalesce(sum(case when lower(coalesce(data->>'type',''))='receipt' then public.erp_try_numeric(data->>'amount',0) else -public.erp_try_numeric(data->>'amount',0) end),0) from public.erp_cash_transactions where company_id=p_company_id and not is_deleted and upper(coalesce(data->>'currency',''))='USD'),
    'cashBalanceIqd',(select coalesce(sum(case when lower(coalesce(data->>'type',''))='receipt' then public.erp_try_numeric(data->>'amount',0) else -public.erp_try_numeric(data->>'amount',0) end),0) from public.erp_cash_transactions where company_id=p_company_id and not is_deleted and upper(coalesce(data->>'currency',''))='IQD'),
    'inventoryValue',(select coalesce(sum(public.erp_try_numeric(data->>'quantity',0)*public.erp_try_numeric(data->>'averageUnitCost',0)),0) from public.erp_warehouse_stock where company_id=p_company_id and not is_deleted),
    'totalReceivables',v_total_receivables,
    'totalPayables',v_total_payables,
    'pendingPurchaseCars',(select count(*) from public.erp_cars where company_id=p_company_id and not is_deleted and lower(coalesce(data->>'status','')) in ('pending_purchase','purchase_pending','قيد الشراء','قيد شراء')),
    'lowStockItems',(select count(*) from public.erp_warehouse_stock where company_id=p_company_id and not is_deleted and public.erp_try_numeric(data->>'quantity',0)<=public.erp_try_numeric(data->>'minimumQuantity',0)),
    'carsWithoutWarehouse',(select count(*) from public.erp_cars where company_id=p_company_id and not is_deleted and nullif(btrim(coalesce(data->>'warehouseId',data->>'warehouse_id','')),'') is null and lower(coalesce(data->>'status','')) not in ('sold','مباعة','مباع')),
    'activeReservations',(select count(*) from public.erp_reservations where company_id=p_company_id and not is_deleted and lower(status)='active'),
    'overdueInstallments',(select count(*) from public.erp_installments where company_id=p_company_id and not is_deleted and public.erp_try_numeric(data->>'remainingAmount',0)>0 and public.erp_try_date(data->>'dueDate',p_reference_day)<p_reference_day),
    'dueSoonInstallments',(select count(*) from public.erp_installments where company_id=p_company_id and not is_deleted and public.erp_try_numeric(data->>'remainingAmount',0)>0 and public.erp_try_date(data->>'dueDate',p_reference_day) between p_reference_day and p_reference_day+7),
    'outstandingInstallments',(select coalesce(sum(public.erp_try_numeric(data->>'remainingAmount',0)),0) from public.erp_installments where company_id=p_company_id and not is_deleted),
    'pendingSyncOperations',0,
    'salesTrend',v_sales_trend,
    'recentActivities',v_recent,
    'upcomingInstallments',v_upcoming,
    'generatedAt',now()
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Global search: broadened and protected from malformed numeric values.
-- ---------------------------------------------------------------------------
create or replace function public.erp_cloud_global_search(
  p_company_id uuid,
  p_query text,
  p_limit integer default 50
) returns setof jsonb
language sql security definer set search_path=public as $$
  with q as (
    select '%'||btrim(coalesce(p_query,''))||'%' pattern
  ), rows as (
    select c.id::text id,'السيارات'::text type,
      concat_ws(' ',coalesce(c.data->>'brand',c.data->>'make'),c.data->>'model',c.data->>'year') title,
      coalesce(c.data->>'chassis',c.data->>'vin',c.data->>'plateNumber','') subtitle,
      '/cars'::text route,'cars.view'::text permission,'car'::text icon,
      c.data->>'status' status,null::numeric amount,c.created_at occurred_at,1 rank
    from public.erp_cars c cross join q
    where c.company_id=p_company_id and not c.is_deleted and (
      coalesce(c.data->>'brand',c.data->>'make','') ilike q.pattern
      or coalesce(c.data->>'model','') ilike q.pattern
      or coalesce(c.data->>'chassis',c.data->>'vin','') ilike q.pattern
      or coalesce(c.data->>'plateNumber','') ilike q.pattern)
    union all
    select i.id,'المنتجات',coalesce(i.data->>'name',i.data->>'code',''),
      concat_ws(' • ',i.data->>'code',i.data->>'barcode'),'/inventory','inventory.view','inventory',
      case when public.erp_try_boolean(i.data->>'isActive',true) then 'active' else 'inactive' end,
      public.erp_try_numeric(i.data->>'salePrice',0),i.created_at,2
    from public.erp_inventory i cross join q
    where i.company_id=p_company_id and not i.is_deleted and (
      coalesce(i.data->>'name','') ilike q.pattern
      or coalesce(i.data->>'code','') ilike q.pattern
      or coalesce(i.data->>'barcode','') ilike q.pattern)
    union all
    select x.id,'العملاء',coalesce(x.data->>'name',''),coalesce(x.data->>'phone',''),
      '/customers','customers.view','customer',null,null,x.created_at,3
    from public.erp_customers x cross join q
    where x.company_id=p_company_id and not x.is_deleted and (
      coalesce(x.data->>'name','') ilike q.pattern
      or coalesce(x.data->>'phone','') ilike q.pattern
      or coalesce(x.data->>'email','') ilike q.pattern)
    union all
    select x.id,'المجهزون',coalesce(x.data->>'name',''),coalesce(x.data->>'phone',''),
      '/suppliers','suppliers.view','supplier',null,null,x.created_at,4
    from public.erp_suppliers x cross join q
    where x.company_id=p_company_id and not x.is_deleted and (
      coalesce(x.data->>'name','') ilike q.pattern
      or coalesce(x.data->>'phone','') ilike q.pattern
      or coalesce(x.data->>'email','') ilike q.pattern)
    union all
    select o.id::text,'أوامر البيع',o.order_number,coalesce(c.data->>'name',''),
      '/sales','sales.view','sale',o.status,o.total,o.created_at,5
    from public.erp_sales_orders_cloud o cross join q
    left join public.erp_customers c on c.company_id=o.company_id and c.id=o.customer_id and not c.is_deleted
    where o.company_id=p_company_id and not o.is_deleted and (
      o.order_number ilike q.pattern or coalesce(c.data->>'name','') ilike q.pattern)
    union all
    select o.id::text,'أوامر الشراء',o.order_number,coalesce(s.data->>'name',''),
      '/purchases','purchases.view','purchase',o.status,o.total,o.created_at,6
    from public.erp_purchase_orders_cloud o cross join q
    left join public.erp_suppliers s on s.company_id=o.company_id and s.id=o.supplier_id and not s.is_deleted
    where o.company_id=p_company_id and not o.is_deleted and (
      o.order_number ilike q.pattern or coalesce(s.data->>'name','') ilike q.pattern)
    union all
    select d.id::text,'المستندات',coalesce(d.data->>'titleAr',d.data->>'titleEn',d.data->>'title',''),
      coalesce(d.data->>'documentNumber',''),'/documents','documents.view','document',d.data->>'status',null,d.created_at,7
    from public.erp_document_records d cross join q
    where d.company_id=p_company_id and not d.is_deleted and (
      coalesce(d.data->>'titleAr',d.data->>'titleEn',d.data->>'title','') ilike q.pattern
      or coalesce(d.data->>'documentNumber','') ilike q.pattern)
    union all
    select a.account_id,'الحسابات',a.code||' — '||a.name,coalesce(a.currency,''),
      '/accounting','accounting.view','account',case when a.is_active then 'active' else 'inactive' end,
      a.opening_balance,a.synced_at,8
    from public.erp_accounts a cross join q
    where a.organization_id=p_company_id and (
      a.code ilike q.pattern or a.name ilike q.pattern)
  )
  select jsonb_build_object(
    'id',id,'type',type,'title',title,'subtitle',subtitle,'route',route,
    'permission',permission,'icon',icon,'status',status,'amount',amount,
    'date',occurred_at::text
  )
  from rows
  where public.erp_is_company_member(p_company_id)
    and length(btrim(coalesce(p_query,'')))>=2
  order by rank,occurred_at desc
  limit greatest(1,least(coalesce(p_limit,50),200));
$$;

-- Catalogs use the exact Arabic and English statuses stored by the app.
create or replace function public.erp_cloud_purchase_order_catalog(p_company_id uuid)
returns setof jsonb language sql security definer set search_path=public as $$
 select jsonb_build_object(
   'itemType','car','id',c.id,
   'description',concat_ws(' ',coalesce(c.data->>'brand',c.data->>'make'),c.data->>'model',c.data->>'year'),
   'baseCost',coalesce(public.erp_try_numeric(c.data->>'purchasePrice',null),public.erp_try_numeric(c.data->>'costPrice',0)),
   'imagePath',coalesce(c.data->>'imagePath',c.data->>'image'),
   'details',c.data||jsonb_build_object('id',c.id)
 )
 from public.erp_cars c
 where c.company_id=p_company_id and not c.is_deleted
   and lower(btrim(coalesce(c.data->>'status',''))) in (
     'known','identified','defined','registered','purchase_pending','pending_purchase',
     'معرفة','معرّفة','مُعرفة','قيد الشراء','قيد شراء'
   )
   and public.erp_is_company_member(p_company_id)
 union all
 select jsonb_build_object(
   'itemType','product','id',i.id,
   'description',coalesce(i.data->>'name',i.data->>'code',''),
   'baseCost',coalesce(public.erp_try_numeric(i.data->>'unitCost',null),public.erp_try_numeric(i.data->>'costPrice',0)),
   'imagePath',coalesce(i.data->>'imagePath',i.data->>'image'),
   'details',i.data||jsonb_build_object('id',i.id)
 )
 from public.erp_inventory i
 where i.company_id=p_company_id and not i.is_deleted
   and public.erp_try_boolean(i.data->>'isActive',true)
   and public.erp_is_company_member(p_company_id);
$$;

create or replace function public.erp_cloud_sales_order_catalog(p_company_id uuid)
returns setof jsonb language sql security definer set search_path=public as $$
 select jsonb_build_object(
   'itemType','car','id',c.id,
   'description',concat_ws(' ',coalesce(c.data->>'brand',c.data->>'make'),c.data->>'model',c.data->>'year'),
   'availableQuantity',1,
   'basePrice',public.erp_try_numeric(c.data->>'salePrice',0),
   'imagePath',coalesce(c.data->>'imagePath',c.data->>'image'),
   'details',c.data||jsonb_build_object('id',c.id)
 )
 from public.erp_cars c
 where c.company_id=p_company_id and not c.is_deleted
   and lower(btrim(coalesce(c.data->>'status',''))) in ('available','متوفرة','متوفر','متاحة')
   and nullif(btrim(coalesce(c.data->>'warehouseId',c.data->>'warehouse_id','')),'') is not null
   and public.erp_is_company_member(p_company_id)
 union all
 select jsonb_build_object(
   'itemType','product','id',i.id,
   'description',coalesce(i.data->>'name',i.data->>'code',''),
   'availableQuantity',coalesce(sum(public.erp_try_numeric(ws.data->>'quantity',0)),0),
   'basePrice',public.erp_try_numeric(i.data->>'salePrice',0),
   'imagePath',coalesce(i.data->>'imagePath',i.data->>'image'),
   'details',i.data||jsonb_build_object(
      'id',i.id,'النوع','منتج','الكود',i.data->>'code',
      'الكمية المتاحة',coalesce(sum(public.erp_try_numeric(ws.data->>'quantity',0)),0),
      'الكلفة',public.erp_try_numeric(i.data->>'unitCost',0),
      'سعر البيع',public.erp_try_numeric(i.data->>'salePrice',0)
   )
 )
 from public.erp_inventory i
 left join public.erp_warehouse_stock ws
   on ws.company_id=i.company_id and ws.data->>'productId'=i.id and not ws.is_deleted
 where i.company_id=p_company_id and not i.is_deleted
   and public.erp_try_boolean(i.data->>'isActive',true)
   and public.erp_is_company_member(p_company_id)
 group by i.company_id,i.id,i.data
 having coalesce(sum(public.erp_try_numeric(ws.data->>'quantity',0)),0)>0;
$$;

-- Do not resurrect an intentionally deleted MAIN warehouse on every login.
create or replace function public.erp_prepare_company_runtime(p_company_id uuid)
returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_result jsonb;
  v_branch_id uuid;
  v_had_warehouse_history boolean;
  v_had_active_main boolean;
  v_generated_warehouse text;
begin
  if auth.uid() is null then
    raise exception 'authentication_required' using errcode='42501';
  end if;
  if not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;

  select exists(select 1 from public.erp_warehouses where company_id=p_company_id),
         exists(select 1 from public.erp_warehouses
                where company_id=p_company_id and not is_deleted
                  and public.erp_try_boolean(data->>'isActive',true)
                  and lower(btrim(coalesce(data->>'code','')))='main')
    into v_had_warehouse_history,v_had_active_main;

  v_result:=public.erp_seed_company_runtime_defaults(p_company_id);
  v_branch_id:=(v_result->>'branchId')::uuid;
  v_generated_warehouse:=nullif(v_result->>'warehouseId','');

  if v_had_warehouse_history and not v_had_active_main and v_generated_warehouse is not null then
    update public.erp_warehouses
    set data=data||jsonb_build_object('isActive',false,'updatedAt',now()),
        is_deleted=true,deleted_at=coalesce(deleted_at,now()),updated_at=now(),updated_by=auth.uid()
    where company_id=p_company_id and id=v_generated_warehouse
      and lower(btrim(coalesce(data->>'code','')))='main';
    v_result:=jsonb_set(v_result,'{warehouseId}','null'::jsonb,true)
      || jsonb_build_object('warehousePreservedDeleted',true);
  end if;

  update public.company_memberships
  set default_branch_id=coalesce(default_branch_id,v_branch_id),updated_at=now()
  where company_id=p_company_id
    and public.erp_membership_matches_current_user(user_id,user_uid)
    and is_active;

  return v_result||jsonb_build_object('preparedAt',now());
end;
$$;

-- Make product totals robust and validate the actual persisted car states.
create or replace function public.erp_cloud_commercial_items_subtotal(
  p_company_id uuid,p_items jsonb,p_purchase boolean
) returns numeric
language plpgsql security definer set search_path=public as $$
declare
  v_item jsonb; v_type text; v_id text; v_description text;
  v_qty numeric; v_unit numeric; v_status text; v_subtotal numeric:=0;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  if coalesce(jsonb_typeof(p_items),'null')<>'array' or jsonb_array_length(p_items)=0 then
    raise exception 'يجب إضافة بند واحد على الأقل';
  end if;
  if exists(select 1 from jsonb_array_elements(p_items) x
            group by lower(coalesce(x->>'itemType','')),coalesce(x->>'itemId','') having count(*)>1) then
    raise exception 'لا يمكن تكرار البند نفسه داخل الأمر';
  end if;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_type:=lower(btrim(coalesce(v_item->>'itemType','')));
    v_id:=btrim(coalesce(v_item->>'itemId',''));
    v_description:=btrim(coalesce(v_item->>'description',''));
    v_qty:=public.erp_try_numeric(v_item->>'quantity',0);
    v_unit:=public.erp_try_numeric(v_item->>(case when p_purchase then 'unitCost' else 'unitPrice' end),-1);
    if v_type not in ('car','product') or v_id='' or v_description='' or v_qty<=0
       or v_qty<>trunc(v_qty) or v_unit<0 or (v_type='car' and v_qty<>1) then
      raise exception 'بيانات بند الأمر غير صحيحة: %',v_description;
    end if;

    if v_type='car' then
      select lower(btrim(coalesce(data->>'status',''))) into v_status
      from public.erp_cars where company_id=p_company_id and id=v_id and not is_deleted;
      if not found then raise exception 'السيارة المعرفة غير موجودة: %',v_description; end if;
      if p_purchase and v_status not in (
        'known','identified','defined','registered','purchase_pending','pending_purchase',
        'معرفة','معرّفة','مُعرفة','قيد الشراء','قيد شراء') then
        raise exception 'حالة السيارة لا تسمح بإضافتها إلى أمر شراء: %',v_description;
      end if;
      if not p_purchase and v_status not in ('available','متوفرة','متوفر','متاحة','selling','pending_sale','قيد البيع') then
        raise exception 'السيارة غير متاحة للبيع: %',v_description;
      end if;
    else
      perform 1 from public.erp_inventory
      where company_id=p_company_id and id=v_id and not is_deleted
        and public.erp_try_boolean(data->>'isActive',true);
      if not found then raise exception 'المنتج غير موجود أو غير فعال: %',v_description; end if;
    end if;
    v_subtotal:=v_subtotal+v_qty*v_unit;
  end loop;
  return round(v_subtotal,2);
end;
$$;


create or replace function public.erp_inventory_ensure_stock(
  p_company_id uuid,p_warehouse_id text,p_product_id text
) returns public.erp_warehouse_stock
language plpgsql security definer set search_path=public as $$
declare
  v_stock public.erp_warehouse_stock%rowtype;
  v_id text:=p_warehouse_id||'::'||p_product_id;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;

  select * into v_stock
  from public.erp_warehouse_stock
  where company_id=p_company_id and not is_deleted
    and data->>'warehouseId'=p_warehouse_id and data->>'productId'=p_product_id
  order by updated_at desc
  limit 1 for update;
  if found then return v_stock; end if;

  select * into v_stock
  from public.erp_warehouse_stock
  where company_id=p_company_id and id=v_id
  for update;
  if found then
    update public.erp_warehouse_stock
    set is_deleted=false,deleted_at=null,
        data=coalesce(data,'{}'::jsonb)||jsonb_build_object(
          'warehouseId',p_warehouse_id,'productId',p_product_id,
          'quantity',public.erp_try_numeric(data->>'quantity',0),
          'reservedQuantity',public.erp_try_numeric(data->>'reservedQuantity',0),
          'expectedIncoming',public.erp_try_numeric(data->>'expectedIncoming',0),
          'expectedOutgoing',public.erp_try_numeric(data->>'expectedOutgoing',0),
          'averageUnitCost',public.erp_try_numeric(data->>'averageUnitCost',0),
          'updatedAt',now()),
        updated_at=now(),updated_by=auth.uid()
    where company_id=p_company_id and id=v_id
    returning * into v_stock;
    return v_stock;
  end if;

  insert into public.erp_warehouse_stock(company_id,id,data,created_by,updated_by)
  values(p_company_id,v_id,jsonb_build_object(
    'warehouseId',p_warehouse_id,'productId',p_product_id,'quantity',0,
    'reservedQuantity',0,'expectedIncoming',0,'expectedOutgoing',0,
    'averageUnitCost',0,'updatedAt',now()
  ),auth.uid(),auth.uid())
  returning * into v_stock;
  return v_stock;
end;
$$;

-- Reserve/mark vehicles when orders are approved; release them on reopening.
create or replace function public.erp_approve_cloud_purchase_order(p_company_id uuid,p_order_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_order public.erp_purchase_orders_cloud%rowtype; r record; v_status text; v_owner text;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  select * into v_order from public.erp_purchase_orders_cloud
  where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found then raise exception 'أمر الشراء غير موجود'; end if;
  if v_order.status='approved' then return; end if;
  if v_order.status<>'draft' then raise exception 'حالة أمر الشراء لا تسمح بالتصديق'; end if;
  for r in select * from public.erp_purchase_order_items_cloud
           where company_id=p_company_id and order_id=p_order_id and not is_deleted and item_type='car' for update loop
    select lower(btrim(coalesce(data->>'status',''))),nullif(btrim(coalesce(data->>'purchaseOrderId','')),'')
      into v_status,v_owner
    from public.erp_cars where company_id=p_company_id and id=r.item_id and not is_deleted for update;
    if not found or v_status not in ('known','identified','defined','registered','معرفة','معرّفة','مُعرفة','purchase_pending','pending_purchase','قيد الشراء','قيد شراء') then
      raise exception 'السيارة % غير صالحة لأمر الشراء',r.description;
    end if;
    if v_owner is not null and v_owner<>p_order_id::text then
      raise exception 'السيارة % مرتبطة بأمر شراء آخر',r.description;
    end if;
    update public.erp_cars
    set data=data||jsonb_build_object('status','قيد الشراء','purchaseOrderId',p_order_id::text,'updatedAt',now()),
        updated_at=now(),updated_by=auth.uid()
    where company_id=p_company_id and id=r.item_id;
  end loop;
  update public.erp_purchase_orders_cloud set status='approved',updated_at=now() where id=p_order_id and company_id=p_company_id;
  perform public.erp_commercial_audit(p_company_id,'purchases',p_order_id,null,v_order.order_number,'approve_order','draft','approved',null);
end;
$$;

create or replace function public.erp_reopen_cloud_purchase_order(p_company_id uuid,p_order_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_order public.erp_purchase_orders_cloud%rowtype;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  select * into v_order from public.erp_purchase_orders_cloud where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found or v_order.status<>'approved' then raise exception 'يمكن إعادة فتح أمر شراء مصدق فقط'; end if;
  if exists(select 1 from public.erp_commercial_workflow_documents where company_id=p_company_id and parent_id=p_order_id and module='purchases' and not is_deleted and status<>'cancelled') then
    raise exception 'للأمر مستندات فعالة ولا يمكن إعادة فتحه';
  end if;
  update public.erp_cars c
  set data=(c.data-'purchaseOrderId')||jsonb_build_object('status','معرفة','updatedAt',now()),updated_at=now(),updated_by=auth.uid()
  where c.company_id=p_company_id and not c.is_deleted
    and c.data->>'purchaseOrderId'=p_order_id::text
    and lower(btrim(coalesce(c.data->>'status',''))) in ('purchase_pending','pending_purchase','قيد الشراء','قيد شراء')
    and nullif(btrim(coalesce(c.data->>'warehouseId',c.data->>'warehouse_id','')),'') is null
    and exists(select 1 from public.erp_purchase_order_items_cloud i where i.company_id=p_company_id and i.order_id=p_order_id and not i.is_deleted and i.item_type='car' and i.item_id=c.id);
  update public.erp_purchase_orders_cloud set status='draft',updated_at=now() where id=p_order_id and company_id=p_company_id;
  perform public.erp_commercial_audit(p_company_id,'purchases',p_order_id,null,v_order.order_number,'reopen_order','approved','draft',null);
end;
$$;

create or replace function public.erp_approve_cloud_sales_order(p_company_id uuid,p_order_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_order public.erp_sales_orders_cloud%rowtype; r record; v_status text; v_wh text; v_owner text;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  select * into v_order from public.erp_sales_orders_cloud where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found then raise exception 'أمر البيع غير موجود'; end if;
  if v_order.status='approved' then return; end if;
  if v_order.status<>'draft' then raise exception 'حالة أمر البيع لا تسمح بالتصديق'; end if;
  for r in select * from public.erp_sales_order_items_cloud
           where company_id=p_company_id and order_id=p_order_id and not is_deleted for update loop
    if r.item_type='car' then
      select lower(btrim(coalesce(data->>'status',''))),
             nullif(btrim(coalesce(data->>'warehouseId',data->>'warehouse_id','')),''),
             nullif(btrim(coalesce(data->>'salesOrderId','')),'')
        into v_status,v_wh,v_owner from public.erp_cars
      where company_id=p_company_id and id=r.item_id and not is_deleted for update;
      if not found or v_status not in ('available','متوفرة','متوفر','متاحة','selling','pending_sale','قيد البيع') or v_wh is null then
        raise exception 'السيارة % غير متاحة في مخزن للبيع',r.description;
      end if;
      if v_owner is not null and v_owner<>p_order_id::text then
        raise exception 'السيارة % مرتبطة بأمر بيع آخر',r.description;
      end if;
      update public.erp_cars
      set data=data||jsonb_build_object('status','قيد البيع','salesOrderId',p_order_id::text,'updatedAt',now()),
          updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and id=r.item_id;
    else
      if (select coalesce(sum(public.erp_try_numeric(data->>'quantity',0)),0) from public.erp_warehouse_stock where company_id=p_company_id and not is_deleted and data->>'productId'=r.item_id)<r.quantity then
        raise exception 'الرصيد الإجمالي للمنتج % غير كافٍ',r.description;
      end if;
    end if;
  end loop;
  update public.erp_sales_orders_cloud set status='approved',updated_at=now() where id=p_order_id and company_id=p_company_id;
  perform public.erp_commercial_audit(p_company_id,'sales',p_order_id,null,v_order.order_number,'approve_order','draft','approved',null);
end;
$$;

create or replace function public.erp_reopen_cloud_sales_order(p_company_id uuid,p_order_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_order public.erp_sales_orders_cloud%rowtype;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  select * into v_order from public.erp_sales_orders_cloud where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found or v_order.status<>'approved' then raise exception 'يمكن إعادة فتح أمر بيع مصدق فقط'; end if;
  if exists(select 1 from public.erp_commercial_workflow_documents where company_id=p_company_id and parent_id=p_order_id and module='sales' and not is_deleted and status<>'cancelled') then
    raise exception 'للأمر مستندات فعالة ولا يمكن إعادة فتحه';
  end if;
  update public.erp_cars c
  set data=(c.data-'salesOrderId')||jsonb_build_object('status','متوفرة','updatedAt',now()),updated_at=now(),updated_by=auth.uid()
  where c.company_id=p_company_id and not c.is_deleted
    and c.data->>'salesOrderId'=p_order_id::text
    and lower(btrim(coalesce(c.data->>'status',''))) in ('selling','pending_sale','قيد البيع')
    and exists(select 1 from public.erp_sales_order_items_cloud i where i.company_id=p_company_id and i.order_id=p_order_id and not i.is_deleted and i.item_type='car' and i.item_id=c.id);
  update public.erp_sales_orders_cloud set status='draft',updated_at=now() where id=p_order_id and company_id=p_company_id;
  perform public.erp_commercial_audit(p_company_id,'sales',p_order_id,null,v_order.order_number,'reopen_order','approved','draft',null);
end;
$$;

-- ---------------------------------------------------------------------------
-- Inventory posting for receipts and deliveries.
-- ---------------------------------------------------------------------------
create or replace function public.erp_inventory_refresh_product(p_company_id uuid,p_product_id text)
returns void language plpgsql security definer set search_path=public as $$
declare v_qty numeric; v_value numeric; v_in numeric; v_out numeric; v_old numeric;
begin
  select coalesce(sum(public.erp_try_numeric(data->>'quantity',0)),0),
         coalesce(sum(public.erp_try_numeric(data->>'quantity',0)*public.erp_try_numeric(data->>'averageUnitCost',0)),0),
         coalesce(sum(public.erp_try_numeric(data->>'expectedIncoming',0)),0),
         coalesce(sum(public.erp_try_numeric(data->>'expectedOutgoing',0)),0)
    into v_qty,v_value,v_in,v_out
  from public.erp_warehouse_stock
  where company_id=p_company_id and not is_deleted and data->>'productId'=p_product_id;
  select public.erp_try_numeric(data->>'unitCost',0) into v_old
  from public.erp_inventory where company_id=p_company_id and id=p_product_id and not is_deleted;
  update public.erp_inventory
  set data=data||jsonb_build_object(
    'quantity',trunc(v_qty)::int,'expectedIncoming',trunc(v_in)::int,'expectedOutgoing',trunc(v_out)::int,
    'unitCost',case when v_qty>0 then round(v_value/v_qty,4) else coalesce(v_old,0) end,
    'updatedAt',now()
  ),updated_at=now(),updated_by=auth.uid()
  where company_id=p_company_id and id=p_product_id and not is_deleted;
end;
$$;

create or replace function public.erp_create_cloud_sales_delivery(
  p_company_id uuid,p_order_id uuid,p_warehouse_id text default null,p_notes text default null
) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_id uuid:=gen_random_uuid(); v_number text;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  if nullif(btrim(coalesce(p_warehouse_id,'')),'') is null then raise exception 'يجب اختيار المخزن'; end if;
  perform 1 from public.erp_sales_orders_cloud
  where company_id=p_company_id and id=p_order_id and status='approved' and not is_deleted for update;
  if not found then raise exception 'أمر بيع مصدق غير موجود'; end if;
  perform 1 from public.erp_warehouses
  where company_id=p_company_id and id=p_warehouse_id and not is_deleted
    and public.erp_try_boolean(data->>'isActive',true);
  if not found then raise exception 'المخزن غير موجود أو غير فعال'; end if;
  if exists(select 1 from public.erp_commercial_workflow_documents
            where company_id=p_company_id and parent_id=p_order_id and module='sales'
              and document_type='delivery' and not is_deleted and status<>'cancelled') then
    raise exception 'يوجد أمر تجهيز فعال لهذا الأمر';
  end if;
  v_number:='SD-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');
  insert into public.erp_commercial_workflow_documents(
    id,company_id,module,document_type,parent_id,document_number,warehouse_id,payload
  ) values(v_id,p_company_id,'sales','delivery',p_order_id,v_number,p_warehouse_id,
           jsonb_build_object('notes',p_notes,'createdBy',auth.uid()));
  perform public.erp_commercial_audit(p_company_id,'sales',p_order_id,v_id,v_number,'create_delivery',null,'draft',null);
  return v_id;
end;
$$;

create or replace function public.erp_create_cloud_purchase_receipt(
  p_company_id uuid,p_order_id uuid,p_warehouse_id text default null,p_notes text default null
) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_id uuid:=gen_random_uuid(); v_number text;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  if nullif(btrim(coalesce(p_warehouse_id,'')),'') is null then raise exception 'يجب اختيار المخزن'; end if;
  perform 1 from public.erp_purchase_orders_cloud
  where company_id=p_company_id and id=p_order_id and status='approved' and not is_deleted for update;
  if not found then raise exception 'أمر شراء مصدق غير موجود'; end if;
  perform 1 from public.erp_warehouses
  where company_id=p_company_id and id=p_warehouse_id and not is_deleted
    and public.erp_try_boolean(data->>'isActive',true);
  if not found then raise exception 'المخزن غير موجود أو غير فعال'; end if;
  if exists(select 1 from public.erp_commercial_workflow_documents
            where company_id=p_company_id and parent_id=p_order_id and module='purchases'
              and document_type='receipt' and not is_deleted and status<>'cancelled') then
    raise exception 'يوجد أمر استلام فعال لهذا الأمر';
  end if;
  v_number:='PR-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');
  insert into public.erp_commercial_workflow_documents(
    id,company_id,module,document_type,parent_id,document_number,warehouse_id,payload
  ) values(v_id,p_company_id,'purchases','receipt',p_order_id,v_number,p_warehouse_id,
           jsonb_build_object('notes',p_notes,'createdBy',auth.uid()));
  perform public.erp_commercial_audit(p_company_id,'purchases',p_order_id,v_id,v_number,'create_receipt',null,'draft',null);
  return v_id;
end;
$$;

create or replace function public.erp_approve_cloud_purchase_receipt(p_company_id uuid,p_receipt_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare
  v_doc public.erp_commercial_workflow_documents%rowtype;
  v_stock public.erp_warehouse_stock%rowtype;
  r record; v_qty numeric; v_avg numeric; v_new_avg numeric;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  select * into v_doc from public.erp_commercial_workflow_documents
  where company_id=p_company_id and id=p_receipt_id and module='purchases' and document_type='receipt' and not is_deleted for update;
  if not found then raise exception 'أمر الاستلام غير موجود'; end if;
  if v_doc.status='cancelled' then raise exception 'أمر الاستلام ملغي'; end if;
  if v_doc.payload ? 'inventoryPostedAt' then return; end if;
  perform 1 from public.erp_warehouses where company_id=p_company_id and id=v_doc.warehouse_id and not is_deleted and public.erp_try_boolean(data->>'isActive',true);
  if not found then raise exception 'أمر الاستلام غير مرتبط بمخزن فعال'; end if;

  for r in select * from public.erp_purchase_order_items_cloud
           where company_id=p_company_id and order_id=v_doc.parent_id and not is_deleted order by id for update loop
    if r.item_type='product' then
      v_stock:=public.erp_inventory_ensure_stock(p_company_id,v_doc.warehouse_id,r.item_id);
      v_qty:=public.erp_try_numeric(v_stock.data->>'quantity',0);
      v_avg:=public.erp_try_numeric(v_stock.data->>'averageUnitCost',0);
      v_new_avg:=case when v_qty+r.quantity>0 then ((v_qty*v_avg)+(r.quantity*r.unit_cost))/(v_qty+r.quantity) else r.unit_cost end;
      update public.erp_warehouse_stock
      set data=data||jsonb_build_object('quantity',v_qty+r.quantity,'averageUnitCost',round(v_new_avg,4),'updatedAt',now()),
          updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and id=v_stock.id;
      perform public.erp_inventory_insert_movement(p_company_id,r.item_id,v_doc.warehouse_id,'purchase_in',r.quantity,r.unit_cost,'purchase_receipt',v_doc.id::text,v_doc.document_number);
      perform public.erp_inventory_refresh_product(p_company_id,r.item_id);
    else
      perform 1 from public.erp_cars where company_id=p_company_id and id=r.item_id and not is_deleted for update;
      if not found then raise exception 'السيارة % لم تعد موجودة',r.description; end if;
      if lower(btrim(coalesce((select data->>'status' from public.erp_cars where company_id=p_company_id and id=r.item_id),''))) not in
         ('known','identified','defined','registered','purchase_pending','pending_purchase','معرفة','معرّفة','مُعرفة','قيد الشراء','قيد شراء') then
        raise exception 'حالة السيارة % لا تسمح باستلامها',r.description;
      end if;
      update public.erp_cars
      set data=(data-'purchaseOrderId')||jsonb_build_object(
            'status','متوفرة','warehouseId',v_doc.warehouse_id,'purchasePrice',r.unit_cost,
            'receivedAt',now(),'purchaseReceiptId',v_doc.id::text,'sourcePurchaseOrderId',v_doc.parent_id::text,'updatedAt',now()),
          updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and id=r.item_id;
    end if;
  end loop;

  update public.erp_commercial_workflow_documents
  set status='approved',payload=payload||jsonb_build_object('inventoryPostedAt',now(),'inventoryPostedBy',auth.uid()),updated_at=now()
  where company_id=p_company_id and id=p_receipt_id;
  perform public.erp_commercial_audit(p_company_id,'purchases',v_doc.parent_id,v_doc.id,v_doc.document_number,'approve_receipt',v_doc.status,'approved',null);
end;
$$;

create or replace function public.erp_approve_cloud_sales_delivery(p_company_id uuid,p_delivery_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare
  v_doc public.erp_commercial_workflow_documents%rowtype;
  v_stock public.erp_warehouse_stock%rowtype;
  r record; v_available numeric; v_cost numeric; v_total_cost numeric:=0;
  v_entry_id text; v_inventory_account text; v_cogs_account text;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  select * into v_doc from public.erp_commercial_workflow_documents
  where company_id=p_company_id and id=p_delivery_id and module='sales' and document_type='delivery' and not is_deleted for update;
  if not found then raise exception 'أمر التجهيز غير موجود'; end if;
  if v_doc.status='cancelled' then raise exception 'أمر التجهيز ملغي'; end if;
  if v_doc.payload ? 'inventoryPostedAt' then return; end if;
  if nullif(btrim(coalesce(v_doc.warehouse_id,'')),'') is null then raise exception 'أمر التجهيز بدون مخزن'; end if;
  perform 1 from public.erp_warehouses where company_id=p_company_id and id=v_doc.warehouse_id and not is_deleted and public.erp_try_boolean(data->>'isActive',true);
  if not found then raise exception 'المخزن غير موجود أو غير فعال'; end if;

  for r in select * from public.erp_sales_order_items_cloud
           where company_id=p_company_id and order_id=v_doc.parent_id and not is_deleted order by id for update loop
    if r.item_type='product' then
      v_stock:=public.erp_inventory_ensure_stock(p_company_id,v_doc.warehouse_id,r.item_id);
      v_available:=public.erp_try_numeric(v_stock.data->>'quantity',0);
      v_cost:=public.erp_try_numeric(v_stock.data->>'averageUnitCost',0);
      if v_available<r.quantity then raise exception 'الرصيد في المخزن غير كافٍ للمنتج %',r.description; end if;
      update public.erp_warehouse_stock
      set data=data||jsonb_build_object('quantity',v_available-r.quantity,'updatedAt',now()),updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and id=v_stock.id;
      perform public.erp_inventory_insert_movement(p_company_id,r.item_id,v_doc.warehouse_id,'sale_out',-r.quantity,v_cost,'sales_delivery',v_doc.id::text,v_doc.document_number);
      perform public.erp_inventory_refresh_product(p_company_id,r.item_id);
      v_total_cost:=v_total_cost+r.quantity*v_cost;
    else
      perform 1 from public.erp_cars
      where company_id=p_company_id and id=r.item_id and not is_deleted
        and nullif(btrim(coalesce(data->>'warehouseId',data->>'warehouse_id','')),'')=v_doc.warehouse_id
        and lower(btrim(coalesce(data->>'status',''))) in ('available','متوفرة','متوفر','متاحة','selling','pending_sale','قيد البيع')
      for update;
      if not found then raise exception 'السيارة % غير موجودة في مخزن التجهيز أو ليست متاحة',r.description; end if;
      v_cost:=coalesce((select public.erp_try_numeric(data->>'purchasePrice',null) from public.erp_cars where company_id=p_company_id and id=r.item_id),
                       (select public.erp_try_numeric(data->>'costPrice',0) from public.erp_cars where company_id=p_company_id and id=r.item_id),0);
      v_total_cost:=v_total_cost+v_cost;
      update public.erp_cars
      set data=(data-'warehouseId'-'warehouse_id')||jsonb_build_object(
            'status','قيد البيع','salesOrderId',v_doc.parent_id::text,
            'lastWarehouseId',v_doc.warehouse_id,'deliveredAt',now(),
            'salesDeliveryId',v_doc.id::text,'sourceSalesOrderId',v_doc.parent_id::text,'updatedAt',now()),
          updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and id=r.item_id;
    end if;
  end loop;

  if v_total_cost>0 then
    select account_id into v_inventory_account from public.erp_accounts where organization_id=p_company_id and code='1300' and is_active limit 1;
    select account_id into v_cogs_account from public.erp_accounts where organization_id=p_company_id and code='5100' and is_active limit 1;
    if v_inventory_account is null or v_cogs_account is null then raise exception 'حسابات المخزون أو تكلفة المبيعات غير مهيأة'; end if;
    v_entry_id:=gen_random_uuid()::text;
    insert into public.erp_journal_entries(company_id,id,data,created_by,updated_by)
    values(p_company_id,v_entry_id,jsonb_build_object(
      'id',v_entry_id,'entryNumber','COGS-'||replace(v_doc.id::text,'-',''),'entryDate',now(),
      'description','تكلفة تجهيز '||v_doc.document_number,'currency','USD','referenceType','workflow_delivery_cost',
      'referenceId',v_doc.id::text,'orderId',v_doc.parent_id::text,'status','posted',
      'totalDebit',v_total_cost,'totalCredit',v_total_cost,'createdAt',now()),auth.uid(),auth.uid());
    insert into public.erp_journal_lines(company_id,id,data,created_by,updated_by) values
    (p_company_id,gen_random_uuid()::text,jsonb_build_object('entryId',v_entry_id,'accountId',v_cogs_account,'debit',v_total_cost,'credit',0,'description','تكلفة البضاعة المباعة'),auth.uid(),auth.uid()),
    (p_company_id,gen_random_uuid()::text,jsonb_build_object('entryId',v_entry_id,'accountId',v_inventory_account,'debit',0,'credit',v_total_cost,'description','إخراج من المخزون'),auth.uid(),auth.uid());
  end if;

  update public.erp_commercial_workflow_documents
  set status='approved',payload=payload||jsonb_build_object('inventoryPostedAt',now(),'inventoryPostedBy',auth.uid(),'costJournalEntryId',v_entry_id,'totalCost',v_total_cost),updated_at=now()
  where company_id=p_company_id and id=p_delivery_id;
  perform public.erp_commercial_audit(p_company_id,'sales',v_doc.parent_id,v_doc.id,v_doc.document_number,'approve_delivery',v_doc.status,'approved',null);
end;
$$;

create or replace function public.erp_cancel_cloud_purchase_receipt(p_company_id uuid,p_receipt_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_doc public.erp_commercial_workflow_documents%rowtype; v_stock public.erp_warehouse_stock%rowtype; r record; v_qty numeric;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  select * into v_doc from public.erp_commercial_workflow_documents where company_id=p_company_id and id=p_receipt_id and module='purchases' and document_type='receipt' and not is_deleted for update;
  if not found then raise exception 'أمر الاستلام غير موجود'; end if;
  if v_doc.status='cancelled' then return; end if;
  if exists(select 1 from public.erp_commercial_workflow_documents where company_id=p_company_id and parent_id=v_doc.parent_id and module='purchases' and document_type='invoice' and not is_deleted and status<>'cancelled') then
    raise exception 'لا يمكن إلغاء الاستلام لوجود فاتورة فعالة';
  end if;
  if v_doc.payload ? 'inventoryPostedAt' and not (v_doc.payload ? 'inventoryReversedAt') then
    for r in select * from public.erp_purchase_order_items_cloud where company_id=p_company_id and order_id=v_doc.parent_id and not is_deleted order by id for update loop
      if r.item_type='product' then
        v_stock:=public.erp_inventory_ensure_stock(p_company_id,v_doc.warehouse_id,r.item_id);
        v_qty:=public.erp_try_numeric(v_stock.data->>'quantity',0);
        if v_qty<r.quantity then raise exception 'لا يمكن عكس الاستلام لأن رصيد المنتج % تم استخدامه',r.description; end if;
        update public.erp_warehouse_stock set data=data||jsonb_build_object('quantity',v_qty-r.quantity,'updatedAt',now()),updated_at=now(),updated_by=auth.uid() where company_id=p_company_id and id=v_stock.id;
        perform public.erp_inventory_insert_movement(p_company_id,r.item_id,v_doc.warehouse_id,'purchase_receipt_reversal',-r.quantity,r.unit_cost,'purchase_receipt_cancel',v_doc.id::text,v_doc.document_number);
        perform public.erp_inventory_refresh_product(p_company_id,r.item_id);
      else
        perform 1 from public.erp_cars where company_id=p_company_id and id=r.item_id and not is_deleted
          and lower(btrim(coalesce(data->>'status',''))) in ('available','متوفرة','متوفر','متاحة')
          and coalesce(data->>'warehouseId',data->>'warehouse_id')=v_doc.warehouse_id for update;
        if not found then raise exception 'لا يمكن عكس استلام السيارة % بعد تحريكها أو بيعها',r.description; end if;
        update public.erp_cars set data=(data-'warehouseId'-'warehouse_id')||jsonb_build_object('status','قيد الشراء','purchaseOrderId',v_doc.parent_id::text,'updatedAt',now()),updated_at=now(),updated_by=auth.uid()
        where company_id=p_company_id and id=r.item_id;
      end if;
    end loop;
  end if;
  update public.erp_commercial_workflow_documents set status='cancelled',payload=payload||jsonb_build_object('inventoryReversedAt',now(),'cancelledAt',now()),updated_at=now() where company_id=p_company_id and id=p_receipt_id;
  perform public.erp_commercial_audit(p_company_id,'purchases',v_doc.parent_id,v_doc.id,v_doc.document_number,'cancel_receipt',v_doc.status,'cancelled',null);
end;
$$;

create or replace function public.erp_cancel_cloud_sales_delivery(p_company_id uuid,p_delivery_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_doc public.erp_commercial_workflow_documents%rowtype; v_stock public.erp_warehouse_stock%rowtype; r record; v_qty numeric; v_cost numeric; v_journal text;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  select * into v_doc from public.erp_commercial_workflow_documents where company_id=p_company_id and id=p_delivery_id and module='sales' and document_type='delivery' and not is_deleted for update;
  if not found then raise exception 'أمر التجهيز غير موجود'; end if;
  if v_doc.status='cancelled' then return; end if;
  if exists(select 1 from public.erp_commercial_workflow_documents where company_id=p_company_id and parent_id=v_doc.parent_id and module='sales' and document_type='invoice' and not is_deleted and status<>'cancelled') then
    raise exception 'لا يمكن إلغاء التجهيز لوجود فاتورة فعالة';
  end if;
  if v_doc.payload ? 'inventoryPostedAt' and not (v_doc.payload ? 'inventoryReversedAt') then
    for r in select * from public.erp_sales_order_items_cloud where company_id=p_company_id and order_id=v_doc.parent_id and not is_deleted order by id for update loop
      if r.item_type='product' then
        v_stock:=public.erp_inventory_ensure_stock(p_company_id,v_doc.warehouse_id,r.item_id);
        v_qty:=public.erp_try_numeric(v_stock.data->>'quantity',0);
        v_cost:=public.erp_try_numeric(v_stock.data->>'averageUnitCost',0);
        update public.erp_warehouse_stock set data=data||jsonb_build_object('quantity',v_qty+r.quantity,'updatedAt',now()),updated_at=now(),updated_by=auth.uid() where company_id=p_company_id and id=v_stock.id;
        perform public.erp_inventory_insert_movement(p_company_id,r.item_id,v_doc.warehouse_id,'sales_delivery_reversal',r.quantity,v_cost,'sales_delivery_cancel',v_doc.id::text,v_doc.document_number);
        perform public.erp_inventory_refresh_product(p_company_id,r.item_id);
      else
        perform 1 from public.erp_cars
        where company_id=p_company_id and id=r.item_id and not is_deleted
          and lower(btrim(coalesce(data->>'status',''))) in ('selling','pending_sale','قيد البيع')
          and data->>'salesDeliveryId'=v_doc.id::text
        for update;
        if not found then raise exception 'لا يمكن عكس تجهيز السيارة % لأن حالتها تغيرت أو تم تصديق فاتورتها',r.description; end if;
        update public.erp_cars
        set data=(data-'salesDeliveryId'-'deliveredAt'-'lastWarehouseId')||jsonb_build_object(
              'status','قيد البيع','warehouseId',v_doc.warehouse_id,
              'salesOrderId',v_doc.parent_id::text,'updatedAt',now()),
            updated_at=now(),updated_by=auth.uid()
        where company_id=p_company_id and id=r.item_id;
      end if;
    end loop;
    v_journal:=nullif(v_doc.payload->>'costJournalEntryId','');
    if v_journal is not null then
      update public.erp_journal_lines set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid() where company_id=p_company_id and not is_deleted and data->>'entryId'=v_journal;
      update public.erp_journal_entries set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid() where company_id=p_company_id and id=v_journal and not is_deleted;
    end if;
  end if;
  update public.erp_commercial_workflow_documents set status='cancelled',payload=payload||jsonb_build_object('inventoryReversedAt',now(),'cancelledAt',now()),updated_at=now() where company_id=p_company_id and id=p_delivery_id;
  perform public.erp_commercial_audit(p_company_id,'sales',v_doc.parent_id,v_doc.id,v_doc.document_number,'cancel_delivery',v_doc.status,'cancelled',null);
end;
$$;

-- ---------------------------------------------------------------------------
-- Invoice accounting and cash settlement.
-- ---------------------------------------------------------------------------
create or replace function public.erp_ensure_workflow_accounts(p_company_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare
  v_revenue_parent text; v_expense_parent text;
  v_gain_id text:='workflow-fx-gain-'||substr(md5(p_company_id::text),1,12);
  v_loss_id text:='workflow-fx-loss-'||substr(md5(p_company_id::text),1,12);
begin
  perform public.erp_seed_default_accounts(p_company_id);
  select account_id into v_revenue_parent from public.erp_accounts where organization_id=p_company_id and code='4000' limit 1;
  select account_id into v_expense_parent from public.erp_accounts where organization_id=p_company_id and code='5000' limit 1;
  insert into public.erp_accounts(organization_id,account_id,code,name,account_type,parent_account_id,currency,opening_balance,is_active,source_updated_at,synced_at,synced_by)
  values(p_company_id,v_gain_id,'4200','أرباح فروقات الصرف','revenue',v_revenue_parent,'MULTI',0,true,now(),now(),auth.uid())
  on conflict(organization_id,code) do update set name=excluded.name,parent_account_id=excluded.parent_account_id,is_active=true,synced_at=now(),synced_by=auth.uid();
  insert into public.erp_accounts(organization_id,account_id,code,name,account_type,parent_account_id,currency,opening_balance,is_active,source_updated_at,synced_at,synced_by)
  values(p_company_id,v_loss_id,'5300','خسائر فروقات الصرف','expense',v_expense_parent,'MULTI',0,true,now(),now(),auth.uid())
  on conflict(organization_id,code) do update set name=excluded.name,parent_account_id=excluded.parent_account_id,is_active=true,synced_at=now(),synced_by=auth.uid();
end;
$$;

create or replace function public.erp_workflow_partner_account(
  p_company_id uuid,p_partner_type text,p_partner_id text,p_currency text
) returns text language plpgsql security definer set search_path=public as $$
declare v_id text; v_parent text; v_name text; v_code text; v_account_type text;
begin
  select case when upper(p_currency)='IQD' then coalesce(iqd_account_id,usd_account_id) else coalesce(usd_account_id,iqd_account_id) end
    into v_id from public.erp_partner_accounts
  where organization_id=p_company_id and partner_type=p_partner_type and partner_id=p_partner_id and is_active limit 1;
  if v_id is not null and exists(select 1 from public.erp_accounts where organization_id=p_company_id and account_id=v_id and is_active) then
    return v_id;
  end if;

  perform public.erp_seed_default_accounts(p_company_id);
  if p_partner_type='customer' then
    select account_id into v_parent from public.erp_accounts where organization_id=p_company_id and code='1400' and is_active limit 1;
    select coalesce(data->>'name',p_partner_id) into v_name from public.erp_customers where company_id=p_company_id and id=p_partner_id and not is_deleted;
    v_account_type:='asset'; v_code:='14-'||upper(substr(md5(p_partner_id),1,8));
  elsif p_partner_type='supplier' then
    select account_id into v_parent from public.erp_accounts where organization_id=p_company_id and code='2100' and is_active limit 1;
    select coalesce(data->>'name',p_partner_id) into v_name from public.erp_suppliers where company_id=p_company_id and id=p_partner_id and not is_deleted;
    v_account_type:='liability'; v_code:='21-'||upper(substr(md5(p_partner_id),1,8));
  else
    raise exception 'invalid partner type';
  end if;
  if v_parent is null or v_name is null then raise exception 'حساب الطرف أو بياناته غير متاحة'; end if;
  v_id:='partner-'||p_partner_type||'-'||substr(md5(p_partner_id),1,20);
  insert into public.erp_accounts(organization_id,account_id,code,name,account_type,parent_account_id,currency,opening_balance,is_active,source_updated_at,synced_at,synced_by)
  values(p_company_id,v_id,v_code,(case when p_partner_type='customer' then 'العميل ' else 'المورد ' end)||v_name,v_account_type,v_parent,'MULTI',0,true,now(),now(),auth.uid())
  on conflict(organization_id,account_id) do update set name=excluded.name,is_active=true,synced_at=now(),synced_by=auth.uid();
  insert into public.erp_partner_accounts(organization_id,partner_type,partner_id,partner_name,usd_account_id,iqd_account_id,is_active,source_updated_at,synced_at,synced_by)
  values(p_company_id,p_partner_type,p_partner_id,v_name,v_id,v_id,true,now(),now(),auth.uid())
  on conflict(organization_id,partner_type,partner_id) do update set partner_name=excluded.partner_name,usd_account_id=v_id,iqd_account_id=v_id,is_active=true,synced_at=now(),synced_by=auth.uid();
  return v_id;
end;
$$;

create or replace function public.erp_create_cloud_sales_workflow_invoice(p_company_id uuid,p_order_id uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid:=gen_random_uuid(); v_total numeric; v_currency text; v_number text;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  select total,currency into v_total,v_currency from public.erp_sales_orders_cloud
  where company_id=p_company_id and id=p_order_id and status='approved' and not is_deleted for update;
  if not found then raise exception 'أمر البيع المصدق غير موجود'; end if;
  if not exists(select 1 from public.erp_commercial_workflow_documents where company_id=p_company_id and parent_id=p_order_id and module='sales' and document_type='delivery' and status='approved' and not is_deleted and payload ? 'inventoryPostedAt') then
    raise exception 'يجب تصديق أمر التجهيز وترحيله مخزنيًا أولاً';
  end if;
  if exists(select 1 from public.erp_commercial_workflow_documents where company_id=p_company_id and parent_id=p_order_id and module='sales' and document_type='invoice' and not is_deleted and status<>'cancelled') then
    raise exception 'توجد فاتورة بيع فعالة لهذا الأمر';
  end if;
  v_number:='SI-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');
  insert into public.erp_commercial_workflow_documents(id,company_id,module,document_type,parent_id,document_number,warehouse_id,payload)
  values(v_id,p_company_id,'sales','invoice',p_order_id,v_number,null,jsonb_build_object(
    'currency',v_currency,'totalAmount',v_total,'paidAmount',0,'remainingAmount',v_total,
    'paymentStatus','unpaid','payments','[]'::jsonb,'createdBy',auth.uid()));
  perform public.erp_commercial_audit(p_company_id,'sales',p_order_id,v_id,v_number,'create_invoice',null,'draft',null);
  return v_id;
end;
$$;

create or replace function public.erp_create_cloud_purchase_workflow_invoice(p_company_id uuid,p_order_id uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid:=gen_random_uuid(); v_total numeric; v_currency text; v_number text;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  select total,currency into v_total,v_currency from public.erp_purchase_orders_cloud
  where company_id=p_company_id and id=p_order_id and status='approved' and not is_deleted for update;
  if not found then raise exception 'أمر الشراء المصدق غير موجود'; end if;
  if not exists(select 1 from public.erp_commercial_workflow_documents where company_id=p_company_id and parent_id=p_order_id and module='purchases' and document_type='receipt' and status='approved' and not is_deleted and payload ? 'inventoryPostedAt') then
    raise exception 'يجب تصديق أمر الاستلام وترحيله مخزنيًا أولاً';
  end if;
  if exists(select 1 from public.erp_commercial_workflow_documents where company_id=p_company_id and parent_id=p_order_id and module='purchases' and document_type='invoice' and not is_deleted and status<>'cancelled') then
    raise exception 'توجد فاتورة شراء فعالة لهذا الأمر';
  end if;
  v_number:='PI-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');
  insert into public.erp_commercial_workflow_documents(id,company_id,module,document_type,parent_id,document_number,warehouse_id,payload)
  values(v_id,p_company_id,'purchases','invoice',p_order_id,v_number,null,jsonb_build_object(
    'currency',v_currency,'totalAmount',v_total,'paidAmount',0,'remainingAmount',v_total,
    'paymentStatus','unpaid','payments','[]'::jsonb,'createdBy',auth.uid()));
  perform public.erp_commercial_audit(p_company_id,'purchases',p_order_id,v_id,v_number,'create_invoice',null,'draft',null);
  return v_id;
end;
$$;

create or replace function public.erp_mark_sales_order_cars_sold(
  p_company_id uuid,p_order_id uuid,p_invoice_id uuid
) returns void language plpgsql security definer set search_path=public as $$
begin
  update public.erp_cars c
  set data=(c.data-'salesOrderId')||jsonb_build_object(
        'status','مباعة','soldAt',coalesce(public.erp_try_timestamptz(c.data->>'soldAt',null),now()),
        'salesInvoiceId',p_invoice_id::text,'sourceSalesOrderId',p_order_id::text,'updatedAt',now()),
      updated_at=now(),updated_by=auth.uid()
  where c.company_id=p_company_id and not c.is_deleted
    and lower(btrim(coalesce(c.data->>'status',''))) in ('selling','pending_sale','قيد البيع','sold','مباعة','مباع')
    and exists(
      select 1
      from public.erp_sales_order_items_cloud i
      join public.erp_commercial_workflow_documents d
        on d.company_id=i.company_id and d.parent_id=i.order_id
       and d.module='sales' and d.document_type='delivery'
       and d.status='approved' and not d.is_deleted and d.payload ? 'inventoryPostedAt'
      where i.company_id=p_company_id and i.order_id=p_order_id
        and not i.is_deleted and i.item_type='car' and i.item_id=c.id
        and c.data->>'salesDeliveryId'=d.id::text
    );
end;
$$;

create or replace function public.erp_restore_sales_order_cars_after_invoice_cancel(
  p_company_id uuid,p_order_id uuid,p_invoice_id uuid
) returns void language plpgsql security definer set search_path=public as $$
begin
  update public.erp_cars c
  set data=(c.data-'salesInvoiceId'-'soldAt')||jsonb_build_object(
        'status','قيد البيع','salesOrderId',p_order_id::text,'updatedAt',now()),
      updated_at=now(),updated_by=auth.uid()
  where c.company_id=p_company_id and not c.is_deleted
    and c.data->>'salesInvoiceId'=p_invoice_id::text
    and lower(btrim(coalesce(c.data->>'status',''))) in ('sold','مباعة','مباع')
    and exists(
      select 1 from public.erp_sales_order_items_cloud i
      where i.company_id=p_company_id and i.order_id=p_order_id
        and not i.is_deleted and i.item_type='car' and i.item_id=c.id
    );
end;
$$;

create or replace function public.erp_approve_cloud_workflow_invoice(
  p_company_id uuid,p_invoice_id uuid,p_module text
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_doc public.erp_commercial_workflow_documents%rowtype;
  v_total numeric; v_currency text; v_partner_id text; v_partner_type text;
  v_partner_account text; v_counter_account text; v_entry_id text;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  if p_module not in ('sales','purchases') then raise exception 'invalid workflow module'; end if;
  select * into v_doc from public.erp_commercial_workflow_documents
  where company_id=p_company_id and id=p_invoice_id and module=p_module and document_type='invoice' and not is_deleted for update;
  if not found then raise exception 'الفاتورة غير موجودة'; end if;
  if v_doc.status='approved' and nullif(v_doc.payload->>'journalEntryId','') is not null then
    if p_module='sales' then
      perform public.erp_mark_sales_order_cars_sold(p_company_id,v_doc.parent_id,p_invoice_id);
    end if;
    return;
  end if;
  if v_doc.status not in ('draft','approved') then raise exception 'حالة الفاتورة لا تسمح بالتصديق'; end if;
  v_total:=public.erp_try_numeric(v_doc.payload->>'totalAmount',0);
  v_currency:=upper(coalesce(v_doc.payload->>'currency',''));
  if v_total<=0 or v_currency not in ('USD','IQD') then raise exception 'قيمة أو عملة الفاتورة غير صحيحة'; end if;
  perform public.erp_ensure_workflow_accounts(p_company_id);

  if p_module='sales' then
    select customer_id into v_partner_id from public.erp_sales_orders_cloud where company_id=p_company_id and id=v_doc.parent_id and not is_deleted;
    v_partner_type:='customer';
    select account_id into v_counter_account from public.erp_accounts where organization_id=p_company_id and code='4100' and is_active limit 1;
  else
    select supplier_id into v_partner_id from public.erp_purchase_orders_cloud where company_id=p_company_id and id=v_doc.parent_id and not is_deleted;
    v_partner_type:='supplier';
    select account_id into v_counter_account from public.erp_accounts where organization_id=p_company_id and code='1300' and is_active limit 1;
  end if;
  if v_partner_id is null or v_counter_account is null then raise exception 'الحسابات أو الطرف المرتبط بالفاتورة غير مكتمل'; end if;
  v_partner_account:=public.erp_workflow_partner_account(p_company_id,v_partner_type,v_partner_id,v_currency);
  v_entry_id:=gen_random_uuid()::text;

  insert into public.erp_journal_entries(company_id,id,data,created_by,updated_by)
  values(p_company_id,v_entry_id,jsonb_build_object(
    'id',v_entry_id,'entryNumber',(case when p_module='sales' then 'SINV-' else 'PINV-' end)||replace(v_doc.id::text,'-',''),
    'entryDate',now(),'description',(case when p_module='sales' then 'فاتورة بيع ' else 'فاتورة شراء ' end)||v_doc.document_number,
    'currency',v_currency,'referenceType','workflow_invoice','referenceId',v_doc.id::text,'orderId',v_doc.parent_id::text,
    'totalDebit',v_total,'totalCredit',v_total,'status','posted','createdAt',now()),auth.uid(),auth.uid());
  if p_module='sales' then
    insert into public.erp_journal_lines(company_id,id,data,created_by,updated_by) values
    (p_company_id,gen_random_uuid()::text,jsonb_build_object('entryId',v_entry_id,'accountId',v_partner_account,'debit',v_total,'credit',0,'description','ذمة العميل'),auth.uid(),auth.uid()),
    (p_company_id,gen_random_uuid()::text,jsonb_build_object('entryId',v_entry_id,'accountId',v_counter_account,'debit',0,'credit',v_total,'description','إيراد المبيعات'),auth.uid(),auth.uid());
  else
    insert into public.erp_journal_lines(company_id,id,data,created_by,updated_by) values
    (p_company_id,gen_random_uuid()::text,jsonb_build_object('entryId',v_entry_id,'accountId',v_counter_account,'debit',v_total,'credit',0,'description','المخزون المستلم'),auth.uid(),auth.uid()),
    (p_company_id,gen_random_uuid()::text,jsonb_build_object('entryId',v_entry_id,'accountId',v_partner_account,'debit',0,'credit',v_total,'description','ذمة المورد'),auth.uid(),auth.uid());
  end if;
  if p_module='sales' then
    perform public.erp_mark_sales_order_cars_sold(p_company_id,v_doc.parent_id,p_invoice_id);
  end if;
  update public.erp_commercial_workflow_documents
  set status='approved',payload=payload||jsonb_build_object('journalEntryId',v_entry_id,'approvedAt',now(),'approvedBy',auth.uid()),updated_at=now()
  where company_id=p_company_id and id=p_invoice_id;
  perform public.erp_commercial_audit(p_company_id,p_module,v_doc.parent_id,v_doc.id,v_doc.document_number,'approve_invoice',v_doc.status,'approved',null);
end;
$$;

create or replace function public.erp_approve_cloud_sales_workflow_invoice(p_company_id uuid,p_invoice_id uuid)
returns void language sql security definer set search_path=public as $$
  select public.erp_approve_cloud_workflow_invoice(p_company_id,p_invoice_id,'sales')
$$;
create or replace function public.erp_approve_cloud_purchase_workflow_invoice(p_company_id uuid,p_invoice_id uuid)
returns void language sql security definer set search_path=public as $$
  select public.erp_approve_cloud_workflow_invoice(p_company_id,p_invoice_id,'purchases')
$$;

create or replace function public.erp_cancel_cloud_workflow_invoice(
  p_company_id uuid,p_invoice_id uuid,p_module text,p_reason text default null
) returns void language plpgsql security definer set search_path=public as $$
declare v_doc public.erp_commercial_workflow_documents%rowtype; v_journal text;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  select * into v_doc from public.erp_commercial_workflow_documents
  where company_id=p_company_id and id=p_invoice_id and module=p_module and document_type='invoice' and not is_deleted for update;
  if not found then raise exception 'الفاتورة غير موجودة'; end if;
  if v_doc.status='cancelled' then return; end if;
  if jsonb_array_length(coalesce(v_doc.payload->'payments','[]'::jsonb))>0 then raise exception 'لا يمكن إلغاء فاتورة تحتوي دفعات قبل عكسها محاسبيًا'; end if;
  v_journal:=nullif(v_doc.payload->>'journalEntryId','');
  if v_journal is not null then
    update public.erp_journal_lines set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid() where company_id=p_company_id and not is_deleted and data->>'entryId'=v_journal;
    update public.erp_journal_entries set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid() where company_id=p_company_id and id=v_journal and not is_deleted;
  end if;
  if p_module='sales' and v_doc.status='approved' then
    perform public.erp_restore_sales_order_cars_after_invoice_cancel(p_company_id,v_doc.parent_id,p_invoice_id);
  end if;
  update public.erp_commercial_workflow_documents set status='cancelled',payload=payload||jsonb_build_object('reason',p_reason,'cancelledAt',now()),updated_at=now() where company_id=p_company_id and id=p_invoice_id;
  perform public.erp_commercial_audit(p_company_id,p_module,v_doc.parent_id,v_doc.id,v_doc.document_number,'cancel_invoice',v_doc.status,'cancelled',p_reason);
end;
$$;
create or replace function public.erp_cancel_cloud_sales_workflow_invoice(p_company_id uuid,p_invoice_id uuid,p_reason text default null)
returns void language sql security definer set search_path=public as $$
  select public.erp_cancel_cloud_workflow_invoice(p_company_id,p_invoice_id,'sales',p_reason)
$$;
create or replace function public.erp_cancel_cloud_purchase_workflow_invoice(p_company_id uuid,p_invoice_id uuid,p_reason text default null)
returns void language sql security definer set search_path=public as $$
  select public.erp_cancel_cloud_workflow_invoice(p_company_id,p_invoice_id,'purchases',p_reason)
$$;

create or replace function public.erp_apply_cloud_workflow_invoice_payment(
  p_company_id uuid,p_invoice_id uuid,p_module text,p_payment jsonb
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_doc public.erp_commercial_workflow_documents%rowtype;
  v_invoice_currency text; v_payment_currency text; v_mode text;
  v_remaining numeric; v_requested numeric; v_applied numeric; v_cash numeric; v_rate numeric;
  v_expected numeric; v_equivalent numeric; v_difference numeric; v_next numeric; v_tolerance numeric;
  v_cash_id text; v_cash_ledger text; v_partner_id text; v_partner_type text; v_partner_ledger text;
  v_gain_ledger text; v_loss_ledger text; v_journal_id text; v_cash_transaction_id text; v_payment_id text;
  v_payment_date timestamptz; v_type text; v_key text; v_enriched jsonb; v_total_side numeric;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  if p_module not in ('sales','purchases') then raise exception 'invalid workflow module'; end if;
  select * into v_doc from public.erp_commercial_workflow_documents
  where company_id=p_company_id and id=p_invoice_id and module=p_module and document_type='invoice' and status='approved' and not is_deleted for update;
  if not found then raise exception 'الفاتورة المصدقة غير موجودة'; end if;

  v_invoice_currency:=upper(coalesce(v_doc.payload->>'currency',''));
  v_payment_currency:=upper(coalesce(p_payment->>'paymentCurrency',''));
  v_mode:=coalesce(p_payment->>'settlementMode','partial');
  v_remaining:=public.erp_try_numeric(v_doc.payload->>'remainingAmount',0);
  v_requested:=public.erp_try_numeric(p_payment->>'invoiceAmount',0);
  v_cash:=public.erp_try_numeric(p_payment->>'cashAmount',0);
  v_rate:=public.erp_try_numeric(p_payment->>'exchangeRate',0);
  v_cash_id:=btrim(coalesce(p_payment->>'cashAccountId',''));
  v_payment_date:=coalesce(public.erp_try_timestamptz(p_payment->>'paymentDate',null),now());
  if v_invoice_currency not in ('USD','IQD') or v_payment_currency not in ('USD','IQD') or v_cash_id='' or v_remaining<=0 or v_cash<=0 or v_rate<=0 then
    raise exception 'بيانات الدفعة غير صحيحة';
  end if;
  if v_mode not in ('partial','fullWithExchangeDifference','full_fx') then raise exception 'نوع التسوية غير مدعوم'; end if;
  v_applied:=case when v_mode in ('fullWithExchangeDifference','full_fx') then v_remaining else v_requested end;
  if v_applied<=0 or v_applied>v_remaining+0.01 then raise exception 'مبلغ الدفعة يتجاوز المتبقي'; end if;
  v_expected:=case when v_invoice_currency=v_payment_currency then v_applied when v_invoice_currency='USD' then v_applied*v_rate else v_applied/v_rate end;
  v_equivalent:=case when v_invoice_currency=v_payment_currency then v_cash when v_invoice_currency='USD' then v_cash/v_rate else v_cash*v_rate end;
  v_difference:=case when v_mode in ('fullWithExchangeDifference','full_fx') then v_equivalent-v_applied else 0 end;
  if v_mode='partial' then
    v_tolerance:=greatest(0.01,least(1000,abs(v_expected)*0.005));
    if abs(v_cash-v_expected)>v_tolerance then raise exception 'مبلغ الصندوق لا يطابق مبلغ الفاتورة وسعر الصرف'; end if;
    v_equivalent:=v_applied; v_difference:=0;
  end if;
  v_next:=greatest(0,v_remaining-v_applied);
  v_key:=md5(concat_ws('|',p_invoice_id::text,v_cash_id,v_payment_currency,round(v_applied,4)::text,round(v_cash,4)::text,round(v_rate,6)::text,v_payment_date::text,coalesce(p_payment->>'notes','')));
  if exists(select 1 from jsonb_array_elements(coalesce(v_doc.payload->'payments','[]'::jsonb)) x where x->>'paymentKey'=v_key) then return; end if;

  select nullif(coalesce(data->>'accountId',data->>'account_id'),'') into v_cash_ledger
  from public.erp_cash_accounts where company_id=p_company_id and id=v_cash_id and not is_deleted and public.erp_try_boolean(data->>'isActive',true) for update;
  if not found or v_cash_ledger is null then raise exception 'الصندوق غير موجود أو غير مرتبط بحساب محاسبي'; end if;
  perform public.erp_ensure_workflow_accounts(p_company_id);
  select account_id into v_gain_ledger from public.erp_accounts where organization_id=p_company_id and code='4200' and is_active limit 1;
  select account_id into v_loss_ledger from public.erp_accounts where organization_id=p_company_id and code='5300' and is_active limit 1;
  if p_module='sales' then
    select customer_id into v_partner_id from public.erp_sales_orders_cloud where company_id=p_company_id and id=v_doc.parent_id and not is_deleted;
    v_partner_type:='customer'; v_type:='receipt';
  else
    select supplier_id into v_partner_id from public.erp_purchase_orders_cloud where company_id=p_company_id and id=v_doc.parent_id and not is_deleted;
    v_partner_type:='supplier'; v_type:='payment';
  end if;
  v_partner_ledger:=public.erp_workflow_partner_account(p_company_id,v_partner_type,v_partner_id,v_invoice_currency);
  v_payment_id:=gen_random_uuid()::text; v_journal_id:=gen_random_uuid()::text; v_cash_transaction_id:=gen_random_uuid()::text;
  v_total_side:=greatest(v_applied,v_equivalent);

  insert into public.erp_journal_entries(company_id,id,data,created_by,updated_by)
  values(p_company_id,v_journal_id,jsonb_build_object(
    'id',v_journal_id,'entryNumber',(case when p_module='sales' then 'SPAY-' else 'PPAY-' end)||replace(v_payment_id,'-',''),
    'entryDate',v_payment_date,'description',(case when p_module='sales' then 'قبض فاتورة بيع ' else 'دفع فاتورة شراء ' end)||v_doc.document_number,
    'currency',v_invoice_currency,'referenceType','workflow_payment','referenceId',v_payment_id,
    'invoiceId',v_doc.id::text,'orderId',v_doc.parent_id::text,'totalDebit',v_total_side,'totalCredit',v_total_side,'status','posted','createdAt',now()),auth.uid(),auth.uid());

  if p_module='sales' then
    insert into public.erp_journal_lines(company_id,id,data,created_by,updated_by) values
      (p_company_id,gen_random_uuid()::text,jsonb_build_object('entryId',v_journal_id,'accountId',v_cash_ledger,'debit',v_equivalent,'credit',0,'description','الصندوق'),auth.uid(),auth.uid()),
      (p_company_id,gen_random_uuid()::text,jsonb_build_object('entryId',v_journal_id,'accountId',v_partner_ledger,'debit',0,'credit',v_applied,'description','تسديد ذمة العميل'),auth.uid(),auth.uid());
    if v_difference>0.0001 then
      insert into public.erp_journal_lines(company_id,id,data,created_by,updated_by) values(p_company_id,gen_random_uuid()::text,jsonb_build_object('entryId',v_journal_id,'accountId',v_gain_ledger,'debit',0,'credit',v_difference,'description','ربح فرق صرف'),auth.uid(),auth.uid());
    elsif v_difference< -0.0001 then
      insert into public.erp_journal_lines(company_id,id,data,created_by,updated_by) values(p_company_id,gen_random_uuid()::text,jsonb_build_object('entryId',v_journal_id,'accountId',v_loss_ledger,'debit',abs(v_difference),'credit',0,'description','خسارة فرق صرف'),auth.uid(),auth.uid());
    end if;
  else
    insert into public.erp_journal_lines(company_id,id,data,created_by,updated_by) values
      (p_company_id,gen_random_uuid()::text,jsonb_build_object('entryId',v_journal_id,'accountId',v_partner_ledger,'debit',v_applied,'credit',0,'description','تسديد ذمة المورد'),auth.uid(),auth.uid()),
      (p_company_id,gen_random_uuid()::text,jsonb_build_object('entryId',v_journal_id,'accountId',v_cash_ledger,'debit',0,'credit',v_equivalent,'description','الصندوق'),auth.uid(),auth.uid());
    if v_difference>0.0001 then
      insert into public.erp_journal_lines(company_id,id,data,created_by,updated_by) values(p_company_id,gen_random_uuid()::text,jsonb_build_object('entryId',v_journal_id,'accountId',v_loss_ledger,'debit',v_difference,'credit',0,'description','خسارة فرق صرف'),auth.uid(),auth.uid());
    elsif v_difference< -0.0001 then
      insert into public.erp_journal_lines(company_id,id,data,created_by,updated_by) values(p_company_id,gen_random_uuid()::text,jsonb_build_object('entryId',v_journal_id,'accountId',v_gain_ledger,'debit',0,'credit',abs(v_difference),'description','ربح فرق صرف'),auth.uid(),auth.uid());
    end if;
  end if;

  insert into public.erp_cash_transactions(company_id,id,data,created_by,updated_by)
  values(p_company_id,v_cash_transaction_id,jsonb_build_object(
    'id',v_cash_transaction_id,'voucherNumber',(case when p_module='sales' then 'SR-' else 'PP-' end)||replace(v_payment_id,'-',''),
    'type',v_type,'category','workflow_invoice','cashAccountId',v_cash_id,
    'counterAccountId',v_partner_ledger,'paymentMethod',coalesce(nullif(p_payment->>'paymentMethod',''),'cash'),
    'amount',v_cash,'currency',v_payment_currency,'exchangeRate',v_rate,'invoiceAmount',v_applied,
    'amountUsd',case when v_payment_currency='USD' then v_cash else v_cash/v_rate end,
    'amountIqd',case when v_payment_currency='IQD' then v_cash else v_cash*v_rate end,
    'transactionDate',v_payment_date,'referenceType','workflow_invoice_payment','referenceId',v_doc.id::text,
    'partyType',v_partner_type,'partyId',v_partner_id,'notes',p_payment->>'notes',
    'journalEntryId',v_journal_id,'paymentId',v_payment_id,'createdAt',now(),'updatedAt',now()),auth.uid(),auth.uid());

  v_enriched:=p_payment||jsonb_build_object(
    'paymentId',v_payment_id,'paymentKey',v_key,'invoiceId',v_doc.id::text,'invoiceCurrency',v_invoice_currency,
    'invoiceAmount',v_applied,'appliedInvoiceAmount',v_applied,'cashAmount',v_cash,'paymentCurrency',v_payment_currency,
    'exchangeRate',v_rate,'expectedCashAmount',v_expected,'actualInvoiceEquivalent',v_equivalent,
    'exchangeDifference',v_difference,'previousRemainingAmount',v_remaining,'remainingAmount',v_next,
    'paymentDate',v_payment_date,'settlementMode',case when v_mode in ('fullWithExchangeDifference','full_fx') then 'full_fx' else 'partial' end,
    'journalEntryId',v_journal_id,'cashTransactionId',v_cash_transaction_id,'createdBy',auth.uid(),'createdAt',now()
  );
  update public.erp_commercial_workflow_documents set payload=
    jsonb_set(jsonb_set(jsonb_set(jsonb_set(
      payload,'{payments}',coalesce(payload->'payments','[]'::jsonb)||jsonb_build_array(v_enriched)),
      '{remainingAmount}',to_jsonb(v_next)),
      '{paidAmount}',to_jsonb(public.erp_try_numeric(payload->>'totalAmount',0)-v_next)),
      '{paymentStatus}',to_jsonb((case when v_next<=0.01 then 'paid' else 'partial' end)::text)),
    updated_at=now()
  where company_id=p_company_id and id=p_invoice_id;
  perform public.erp_commercial_audit(p_company_id,p_module,v_doc.parent_id,v_doc.id,v_doc.document_number,'invoice_payment','approved','approved',p_payment->>'notes');
end;
$$;


create or replace function public.erp_pay_cloud_sales_workflow_invoice(
  p_company_id uuid,p_invoice_id uuid,p_payment jsonb
) returns void language sql security definer set search_path=public as $$
  select public.erp_apply_cloud_workflow_invoice_payment(p_company_id,p_invoice_id,'sales',p_payment)
$$;

create or replace function public.erp_pay_cloud_purchase_workflow_invoice(
  p_company_id uuid,p_invoice_id uuid,p_payment jsonb
) returns void language sql security definer set search_path=public as $$
  select public.erp_apply_cloud_workflow_invoice_payment(p_company_id,p_invoice_id,'purchases',p_payment)
$$;

-- Safe workflow lists used by the pages.
create or replace function public.erp_list_cloud_active_warehouses(p_company_id uuid)
returns setof jsonb language sql security definer set search_path=public as $$
 select jsonb_build_object('id',w.id,'name',coalesce(w.data->>'name',''),'code',coalesce(w.data->>'code',''))
 from public.erp_warehouses w
 where w.company_id=p_company_id and not w.is_deleted
   and public.erp_try_boolean(w.data->>'isActive',true)
   and public.erp_is_company_member(p_company_id)
 order by coalesce(w.data->>'name','');
$$;

create or replace function public.erp_list_cloud_active_cash_accounts(p_company_id uuid)
returns setof jsonb language sql security definer set search_path=public as $$
 select jsonb_build_object(
   'id',c.id,
   'name',coalesce(c.data->>'name',''),
   'currency',upper(coalesce(nullif(c.data->>'currency',''),'USD'))
 )
 from public.erp_cash_accounts c
 where c.company_id=p_company_id
   and not c.is_deleted
   and public.erp_try_boolean(c.data->>'isActive',true)
   and public.erp_is_company_member(p_company_id)
 order by coalesce(c.data->>'name','');
$$;

create or replace function public.erp_list_cloud_sales_workflow_orders(p_company_id uuid)
returns setof jsonb language sql security definer set search_path=public as $$
 select jsonb_build_object(
  'id',o.id::text,'orderNumber',o.order_number,'customerId',o.customer_id,'customerName',coalesce(c.data->>'name',''),
  'status',o.status,'currency',o.currency,'exchangeRate',o.exchange_rate,'subtotal',o.subtotal,'discount',o.discount,'total',o.total,
  'notes',o.notes,'createdAt',o.created_at::text,'updatedAt',o.updated_at::text,
  'deliveryId',d.id::text,'deliveryStatus',d.status,'invoiceId',i.id::text,'invoiceStatus',i.status,
  'invoiceRemaining',public.erp_try_numeric(i.payload->>'remainingAmount',0)
 )
 from public.erp_sales_orders_cloud o
 left join public.erp_customers c on c.id=o.customer_id and c.company_id=o.company_id and not c.is_deleted
 left join lateral (select x.* from public.erp_commercial_workflow_documents x where x.company_id=o.company_id and x.module='sales' and x.document_type='delivery' and x.parent_id=o.id and not x.is_deleted order by x.created_at desc limit 1) d on true
 left join lateral (select x.* from public.erp_commercial_workflow_documents x where x.company_id=o.company_id and x.module='sales' and x.document_type='invoice' and x.parent_id=o.id and not x.is_deleted order by x.created_at desc limit 1) i on true
 where o.company_id=p_company_id and not o.is_deleted and public.erp_is_company_member(p_company_id)
 order by o.created_at desc;
$$;

create or replace function public.erp_list_cloud_purchase_workflow_orders(p_company_id uuid)
returns setof jsonb language sql security definer set search_path=public as $$
 select jsonb_build_object(
  'id',o.id::text,'orderNumber',o.order_number,'supplierId',o.supplier_id,'supplierName',coalesce(s.data->>'name',''),
  'status',o.status,'currency',o.currency,'exchangeRate',o.exchange_rate,'subtotal',o.subtotal,'discount',o.discount,'total',o.total,
  'notes',o.notes,'createdAt',o.created_at::text,'updatedAt',o.updated_at::text,
  'receiptId',r.id::text,'receiptStatus',r.status,'invoiceId',i.id::text,'invoiceStatus',i.status,
  'invoiceRemaining',public.erp_try_numeric(i.payload->>'remainingAmount',0)
 )
 from public.erp_purchase_orders_cloud o
 left join public.erp_suppliers s on s.id=o.supplier_id and s.company_id=o.company_id and not s.is_deleted
 left join lateral (select x.* from public.erp_commercial_workflow_documents x where x.company_id=o.company_id and x.module='purchases' and x.document_type='receipt' and x.parent_id=o.id and not x.is_deleted order by x.created_at desc limit 1) r on true
 left join lateral (select x.* from public.erp_commercial_workflow_documents x where x.company_id=o.company_id and x.module='purchases' and x.document_type='invoice' and x.parent_id=o.id and not x.is_deleted order by x.created_at desc limit 1) i on true
 where o.company_id=p_company_id and not o.is_deleted and public.erp_is_company_member(p_company_id)
 order by o.created_at desc;
$$;

-- UI/PDF projection with camelCase keys and actual stock/accounting records.
create or replace function public.erp_get_cloud_commercial_order_details(
  p_company_id uuid,p_order_id uuid,p_purchase boolean
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_module text:=case when p_purchase then 'purchases' else 'sales' end;
  v_order jsonb; v_items jsonb; v_logistics jsonb; v_invoices jsonb;
  v_payments jsonb; v_movements jsonb; v_journals jsonb; v_audit jsonb;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  if p_purchase then
    select jsonb_build_object(
      'id',o.id::text,'orderNumber',o.order_number,'partnerId',o.supplier_id,'partnerName',coalesce(s.data->>'name',''),
      'status',o.status,'currency',o.currency,'exchangeRate',o.exchange_rate,'subtotal',o.subtotal,
      'discount',o.discount,'total',o.total,'notes',o.notes,'createdAt',o.created_at::text,'updatedAt',o.updated_at::text
    ) into v_order
    from public.erp_purchase_orders_cloud o
    left join public.erp_suppliers s on s.company_id=o.company_id and s.id=o.supplier_id and not s.is_deleted
    where o.company_id=p_company_id and o.id=p_order_id and not o.is_deleted;
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',x.id::text,'itemType',x.item_type,'itemId',x.item_id,'description',x.description,
      'quantity',x.quantity,'unitCost',x.unit_cost,'lineTotal',x.line_total,
      'detail_brand',case when x.item_type='car' then coalesce(c.data->>'brand',c.data->>'make') end,
      'detail_model',case when x.item_type='car' then c.data->>'model' end,
      'detail_year',case when x.item_type='car' then c.data->>'year' end,
      'detail_color',case when x.item_type='car' then c.data->>'color' end,
      'detail_chassis',case when x.item_type='car' then coalesce(c.data->>'chassis',c.data->>'vin') end,
      'detail_plateNumber',case when x.item_type='car' then c.data->>'plateNumber' end,
      'detail_status',case when x.item_type='car' then c.data->>'status' end,
      'detail_warehouseName',case
        when x.item_type='car' then coalesce((select w.data->>'name' from public.erp_warehouses w where w.company_id=x.company_id and w.id=coalesce(c.data->>'warehouseId',c.data->>'warehouse_id') limit 1),'')
        else coalesce((select string_agg(distinct coalesce(w.data->>'name',ws.data->>'warehouseId'),', ' order by coalesce(w.data->>'name',ws.data->>'warehouseId')) from public.erp_warehouse_stock ws left join public.erp_warehouses w on w.company_id=ws.company_id and w.id=ws.data->>'warehouseId' where ws.company_id=x.company_id and not ws.is_deleted and ws.data->>'productId'=x.item_id and public.erp_try_numeric(ws.data->>'quantity',0)>0),'')
      end,
      'detail_purchasePrice',case when x.item_type='car' then public.erp_try_numeric(c.data->>'purchasePrice',public.erp_try_numeric(c.data->>'costPrice',0)) end,
      'detail_salePrice',case when x.item_type='car' then public.erp_try_numeric(c.data->>'salePrice',0) else public.erp_try_numeric(i.data->>'salePrice',0) end,
      'detail_maintenanceCost',case when x.item_type='car' then public.erp_try_numeric(c.data->>'maintenanceCost',0) end,
      'detail_code',case when x.item_type='product' then i.data->>'code' end,
      'detail_name',case when x.item_type='product' then i.data->>'name' end,
      'detail_unit',case when x.item_type='product' then i.data->>'unit' end,
      'detail_category',case when x.item_type='product' then coalesce(i.data->>'category',i.data->>'groupName') end,
      'detail_availableQuantity',case when x.item_type='product' then (select coalesce(sum(public.erp_try_numeric(ws.data->>'quantity',0)),0) from public.erp_warehouse_stock ws where ws.company_id=x.company_id and not ws.is_deleted and ws.data->>'productId'=x.item_id) end,
      'detail_averageUnitCost',case when x.item_type='product' then public.erp_try_numeric(i.data->>'unitCost',public.erp_try_numeric(i.data->>'costPrice',0)) end,
      'detail_minimumQuantity',case when x.item_type='product' then public.erp_try_numeric(i.data->>'minimumQuantity',0) end,
      'details',case when x.item_type='car' then coalesce(c.data,'{}'::jsonb) else coalesce(i.data,'{}'::jsonb) end
    ) order by x.id),'[]'::jsonb) into v_items
    from public.erp_purchase_order_items_cloud x
    left join public.erp_cars c on x.item_type='car' and c.company_id=x.company_id and c.id=x.item_id and not c.is_deleted
    left join public.erp_inventory i on x.item_type='product' and i.company_id=x.company_id and i.id=x.item_id and not i.is_deleted
    where x.company_id=p_company_id and x.order_id=p_order_id and not x.is_deleted;
  else
    select jsonb_build_object(
      'id',o.id::text,'orderNumber',o.order_number,'partnerId',o.customer_id,'partnerName',coalesce(c.data->>'name',''),
      'status',o.status,'currency',o.currency,'exchangeRate',o.exchange_rate,'subtotal',o.subtotal,
      'discount',o.discount,'total',o.total,'notes',o.notes,'createdAt',o.created_at::text,'updatedAt',o.updated_at::text
    ) into v_order
    from public.erp_sales_orders_cloud o
    left join public.erp_customers c on c.company_id=o.company_id and c.id=o.customer_id and not c.is_deleted
    where o.company_id=p_company_id and o.id=p_order_id and not o.is_deleted;
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',x.id::text,'itemType',x.item_type,'itemId',x.item_id,'description',x.description,
      'quantity',x.quantity,'unitPrice',x.unit_price,'lineTotal',x.line_total,
      'detail_brand',case when x.item_type='car' then coalesce(c.data->>'brand',c.data->>'make') end,
      'detail_model',case when x.item_type='car' then c.data->>'model' end,
      'detail_year',case when x.item_type='car' then c.data->>'year' end,
      'detail_color',case when x.item_type='car' then c.data->>'color' end,
      'detail_chassis',case when x.item_type='car' then coalesce(c.data->>'chassis',c.data->>'vin') end,
      'detail_plateNumber',case when x.item_type='car' then c.data->>'plateNumber' end,
      'detail_status',case when x.item_type='car' then c.data->>'status' end,
      'detail_warehouseName',case
        when x.item_type='car' then coalesce((select w.data->>'name' from public.erp_warehouses w where w.company_id=x.company_id and w.id=coalesce(c.data->>'warehouseId',c.data->>'warehouse_id') limit 1),'')
        else coalesce((select string_agg(distinct coalesce(w.data->>'name',ws.data->>'warehouseId'),', ' order by coalesce(w.data->>'name',ws.data->>'warehouseId')) from public.erp_warehouse_stock ws left join public.erp_warehouses w on w.company_id=ws.company_id and w.id=ws.data->>'warehouseId' where ws.company_id=x.company_id and not ws.is_deleted and ws.data->>'productId'=x.item_id and public.erp_try_numeric(ws.data->>'quantity',0)>0),'')
      end,
      'detail_purchasePrice',case when x.item_type='car' then public.erp_try_numeric(c.data->>'purchasePrice',public.erp_try_numeric(c.data->>'costPrice',0)) end,
      'detail_salePrice',case when x.item_type='car' then public.erp_try_numeric(c.data->>'salePrice',0) else public.erp_try_numeric(i.data->>'salePrice',0) end,
      'detail_maintenanceCost',case when x.item_type='car' then public.erp_try_numeric(c.data->>'maintenanceCost',0) end,
      'detail_code',case when x.item_type='product' then i.data->>'code' end,
      'detail_name',case when x.item_type='product' then i.data->>'name' end,
      'detail_unit',case when x.item_type='product' then i.data->>'unit' end,
      'detail_category',case when x.item_type='product' then coalesce(i.data->>'category',i.data->>'groupName') end,
      'detail_availableQuantity',case when x.item_type='product' then (select coalesce(sum(public.erp_try_numeric(ws.data->>'quantity',0)),0) from public.erp_warehouse_stock ws where ws.company_id=x.company_id and not ws.is_deleted and ws.data->>'productId'=x.item_id) end,
      'detail_averageUnitCost',case when x.item_type='product' then public.erp_try_numeric(i.data->>'unitCost',public.erp_try_numeric(i.data->>'costPrice',0)) end,
      'detail_minimumQuantity',case when x.item_type='product' then public.erp_try_numeric(i.data->>'minimumQuantity',0) end,
      'details',case when x.item_type='car' then coalesce(c.data,'{}'::jsonb) else coalesce(i.data,'{}'::jsonb) end
    ) order by x.id),'[]'::jsonb) into v_items
    from public.erp_sales_order_items_cloud x
    left join public.erp_cars c on x.item_type='car' and c.company_id=x.company_id and c.id=x.item_id and not c.is_deleted
    left join public.erp_inventory i on x.item_type='product' and i.company_id=x.company_id and i.id=x.item_id and not i.is_deleted
    where x.company_id=p_company_id and x.order_id=p_order_id and not x.is_deleted;
  end if;
  if v_order is null then raise exception 'الأمر غير موجود'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',d.id::text,
    'receiptNumber',case when d.document_type='receipt' then d.document_number else null end,
    'deliveryNumber',case when d.document_type='delivery' then d.document_number else null end,
    'warehouseId',d.warehouse_id,'warehouseName',coalesce(w.data->>'name',''),
    'status',d.status,
    'receiptDate',case when d.document_type='receipt' then d.created_at::text else null end,
    'deliveryDate',case when d.document_type='delivery' then d.created_at::text else null end,
    'inventoryPostedAt',d.payload->>'inventoryPostedAt','notes',d.payload->>'notes',
    'createdAt',d.created_at::text,'updatedAt',d.updated_at::text
  ) order by d.created_at),'[]'::jsonb) into v_logistics
  from public.erp_commercial_workflow_documents d
  left join public.erp_warehouses w on w.company_id=d.company_id and w.id=d.warehouse_id
  where d.company_id=p_company_id and d.module=v_module and d.parent_id=p_order_id
    and d.document_type in ('receipt','delivery') and not d.is_deleted;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',d.id::text,'invoiceNumber',d.document_number,'status',d.status,
    'currency',d.payload->>'currency','total',public.erp_try_numeric(d.payload->>'totalAmount',0),
    'paidAmount',public.erp_try_numeric(d.payload->>'paidAmount',public.erp_try_numeric(d.payload->>'totalAmount',0)-public.erp_try_numeric(d.payload->>'remainingAmount',0)),
    'remainingAmount',public.erp_try_numeric(d.payload->>'remainingAmount',0),
    'paymentStatus',d.payload->>'paymentStatus','journalEntryId',d.payload->>'journalEntryId',
    'createdAt',d.created_at::text,'updatedAt',d.updated_at::text
  ) order by d.created_at),'[]'::jsonb) into v_invoices
  from public.erp_commercial_workflow_documents d
  where d.company_id=p_company_id and d.module=v_module and d.parent_id=p_order_id
    and d.document_type='invoice' and not d.is_deleted;

  select coalesce(jsonb_agg(p.payment||jsonb_build_object(
    'invoiceId',d.id::text,'invoiceNumber',d.document_number,
    'cashAccountName',coalesce(c.data->>'name',''),'cashAccountCurrency',c.data->>'currency'
  ) order by public.erp_try_timestamptz(p.payment->>'paymentDate',d.created_at)),'[]'::jsonb) into v_payments
  from public.erp_commercial_workflow_documents d
  cross join lateral jsonb_array_elements(coalesce(d.payload->'payments','[]'::jsonb)) p(payment)
  left join public.erp_cash_accounts c on c.company_id=d.company_id and c.id=p.payment->>'cashAccountId' and not c.is_deleted
  where d.company_id=p_company_id and d.module=v_module and d.parent_id=p_order_id and d.document_type='invoice' and not d.is_deleted;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',m.id,'movementNumber',m.data->>'movementNumber','productId',m.data->>'productId',
    'productName',coalesce(i.data->>'name',i.data->>'code',''),'warehouseId',m.data->>'warehouseId',
    'warehouseName',coalesce(w.data->>'name',''),'quantity',public.erp_try_numeric(m.data->>'quantity',0),
    'movementType',m.data->>'movementType','unitCost',public.erp_try_numeric(m.data->>'unitCost',0),
    'referenceType',m.data->>'referenceType','referenceId',m.data->>'referenceId',
    'movementDate',coalesce(m.data->>'movementDate',m.created_at::text)
  ) order by public.erp_try_timestamptz(m.data->>'movementDate',m.created_at)),'[]'::jsonb) into v_movements
  from public.erp_inventory_movements m
  left join public.erp_inventory i on i.company_id=m.company_id and i.id=m.data->>'productId' and not i.is_deleted
  left join public.erp_warehouses w on w.company_id=m.company_id and w.id=m.data->>'warehouseId'
  where m.company_id=p_company_id and not m.is_deleted
    and exists(select 1 from public.erp_commercial_workflow_documents d where d.company_id=p_company_id and d.module=v_module and d.parent_id=p_order_id and m.data->>'referenceId'=d.id::text);

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',j.id,'entryNumber',j.data->>'entryNumber','entryDate',j.data->>'entryDate',
    'description',j.data->>'description','currency',j.data->>'currency',
    'totalDebit',public.erp_try_numeric(j.data->>'totalDebit',0),'totalCredit',public.erp_try_numeric(j.data->>'totalCredit',0),
    'referenceType',j.data->>'referenceType','referenceId',j.data->>'referenceId','status',j.data->>'status'
  ) order by public.erp_try_timestamptz(j.data->>'entryDate',j.created_at)),'[]'::jsonb) into v_journals
  from public.erp_journal_entries j
  where j.company_id=p_company_id and not j.is_deleted and (
    j.data->>'orderId'=p_order_id::text
    or exists(select 1 from public.erp_commercial_workflow_documents d where d.company_id=p_company_id and d.module=v_module and d.parent_id=p_order_id and j.data->>'referenceId'=d.id::text)
    or exists(select 1 from public.erp_commercial_workflow_documents d cross join lateral jsonb_array_elements(coalesce(d.payload->'payments','[]'::jsonb)) p(payment) where d.company_id=p_company_id and d.module=v_module and d.parent_id=p_order_id and j.data->>'referenceId'=p.payment->>'paymentId')
  );

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',a.id::text,'documentId',a.document_id::text,'documentNumber',a.document_number,
    'action',a.action,'fromStatus',a.from_status,'toStatus',a.to_status,'reason',a.reason,
    'performedBy',coalesce(u.email,'النظام'),'performedAt',a.performed_at::text
  ) order by a.performed_at),'[]'::jsonb) into v_audit
  from public.erp_commercial_workflow_audit a
  left join auth.users u on u.id=a.performed_by
  where a.company_id=p_company_id and a.module=v_module and a.parent_id=p_order_id;

  return jsonb_build_object(
    'order',v_order,'items',coalesce(v_items,'[]'::jsonb),'logistics',v_logistics,
    'invoices',v_invoices,'payments',v_payments,'movements',v_movements,
    'journalEntries',v_journals,'auditTrail',v_audit
  );
end;
$$;

-- Make every changed table publish tenant-scoped changes to the Flutter bridge.
do $$
declare t text;
begin
  foreach t in array array[
    'erp_cars','erp_car_images','erp_warehouses','erp_car_warehouse_transfers',
    'erp_inventory','erp_inventory_groups','erp_warehouse_stock','erp_inventory_movements',
    'erp_inventory_receipts','erp_inventory_product_sales','erp_customers','erp_suppliers',
    'erp_sales','erp_installments','erp_purchases','erp_purchase_items',
    'erp_sales_orders_cloud','erp_sales_order_items_cloud','erp_purchase_orders_cloud',
    'erp_purchase_order_items_cloud','erp_commercial_workflow_documents','erp_commercial_workflow_audit',
    'erp_cash_accounts','erp_cash_transactions','erp_journal_entries','erp_journal_lines',
    'erp_expenses','erp_reservations','erp_records','branches','erp_accounts'
  ] loop
    if to_regclass('public.'||t) is null then continue; end if;
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then
      execute format('alter publication supabase_realtime add table public.%I',t);
    end if;
  end loop;
exception when undefined_object then
  null;
end $$;

-- Browser-facing commands.
grant execute on function public.erp_cloud_dashboard_snapshot(uuid,date) to authenticated;
grant execute on function public.erp_cloud_global_search(uuid,text,integer) to authenticated;
grant execute on function public.erp_cloud_purchase_order_catalog(uuid) to authenticated;
grant execute on function public.erp_cloud_sales_order_catalog(uuid) to authenticated;
grant execute on function public.erp_prepare_company_runtime(uuid) to authenticated;
grant execute on function public.erp_approve_cloud_purchase_order(uuid,uuid) to authenticated;
grant execute on function public.erp_reopen_cloud_purchase_order(uuid,uuid) to authenticated;
grant execute on function public.erp_approve_cloud_sales_order(uuid,uuid) to authenticated;
grant execute on function public.erp_reopen_cloud_sales_order(uuid,uuid) to authenticated;
grant execute on function public.erp_create_cloud_purchase_receipt(uuid,uuid,text,text) to authenticated;
grant execute on function public.erp_create_cloud_sales_delivery(uuid,uuid,text,text) to authenticated;
grant execute on function public.erp_approve_cloud_purchase_receipt(uuid,uuid) to authenticated;
grant execute on function public.erp_cancel_cloud_purchase_receipt(uuid,uuid) to authenticated;
grant execute on function public.erp_approve_cloud_sales_delivery(uuid,uuid) to authenticated;
grant execute on function public.erp_cancel_cloud_sales_delivery(uuid,uuid) to authenticated;
grant execute on function public.erp_create_cloud_sales_workflow_invoice(uuid,uuid) to authenticated;
grant execute on function public.erp_create_cloud_purchase_workflow_invoice(uuid,uuid) to authenticated;
grant execute on function public.erp_approve_cloud_sales_workflow_invoice(uuid,uuid) to authenticated;
grant execute on function public.erp_approve_cloud_purchase_workflow_invoice(uuid,uuid) to authenticated;
grant execute on function public.erp_cancel_cloud_sales_workflow_invoice(uuid,uuid,text) to authenticated;
grant execute on function public.erp_cancel_cloud_purchase_workflow_invoice(uuid,uuid,text) to authenticated;
grant execute on function public.erp_apply_cloud_workflow_invoice_payment(uuid,uuid,text,jsonb) to authenticated;
grant execute on function public.erp_pay_cloud_sales_workflow_invoice(uuid,uuid,jsonb) to authenticated;
grant execute on function public.erp_pay_cloud_purchase_workflow_invoice(uuid,uuid,jsonb) to authenticated;
grant execute on function public.erp_list_cloud_active_warehouses(uuid) to authenticated;
grant execute on function public.erp_list_cloud_active_cash_accounts(uuid) to authenticated;
grant execute on function public.erp_list_cloud_sales_workflow_orders(uuid) to authenticated;
grant execute on function public.erp_list_cloud_purchase_workflow_orders(uuid) to authenticated;
grant execute on function public.erp_get_cloud_commercial_order_details(uuid,uuid,boolean) to authenticated;

-- Internal helpers are callable only through the audited SECURITY DEFINER API.
revoke all on function public.erp_enrich_journal_line_payload() from public,anon,authenticated;
revoke all on function public.erp_mark_sales_order_cars_sold(uuid,uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_restore_sales_order_cars_after_invoice_cancel(uuid,uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_inventory_ensure_stock(uuid,text,text) from public,anon,authenticated;
revoke all on function public.erp_ensure_workflow_accounts(uuid) from public,anon,authenticated;
revoke all on function public.erp_workflow_partner_account(uuid,text,text,text) from public,anon,authenticated;
revoke all on function public.erp_approve_cloud_workflow_invoice(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.erp_cancel_cloud_workflow_invoice(uuid,uuid,text,text) from public,anon,authenticated;
revoke all on function public.erp_commercial_audit(uuid,text,uuid,uuid,text,text,text,text,text) from public,anon,authenticated;

commit;
