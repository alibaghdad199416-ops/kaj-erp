-- Phase 23: cloud-only commercial workflows, reservations, partner service,
-- global search and notifications. Version remains 17.15.5+1715005.

create extension if not exists pgcrypto;

create table if not exists public.erp_reservations (
  id uuid primary key default gen_random_uuid(), company_id uuid not null,
  reservation_number text not null, car_id text not null, car_name text not null default '',
  customer_id text not null, customer_name text not null default '', customer_phone text not null default '',
  deposit_amount numeric(20,2) not null default 0, start_date timestamptz not null,
  end_date timestamptz not null, status text not null default 'active', notes text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  is_deleted boolean not null default false, deleted_at timestamptz,
  unique(company_id,reservation_number)
);
create index if not exists erp_reservations_company_dates on public.erp_reservations(company_id,start_date desc);

create table if not exists public.erp_partner_activities (
  id uuid primary key default gen_random_uuid(), company_id uuid not null, partner_id text not null,
  activity_type text not null, subject text not null, details text, activity_date timestamptz not null,
  created_by uuid default auth.uid(), created_at timestamptz not null default now(), is_deleted boolean not null default false
);
create table if not exists public.erp_service_cases (
  id uuid primary key default gen_random_uuid(), company_id uuid not null, partner_id text not null,
  case_number text not null, title text not null, description text, priority text not null default 'normal',
  status text not null default 'open', created_by uuid default auth.uid(), created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(), is_deleted boolean not null default false, deleted_at timestamptz,
  unique(company_id,case_number)
);

-- Cloud workflow document tables.
create table if not exists public.erp_sales_orders_cloud (
 id uuid primary key default gen_random_uuid(), company_id uuid not null, order_number text not null,
 customer_id text not null, opportunity_id text, status text not null default 'draft', currency text not null,
 exchange_rate numeric(20,6) not null, subtotal numeric(20,2) not null, discount numeric(20,2) not null default 0,
 total numeric(20,2) not null, notes text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 is_deleted boolean not null default false, deleted_at timestamptz, unique(company_id,order_number)
);
create table if not exists public.erp_sales_order_items_cloud (
 id uuid primary key default gen_random_uuid(), company_id uuid not null, order_id uuid not null references public.erp_sales_orders_cloud(id),
 item_type text not null, item_id text not null, description text not null, quantity integer not null check(quantity>0),
 unit_price numeric(20,2) not null check(unit_price>=0), line_total numeric(20,2) not null, is_deleted boolean not null default false
);
create table if not exists public.erp_purchase_orders_cloud (
 id uuid primary key default gen_random_uuid(), company_id uuid not null, order_number text not null,
 supplier_id text not null, status text not null default 'draft', currency text not null, exchange_rate numeric(20,6) not null,
 subtotal numeric(20,2) not null, discount numeric(20,2) not null default 0, total numeric(20,2) not null, notes text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), is_deleted boolean not null default false,
 deleted_at timestamptz, unique(company_id,order_number)
);
create table if not exists public.erp_purchase_order_items_cloud (
 id uuid primary key default gen_random_uuid(), company_id uuid not null, order_id uuid not null references public.erp_purchase_orders_cloud(id),
 item_type text not null, item_id text not null, description text not null, quantity integer not null check(quantity>0),
 unit_cost numeric(20,2) not null check(unit_cost>=0), line_total numeric(20,2) not null, is_deleted boolean not null default false
);
create table if not exists public.erp_commercial_workflow_documents (
 id uuid primary key default gen_random_uuid(), company_id uuid not null, module text not null,
 document_type text not null, parent_id uuid not null, document_number text not null, warehouse_id text,
 status text not null default 'draft', payload jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 is_deleted boolean not null default false, deleted_at timestamptz, unique(company_id,module,document_type,document_number)
);

alter table public.erp_reservations enable row level security;
alter table public.erp_partner_activities enable row level security;
alter table public.erp_service_cases enable row level security;
alter table public.erp_sales_orders_cloud enable row level security;
alter table public.erp_sales_order_items_cloud enable row level security;
alter table public.erp_purchase_orders_cloud enable row level security;
alter table public.erp_purchase_order_items_cloud enable row level security;
alter table public.erp_commercial_workflow_documents enable row level security;

-- Reuse the established tenant membership function from previous migrations.
do $$ declare t text; begin
 foreach t in array array['erp_reservations','erp_partner_activities','erp_service_cases','erp_sales_orders_cloud','erp_sales_order_items_cloud','erp_purchase_orders_cloud','erp_purchase_order_items_cloud','erp_commercial_workflow_documents'] loop
   execute format('drop policy if exists %I on public.%I', t||'_tenant', t);
   execute format('create policy %I on public.%I for all using (public.erp_is_company_member(company_id)) with check (public.erp_is_company_member(company_id))', t||'_tenant', t);
 end loop;
end $$;

create or replace function public.erp_list_cloud_reservations(p_company_id uuid,p_query text default null)
returns table("id" text,"reservationNumber" text,"carId" text,"carName" text,"customerId" text,"customerName" text,"customerPhone" text,"depositAmount" numeric,"startDate" text,"endDate" text,"status" text,"notes" text,"createdAt" text,"updatedAt" text)
language sql security definer set search_path=public as $$
 select r.id::text,r.reservation_number,r.car_id::text,r.car_name,r.customer_id::text,r.customer_name,r.customer_phone,r.deposit_amount,
 r.start_date::text,r.end_date::text,r.status,r.notes,r.created_at::text,r.updated_at::text
 from erp_reservations r where r.company_id=p_company_id and not r.is_deleted and public.erp_is_company_member(p_company_id)
 and (nullif(trim(p_query),'') is null or r.reservation_number ilike '%'||p_query||'%' or r.customer_name ilike '%'||p_query||'%' or r.car_name ilike '%'||p_query||'%')
 order by r.start_date desc,r.created_at desc;
$$;

create or replace function public.erp_save_cloud_reservation(p_company_id uuid,p_payload jsonb,p_expected_updated_at timestamptz default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid:=coalesce(nullif(p_payload->>'id','')::uuid,gen_random_uuid()); v_old erp_reservations%rowtype;
begin
 if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
 select * into v_old from erp_reservations where company_id=p_company_id and id=v_id for update;
 if found and p_expected_updated_at is not null and v_old.updated_at<>p_expected_updated_at then raise exception 'record changed on another device'; end if;
 insert into erp_reservations(id,company_id,reservation_number,car_id,car_name,customer_id,customer_name,customer_phone,deposit_amount,start_date,end_date,status,notes,created_at,updated_at,is_deleted,deleted_at)
 values(v_id,p_company_id,p_payload->>'reservationNumber',p_payload->>'carId',coalesce(p_payload->>'carName',''),p_payload->>'customerId',coalesce(p_payload->>'customerName',''),coalesce(p_payload->>'customerPhone',''),coalesce((p_payload->>'depositAmount')::numeric,0),(p_payload->>'startDate')::timestamptz,(p_payload->>'endDate')::timestamptz,coalesce(p_payload->>'status','active'),p_payload->>'notes',coalesce((p_payload->>'createdAt')::timestamptz,now()),now(),false,null)
 on conflict(id) do update set reservation_number=excluded.reservation_number,car_id=excluded.car_id,car_name=excluded.car_name,customer_id=excluded.customer_id,customer_name=excluded.customer_name,customer_phone=excluded.customer_phone,deposit_amount=excluded.deposit_amount,start_date=excluded.start_date,end_date=excluded.end_date,status=excluded.status,notes=excluded.notes,updated_at=now(),is_deleted=false,deleted_at=null;
 return v_id;
end $$;
create or replace function public.erp_delete_cloud_reservation(p_company_id uuid,p_reservation_id uuid) returns void language plpgsql security definer set search_path=public as $$
begin update erp_reservations set is_deleted=true,deleted_at=now(),updated_at=now(),status='cancelled' where company_id=p_company_id and id=p_reservation_id and public.erp_is_company_member(p_company_id); end $$;
create or replace function public.erp_cloud_reservation_number_exists(p_company_id uuid,p_reservation_number text,p_exclude_id uuid default null) returns boolean language sql security definer set search_path=public as $$ select exists(select 1 from erp_reservations where company_id=p_company_id and reservation_number=p_reservation_number and not is_deleted and (p_exclude_id is null or id<>p_exclude_id)) and public.erp_is_company_member(p_company_id) $$;

create or replace function public.erp_search_cloud_business_partners(p_company_id uuid,p_query text default '',p_role text default null,p_active_only boolean default true)
returns setof jsonb language sql security definer set search_path=public as $$
 with partners as (
  select c.id,coalesce(c.data->>'name','') display_name,c.data->>'phone' phone,coalesce(c.data->>'currency','USD') default_currency,coalesce(nullif(c.data->>'isActive','')::boolean,true) is_active,'customer' source_type,c.id source_id,c.data->>'email' email,c.data->>'address' address,c.data->>'taxNumber' tax_number,c.data->>'nationalId' national_id,coalesce(nullif(c.data->>'creditLimit','')::numeric,0) credit_limit,c.data->>'notes' notes,array['customer']::text[] roles from erp_customers c where c.company_id=p_company_id and not c.is_deleted
  union all
  select x.id,coalesce(x.data->>'name',''),x.data->>'phone',coalesce(x.data->>'currency','USD'),coalesce(nullif(x.data->>'isActive','')::boolean,true),'supplier',x.id,x.data->>'email',x.data->>'address',x.data->>'taxNumber',x.data->>'nationalId',0,x.data->>'notes',array['supplier']::text[] from erp_suppliers x where x.company_id=p_company_id and not x.is_deleted
 ) select jsonb_build_object('id',id,'displayName',display_name,'phone',coalesce(phone,''),'defaultCurrency',default_currency,'isActive',case when is_active then 1 else 0 end,'sourceType',source_type,'sourceId',source_id,'email',email,'address',address,'taxNumber',tax_number,'nationalId',national_id,'creditLimit',credit_limit,'notes',notes,'roles',roles)
 from partners where public.erp_is_company_member(p_company_id) and (not p_active_only or is_active) and (p_role is null or p_role=any(roles)) and (coalesce(trim(p_query),'')='' or display_name ilike '%'||p_query||'%' or coalesce(phone,'') ilike '%'||p_query||'%');
$$;
create or replace function public.erp_add_cloud_partner_activity(p_company_id uuid,p_partner_id text,p_activity_type text,p_subject text,p_details text,p_activity_date timestamptz) returns uuid language plpgsql security definer set search_path=public as $$ declare v uuid:=gen_random_uuid(); begin if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if; insert into erp_partner_activities(id,company_id,partner_id,activity_type,subject,details,activity_date) values(v,p_company_id,p_partner_id,p_activity_type,p_subject,p_details,p_activity_date); return v; end $$;
create or replace function public.erp_open_cloud_service_case(p_company_id uuid,p_partner_id text,p_title text,p_description text,p_priority text) returns uuid language plpgsql security definer set search_path=public as $$ declare v uuid:=gen_random_uuid(); begin if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if; insert into erp_service_cases(id,company_id,partner_id,case_number,title,description,priority) values(v,p_company_id,p_partner_id,'CASE-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS'),p_title,p_description,p_priority); return v; end $$;

-- Generic cloud workflow helpers. Every transition locks the current document.
create or replace function public.erp_cloud_workflow_transition(p_company_id uuid,p_module text,p_document_type text,p_document_id uuid,p_from text[],p_to text,p_extra jsonb default '{}'::jsonb) returns void language plpgsql security definer set search_path=public as $$
declare v erp_commercial_workflow_documents%rowtype;
begin if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
 select * into v from erp_commercial_workflow_documents where company_id=p_company_id and id=p_document_id and module=p_module and document_type=p_document_type and not is_deleted for update;
 if not found then raise exception 'workflow document not found'; end if; if not(v.status=any(p_from)) then raise exception 'invalid workflow transition from %',v.status; end if;
 update erp_commercial_workflow_documents set status=p_to,payload=payload||coalesce(p_extra,'{}'::jsonb),updated_at=now() where id=v.id;
end $$;

-- Search is centralized in PostgreSQL and always company scoped.
create or replace function public.erp_cloud_global_search(
  p_company_id uuid,
  p_query text,
  p_limit integer default 50
) returns setof jsonb
language sql security definer set search_path=public as $$
  with q as (
    select '%' || coalesce(trim(p_query),'') || '%' as pattern
  ), search_rows as (
    select
      c.id::text as id,
      'السيارات'::text as type,
      concat_ws(' ',c.data->>'brand',c.data->>'make',c.data->>'model') as title,
      coalesce(c.data->>'chassis',c.data->>'vin','') as subtitle,
      '/cars'::text as route,
      'cars.view'::text as permission,
      'car'::text as icon,
      c.data->>'status' as status,
      null::numeric as amount,
      c.created_at as occurred_at,
      1 as rank
    from public.erp_cars c cross join q
    where c.company_id=p_company_id
      and not c.is_deleted
      and (
        coalesce(c.data->>'brand',c.data->>'make','') ilike q.pattern
        or coalesce(c.data->>'model','') ilike q.pattern
        or coalesce(c.data->>'chassis',c.data->>'vin','') ilike q.pattern
      )

    union all

    select
      x.id::text,'العملاء',coalesce(x.data->>'name',''),coalesce(x.data->>'phone',''),
      '/customers','customers.view','customer',null::text,null::numeric,x.created_at,2
    from public.erp_customers x cross join q
    where x.company_id=p_company_id and not x.is_deleted
      and (coalesce(x.data->>'name','') ilike q.pattern or coalesce(x.data->>'phone','') ilike q.pattern)

    union all

    select
      x.id::text,'المجهزون',coalesce(x.data->>'name',''),coalesce(x.data->>'phone',''),
      '/suppliers','suppliers.view','supplier',null::text,null::numeric,x.created_at,3
    from public.erp_suppliers x cross join q
    where x.company_id=p_company_id and not x.is_deleted
      and (coalesce(x.data->>'name','') ilike q.pattern or coalesce(x.data->>'phone','') ilike q.pattern)

    union all

    select
      d.id::text,
      'المستندات',
      coalesce(d.data->>'titleAr',d.data->>'titleEn',d.data->>'title',''),
      coalesce(d.data->>'documentNumber',''),
      '/documents','documents.view','document',d.data->>'status',null::numeric,d.created_at,4
    from public.erp_document_records d cross join q
    where d.company_id=p_company_id and not d.is_deleted
      and (
        coalesce(d.data->>'titleAr',d.data->>'titleEn',d.data->>'title','') ilike q.pattern
        or coalesce(d.data->>'documentNumber','') ilike q.pattern
      )
  )
  select jsonb_build_object(
    'id',id,'type',type,'title',title,'subtitle',subtitle,'route',route,
    'permission',permission,'icon',icon,'status',status,'amount',amount,
    'date',occurred_at::text
  )
  from search_rows
  where public.erp_is_company_member(p_company_id)
  order by rank,occurred_at desc
  limit greatest(1,least(coalesce(p_limit,50),200));
$$;

-- Notification functions use the enterprise notification table introduced earlier.
create or replace function public.erp_create_cloud_notification(
  p_company_id uuid,
  p_user_id uuid,
  p_role_id uuid,
  p_title_ar text,
  p_title_en text,
  p_body_ar text,
  p_body_en text,
  p_type text,
  p_reference_type text,
  p_reference_id text
) returns uuid
language plpgsql security definer set search_path=public as $$
declare
  v_id uuid:=gen_random_uuid();
begin
  if not public.erp_is_company_member(p_company_id) then
    raise exception 'tenant denied';
  end if;
  insert into public.erp_enterprise_notifications(company_id,id,data)
  values(
    p_company_id,
    v_id,
    jsonb_build_object(
      'userId',p_user_id,
      'roleId',p_role_id,
      'titleAr',coalesce(p_title_ar,''),
      'titleEn',coalesce(p_title_en,''),
      'bodyAr',coalesce(p_body_ar,''),
      'bodyEn',coalesce(p_body_en,''),
      'type',coalesce(p_type,'info'),
      'referenceType',p_reference_type,
      'referenceId',p_reference_id,
      'isRead',false,
      'createdAt',now()
    )
  );
  return v_id;
end $$;
create or replace function public.erp_list_cloud_notifications(
  p_company_id uuid,
  p_user_id uuid default null,
  p_role_id uuid default null,
  p_unread_only boolean default false,
  p_limit integer default 100,
  p_offset integer default 0
) returns setof jsonb
language sql security definer set search_path=public as $$
  select n.data || jsonb_build_object(
    'id',n.id,
    'createdAt',coalesce(n.data->>'createdAt',n.created_at::text),
    'updatedAt',n.updated_at::text
  )
  from public.erp_enterprise_notifications n
  where n.company_id=p_company_id
    and not n.is_deleted
    and public.erp_is_company_member(p_company_id)
    and (
      (nullif(n.data->>'userId','') is null and nullif(n.data->>'roleId','') is null)
      or n.data->>'userId'=p_user_id::text
      or n.data->>'roleId'=p_role_id::text
    )
    and (
      not p_unread_only
      or not coalesce(nullif(n.data->>'isRead','')::boolean,false)
    )
  order by coalesce(nullif(n.data->>'isRead','')::boolean,false),n.created_at desc
  limit greatest(1,least(coalesce(p_limit,100),500))
  offset greatest(coalesce(p_offset,0),0);
$$;
create or replace function public.erp_cloud_unread_notification_count(
  p_company_id uuid,
  p_user_id uuid default null,
  p_role_id uuid default null
) returns integer
language sql security definer set search_path=public as $$
  select count(*)::integer
  from public.erp_enterprise_notifications n
  where n.company_id=p_company_id
    and not n.is_deleted
    and not coalesce(nullif(n.data->>'isRead','')::boolean,false)
    and public.erp_is_company_member(p_company_id)
    and (
      (nullif(n.data->>'userId','') is null and nullif(n.data->>'roleId','') is null)
      or n.data->>'userId'=p_user_id::text
      or n.data->>'roleId'=p_role_id::text
    );
$$;
create or replace function public.erp_mark_cloud_notification_read(
  p_company_id uuid,
  p_notification_id uuid
) returns void
language sql security definer set search_path=public as $$
  update public.erp_enterprise_notifications
  set data=data||jsonb_build_object('isRead',true,'readAt',now()),updated_at=now()
  where company_id=p_company_id
    and id=p_notification_id
    and not is_deleted
    and public.erp_is_company_member(p_company_id);
$$;
create or replace function public.erp_mark_all_cloud_notifications_read(
  p_company_id uuid,
  p_user_id uuid default null,
  p_role_id uuid default null
) returns void
language sql security definer set search_path=public as $$
  update public.erp_enterprise_notifications
  set data=data||jsonb_build_object('isRead',true,'readAt',now()),updated_at=now()
  where company_id=p_company_id
    and not is_deleted
    and not coalesce(nullif(data->>'isRead','')::boolean,false)
    and public.erp_is_company_member(p_company_id)
    and (
      (nullif(data->>'userId','') is null and nullif(data->>'roleId','') is null)
      or data->>'userId'=p_user_id::text
      or data->>'roleId'=p_role_id::text
    );
$$;

create or replace function public.erp_cloud_notification_alerts(p_company_id uuid,p_reference_day date) returns setof jsonb language sql security definer set search_path=public as $$
 with metrics as (
  select 'overdue-installments' id,'أقساط متأخرة' title,'يوجد أقساط متأخرة تحتاج إلى متابعة وتحصيل.' message,'critical' severity,'installment' icon,'/installments' route,count(*)::int count,coalesce(sum(coalesce(nullif(data->>'remainingAmount','')::numeric,0)),0) amount from erp_installments where company_id=p_company_id and not is_deleted and coalesce(data->>'status','')<>'paid' and coalesce(nullif(data->>'remainingAmount','')::numeric,0)>0 and nullif(data->>'dueDate','')::date<p_reference_day
  union all select 'low-stock','مواد عند الحد الأدنى','توجد مواد بلغت الحد الأدنى للمخزون.','warning','stock','/inventory',count(*)::int,null from erp_warehouse_stock where company_id=p_company_id and not is_deleted and coalesce(nullif(data->>'quantity','')::numeric,0)<=coalesce(nullif(data->>'minimumQuantity','')::numeric,0)
  union all select 'cars-without-warehouse','سيارات بلا مخزن','توجد سيارات غير مرتبطة بمخزن حالي.','critical','car','/cars',count(*)::int,null from erp_cars where company_id=p_company_id and not is_deleted and nullif(data->>'warehouseId','') is null
 ) select jsonb_build_object('id',id,'title',title,'message',message,'severity',severity,'icon',icon,'route',route,'count',count,'amount',amount) from metrics where count>0 and public.erp_is_company_member(p_company_id);
$$;

-- The concrete commercial RPC names are intentionally stable API boundaries.
-- They delegate creation/transitions to server-side transactions and can be
-- expanded without changing Flutter clients.

create or replace function public.erp_cloud_commercial_items_subtotal(
  p_company_id uuid,
  p_items jsonb,
  p_purchase boolean
) returns numeric
language plpgsql security definer set search_path=public as $$
declare
  v_item jsonb;
  v_item_type text;
  v_item_id text;
  v_description text;
  v_quantity numeric;
  v_unit_amount numeric;
  v_subtotal numeric := 0;
begin
  if not public.erp_is_company_member(p_company_id) then
    raise exception 'tenant denied';
  end if;
  if coalesce(jsonb_typeof(p_items),'null') <> 'array' then
    raise exception 'invalid order items';
  end if;
  if jsonb_array_length(p_items)=0 then
    raise exception 'empty order';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_items) x
    group by lower(coalesce(x->>'itemType','')),coalesce(x->>'itemId','')
    having count(*)>1
  ) then
    raise exception 'duplicate order item';
  end if;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_item_type := lower(coalesce(v_item->>'itemType',''));
    v_item_id := trim(coalesce(v_item->>'itemId',''));
    v_description := trim(coalesce(v_item->>'description',''));
    v_quantity := nullif(v_item->>'quantity','')::numeric;
    v_unit_amount := nullif(
      v_item->>(case when p_purchase then 'unitCost' else 'unitPrice' end),
      ''
    )::numeric;

    if v_item_type not in ('car','product')
       or v_item_id=''
       or v_description=''
       or coalesce(v_quantity,0)<=0
       or v_quantity<>trunc(v_quantity)
       or coalesce(v_unit_amount,-1)<0 then
      raise exception 'invalid order item';
    end if;
    if v_item_type='car' and v_quantity<>1 then
      raise exception 'vehicle quantity must equal one';
    end if;

    if v_item_type='car' then
      perform 1 from erp_cars
      where company_id=p_company_id and id=v_item_id and not is_deleted;
    else
      perform 1 from erp_inventory
      where company_id=p_company_id and id=v_item_id and not is_deleted;
    end if;
    if not found then raise exception 'order item not found'; end if;

    v_subtotal := v_subtotal + v_quantity*v_unit_amount;
  end loop;
  return round(v_subtotal,2);
end $$;

create or replace function public.erp_create_cloud_sales_order(
  p_company_id uuid,p_customer_id text,p_currency text,p_exchange_rate numeric,
  p_items jsonb,p_opportunity_id text default null,p_discount numeric default 0,
  p_notes text default null
) returns uuid
language plpgsql security definer set search_path=public as $$
declare
  v_order_id uuid:=gen_random_uuid();
  v_number text:='SO-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');
  v_subtotal numeric;
  v_item jsonb;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  if trim(coalesce(p_customer_id,''))='' then raise exception 'customer required'; end if;
  if p_currency not in ('USD','IQD') or coalesce(p_exchange_rate,0)<=0 then
    raise exception 'invalid currency or exchange rate';
  end if;
  perform 1 from erp_customers
  where company_id=p_company_id and id=p_customer_id and not is_deleted;
  if not found then raise exception 'customer not found'; end if;

  v_subtotal:=public.erp_cloud_commercial_items_subtotal(p_company_id,p_items,false);
  if coalesce(p_discount,-1)<0 or p_discount>v_subtotal then
    raise exception 'invalid discount';
  end if;

  insert into erp_sales_orders_cloud(
    id,company_id,order_number,customer_id,opportunity_id,status,currency,
    exchange_rate,subtotal,discount,total,notes
  ) values(
    v_order_id,p_company_id,v_number,p_customer_id,nullif(trim(p_opportunity_id),''),
    'draft',p_currency,p_exchange_rate,v_subtotal,p_discount,
    v_subtotal-p_discount,p_notes
  );
  for v_item in select value from jsonb_array_elements(p_items) loop
    insert into erp_sales_order_items_cloud(
      company_id,order_id,item_type,item_id,description,quantity,unit_price,line_total
    ) values(
      p_company_id,v_order_id,lower(v_item->>'itemType'),v_item->>'itemId',
      v_item->>'description',(v_item->>'quantity')::int,(v_item->>'unitPrice')::numeric,
      (v_item->>'quantity')::numeric*(v_item->>'unitPrice')::numeric
    );
  end loop;
  return v_order_id;
end $$;

create or replace function public.erp_create_cloud_purchase_order(
  p_company_id uuid,p_supplier_id text,p_currency text,p_exchange_rate numeric,
  p_items jsonb,p_discount numeric default 0,p_notes text default null
) returns uuid
language plpgsql security definer set search_path=public as $$
declare
  v_order_id uuid:=gen_random_uuid();
  v_number text:='PO-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');
  v_subtotal numeric;
  v_item jsonb;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  if trim(coalesce(p_supplier_id,''))='' then raise exception 'supplier required'; end if;
  if p_currency not in ('USD','IQD') or coalesce(p_exchange_rate,0)<=0 then
    raise exception 'invalid currency or exchange rate';
  end if;
  perform 1 from erp_suppliers
  where company_id=p_company_id and id=p_supplier_id and not is_deleted;
  if not found then raise exception 'supplier not found'; end if;

  v_subtotal:=public.erp_cloud_commercial_items_subtotal(p_company_id,p_items,true);
  if coalesce(p_discount,-1)<0 or p_discount>v_subtotal then
    raise exception 'invalid discount';
  end if;

  insert into erp_purchase_orders_cloud(
    id,company_id,order_number,supplier_id,status,currency,exchange_rate,
    subtotal,discount,total,notes
  ) values(
    v_order_id,p_company_id,v_number,p_supplier_id,'draft',p_currency,p_exchange_rate,
    v_subtotal,p_discount,v_subtotal-p_discount,p_notes
  );
  for v_item in select value from jsonb_array_elements(p_items) loop
    insert into erp_purchase_order_items_cloud(
      company_id,order_id,item_type,item_id,description,quantity,unit_cost,line_total
    ) values(
      p_company_id,v_order_id,lower(v_item->>'itemType'),v_item->>'itemId',
      v_item->>'description',(v_item->>'quantity')::int,(v_item->>'unitCost')::numeric,
      (v_item->>'quantity')::numeric*(v_item->>'unitCost')::numeric
    );
  end loop;
  return v_order_id;
end $$;

create or replace function public.erp_approve_cloud_sales_order(
  p_company_id uuid,p_order_id uuid
) returns void
language plpgsql security definer set search_path=public as $$
declare v_status text;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  select status into v_status from erp_sales_orders_cloud
  where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found then raise exception 'order not found'; end if;
  if v_status<>'draft' then raise exception 'invalid order status'; end if;
  update erp_sales_orders_cloud set status='approved',updated_at=now()
  where company_id=p_company_id and id=p_order_id;
end $$;

create or replace function public.erp_update_cloud_sales_order(
  p_company_id uuid,p_order_id uuid,p_customer_id text,p_currency text,
  p_exchange_rate numeric,p_discount numeric,p_items jsonb,p_notes text default null
) returns void
language plpgsql security definer set search_path=public as $$
declare v_subtotal numeric; v_item jsonb;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  perform 1 from erp_sales_orders_cloud
  where company_id=p_company_id and id=p_order_id and status='draft' and not is_deleted
  for update;
  if not found then raise exception 'draft not found'; end if;
  if p_currency not in ('USD','IQD') or coalesce(p_exchange_rate,0)<=0 then
    raise exception 'invalid currency or exchange rate';
  end if;
  perform 1 from erp_customers
  where company_id=p_company_id and id=p_customer_id and not is_deleted;
  if not found then raise exception 'customer not found'; end if;
  v_subtotal:=public.erp_cloud_commercial_items_subtotal(p_company_id,p_items,false);
  if coalesce(p_discount,-1)<0 or p_discount>v_subtotal then
    raise exception 'invalid discount';
  end if;

  update erp_sales_orders_cloud set
    customer_id=p_customer_id,currency=p_currency,exchange_rate=p_exchange_rate,
    subtotal=v_subtotal,discount=p_discount,total=v_subtotal-p_discount,
    notes=p_notes,updated_at=now()
  where company_id=p_company_id and id=p_order_id;
  update erp_sales_order_items_cloud set is_deleted=true
  where company_id=p_company_id and order_id=p_order_id and not is_deleted;
  for v_item in select value from jsonb_array_elements(p_items) loop
    insert into erp_sales_order_items_cloud(
      company_id,order_id,item_type,item_id,description,quantity,unit_price,line_total
    ) values(
      p_company_id,p_order_id,lower(v_item->>'itemType'),v_item->>'itemId',
      v_item->>'description',(v_item->>'quantity')::int,(v_item->>'unitPrice')::numeric,
      (v_item->>'quantity')::numeric*(v_item->>'unitPrice')::numeric
    );
  end loop;
end $$;

create or replace function public.erp_reopen_cloud_sales_order(
  p_company_id uuid,p_order_id uuid
) returns void
language plpgsql security definer set search_path=public as $$
declare v_status text;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  select status into v_status from erp_sales_orders_cloud
  where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found then raise exception 'order not found'; end if;
  if v_status<>'approved' then raise exception 'only approved order can be reopened'; end if;
  if exists (
    select 1 from erp_commercial_workflow_documents
    where company_id=p_company_id and parent_id=p_order_id and module='sales'
      and not is_deleted and status<>'cancelled'
  ) then raise exception 'order has active workflow documents'; end if;
  update erp_sales_orders_cloud set status='draft',updated_at=now()
  where company_id=p_company_id and id=p_order_id;
end $$;

create or replace function public.erp_delete_cloud_sales_order(
  p_company_id uuid,p_order_id uuid
) returns void
language plpgsql security definer set search_path=public as $$
declare v_status text;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  select status into v_status from erp_sales_orders_cloud
  where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found then raise exception 'order not found'; end if;
  if v_status<>'draft' then raise exception 'only draft order can be deleted'; end if;
  if exists (
    select 1 from erp_commercial_workflow_documents
    where company_id=p_company_id and parent_id=p_order_id and module='sales'
      and not is_deleted and status<>'cancelled'
  ) then raise exception 'order has active workflow documents'; end if;
  update erp_sales_order_items_cloud set is_deleted=true
  where company_id=p_company_id and order_id=p_order_id and not is_deleted;
  update erp_sales_orders_cloud set is_deleted=true,deleted_at=now(),updated_at=now()
  where company_id=p_company_id and id=p_order_id;
end $$;

create or replace function public.erp_approve_cloud_purchase_order(
  p_company_id uuid,p_order_id uuid
) returns void
language plpgsql security definer set search_path=public as $$
declare v_status text;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  select status into v_status from erp_purchase_orders_cloud
  where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found then raise exception 'order not found'; end if;
  if v_status<>'draft' then raise exception 'invalid order status'; end if;
  update erp_purchase_orders_cloud set status='approved',updated_at=now()
  where company_id=p_company_id and id=p_order_id;
end $$;

create or replace function public.erp_update_cloud_purchase_order(
  p_company_id uuid,p_order_id uuid,p_supplier_id text,p_currency text,
  p_exchange_rate numeric,p_discount numeric,p_items jsonb,p_notes text default null
) returns void
language plpgsql security definer set search_path=public as $$
declare v_subtotal numeric; v_item jsonb;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  perform 1 from erp_purchase_orders_cloud
  where company_id=p_company_id and id=p_order_id and status='draft' and not is_deleted
  for update;
  if not found then raise exception 'draft not found'; end if;
  if p_currency not in ('USD','IQD') or coalesce(p_exchange_rate,0)<=0 then
    raise exception 'invalid currency or exchange rate';
  end if;
  perform 1 from erp_suppliers
  where company_id=p_company_id and id=p_supplier_id and not is_deleted;
  if not found then raise exception 'supplier not found'; end if;
  v_subtotal:=public.erp_cloud_commercial_items_subtotal(p_company_id,p_items,true);
  if coalesce(p_discount,-1)<0 or p_discount>v_subtotal then
    raise exception 'invalid discount';
  end if;

  update erp_purchase_orders_cloud set
    supplier_id=p_supplier_id,currency=p_currency,exchange_rate=p_exchange_rate,
    subtotal=v_subtotal,discount=p_discount,total=v_subtotal-p_discount,
    notes=p_notes,updated_at=now()
  where company_id=p_company_id and id=p_order_id;
  update erp_purchase_order_items_cloud set is_deleted=true
  where company_id=p_company_id and order_id=p_order_id and not is_deleted;
  for v_item in select value from jsonb_array_elements(p_items) loop
    insert into erp_purchase_order_items_cloud(
      company_id,order_id,item_type,item_id,description,quantity,unit_cost,line_total
    ) values(
      p_company_id,p_order_id,lower(v_item->>'itemType'),v_item->>'itemId',
      v_item->>'description',(v_item->>'quantity')::int,(v_item->>'unitCost')::numeric,
      (v_item->>'quantity')::numeric*(v_item->>'unitCost')::numeric
    );
  end loop;
end $$;

create or replace function public.erp_reopen_cloud_purchase_order(
  p_company_id uuid,p_order_id uuid
) returns void
language plpgsql security definer set search_path=public as $$
declare v_status text;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  select status into v_status from erp_purchase_orders_cloud
  where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found then raise exception 'order not found'; end if;
  if v_status<>'approved' then raise exception 'only approved order can be reopened'; end if;
  if exists (
    select 1 from erp_commercial_workflow_documents
    where company_id=p_company_id and parent_id=p_order_id and module='purchases'
      and not is_deleted and status<>'cancelled'
  ) then raise exception 'order has active workflow documents'; end if;
  update erp_purchase_orders_cloud set status='draft',updated_at=now()
  where company_id=p_company_id and id=p_order_id;
end $$;

create or replace function public.erp_delete_cloud_purchase_order(
  p_company_id uuid,p_order_id uuid
) returns void
language plpgsql security definer set search_path=public as $$
declare v_status text;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  select status into v_status from erp_purchase_orders_cloud
  where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found then raise exception 'order not found'; end if;
  if v_status<>'draft' then raise exception 'only draft order can be deleted'; end if;
  if exists (
    select 1 from erp_commercial_workflow_documents
    where company_id=p_company_id and parent_id=p_order_id and module='purchases'
      and not is_deleted and status<>'cancelled'
  ) then raise exception 'order has active workflow documents'; end if;
  update erp_purchase_order_items_cloud set is_deleted=true
  where company_id=p_company_id and order_id=p_order_id and not is_deleted;
  update erp_purchase_orders_cloud set is_deleted=true,deleted_at=now(),updated_at=now()
  where company_id=p_company_id and id=p_order_id;
end $$;

create or replace function public.erp_create_cloud_sales_delivery(
  p_company_id uuid,p_order_id uuid,p_warehouse_id text default null,p_notes text default null
) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_id uuid:=gen_random_uuid();
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  perform 1 from erp_sales_orders_cloud
  where company_id=p_company_id and id=p_order_id and status='approved' and not is_deleted
  for update;
  if not found then raise exception 'approved sales order not found'; end if;
  if nullif(trim(p_warehouse_id),'') is not null then
    perform 1 from erp_warehouses
    where company_id=p_company_id and id=p_warehouse_id and not is_deleted;
    if not found then raise exception 'warehouse not found'; end if;
  end if;
  if exists (
    select 1 from erp_commercial_workflow_documents
    where company_id=p_company_id and parent_id=p_order_id and module='sales'
      and document_type='delivery' and not is_deleted and status<>'cancelled'
  ) then raise exception 'active delivery already exists'; end if;
  insert into erp_commercial_workflow_documents(
    id,company_id,module,document_type,parent_id,document_number,warehouse_id,payload
  ) values(
    v_id,p_company_id,'sales','delivery',p_order_id,
    'SD-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS'),nullif(trim(p_warehouse_id),''),
    jsonb_build_object('notes',p_notes)
  );
  return v_id;
end $$;

create or replace function public.erp_create_cloud_purchase_receipt(
  p_company_id uuid,p_order_id uuid,p_warehouse_id text default null,p_notes text default null
) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_id uuid:=gen_random_uuid();
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  if nullif(trim(p_warehouse_id),'') is null then raise exception 'warehouse required'; end if;
  perform 1 from erp_purchase_orders_cloud
  where company_id=p_company_id and id=p_order_id and status='approved' and not is_deleted
  for update;
  if not found then raise exception 'approved purchase order not found'; end if;
  perform 1 from erp_warehouses
  where company_id=p_company_id and id=p_warehouse_id and not is_deleted;
  if not found then raise exception 'warehouse not found'; end if;
  if exists (
    select 1 from erp_commercial_workflow_documents
    where company_id=p_company_id and parent_id=p_order_id and module='purchases'
      and document_type='receipt' and not is_deleted and status<>'cancelled'
  ) then raise exception 'active receipt already exists'; end if;
  insert into erp_commercial_workflow_documents(
    id,company_id,module,document_type,parent_id,document_number,warehouse_id,payload
  ) values(
    v_id,p_company_id,'purchases','receipt',p_order_id,
    'PR-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS'),p_warehouse_id,
    jsonb_build_object('notes',p_notes)
  );
  return v_id;
end $$;

create or replace function public.erp_create_cloud_sales_workflow_invoice(
  p_company_id uuid,p_order_id uuid
) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_id uuid:=gen_random_uuid(); v_total numeric; v_currency text;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  select total,currency into v_total,v_currency from erp_sales_orders_cloud
  where company_id=p_company_id and id=p_order_id and status='approved' and not is_deleted
  for update;
  if not found then raise exception 'approved sales order not found'; end if;
  if not exists (
    select 1 from erp_commercial_workflow_documents
    where company_id=p_company_id and parent_id=p_order_id and module='sales'
      and document_type='delivery' and status='approved' and not is_deleted
  ) then raise exception 'approved delivery required'; end if;
  if exists (
    select 1 from erp_commercial_workflow_documents
    where company_id=p_company_id and parent_id=p_order_id and module='sales'
      and document_type='invoice' and not is_deleted and status<>'cancelled'
  ) then raise exception 'active invoice already exists'; end if;
  insert into erp_commercial_workflow_documents(
    id,company_id,module,document_type,parent_id,document_number,warehouse_id,payload
  ) values(
    v_id,p_company_id,'sales','invoice',p_order_id,
    'SI-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS'),null,
    jsonb_build_object(
      'currency',v_currency,'totalAmount',v_total,'remainingAmount',v_total,
      'paymentStatus','unpaid','payments','[]'::jsonb
    )
  );
  return v_id;
end $$;

create or replace function public.erp_create_cloud_purchase_workflow_invoice(
  p_company_id uuid,p_order_id uuid
) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_id uuid:=gen_random_uuid(); v_total numeric; v_currency text;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  select total,currency into v_total,v_currency from erp_purchase_orders_cloud
  where company_id=p_company_id and id=p_order_id and status='approved' and not is_deleted
  for update;
  if not found then raise exception 'approved purchase order not found'; end if;
  if not exists (
    select 1 from erp_commercial_workflow_documents
    where company_id=p_company_id and parent_id=p_order_id and module='purchases'
      and document_type='receipt' and status='approved' and not is_deleted
  ) then raise exception 'approved receipt required'; end if;
  if exists (
    select 1 from erp_commercial_workflow_documents
    where company_id=p_company_id and parent_id=p_order_id and module='purchases'
      and document_type='invoice' and not is_deleted and status<>'cancelled'
  ) then raise exception 'active invoice already exists'; end if;
  insert into erp_commercial_workflow_documents(
    id,company_id,module,document_type,parent_id,document_number,warehouse_id,payload
  ) values(
    v_id,p_company_id,'purchases','invoice',p_order_id,
    'PI-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS'),null,
    jsonb_build_object(
      'currency',v_currency,'totalAmount',v_total,'remainingAmount',v_total,
      'paymentStatus','unpaid','payments','[]'::jsonb
    )
  );
  return v_id;
end $$;

create or replace function public.erp_approve_cloud_sales_delivery(p_company_id uuid,p_delivery_id uuid)
returns void language sql security definer set search_path=public as $$
 select public.erp_cloud_workflow_transition(p_company_id,'sales','delivery',p_delivery_id,array['draft'],'approved','{}'::jsonb)
$$;
create or replace function public.erp_cancel_cloud_sales_delivery(p_company_id uuid,p_delivery_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
 if exists(select 1 from erp_commercial_workflow_documents d join erp_commercial_workflow_documents i on i.company_id=d.company_id and i.parent_id=d.parent_id and i.module='sales' and i.document_type='invoice' and not i.is_deleted and i.status<>'cancelled' where d.company_id=p_company_id and d.id=p_delivery_id) then raise exception 'delivery has active invoice'; end if;
 perform public.erp_cloud_workflow_transition(p_company_id,'sales','delivery',p_delivery_id,array['approved','draft'],'cancelled','{}'::jsonb);
end $$;
create or replace function public.erp_approve_cloud_purchase_receipt(p_company_id uuid,p_receipt_id uuid)
returns void language sql security definer set search_path=public as $$
 select public.erp_cloud_workflow_transition(p_company_id,'purchases','receipt',p_receipt_id,array['draft'],'approved','{}'::jsonb)
$$;
create or replace function public.erp_cancel_cloud_purchase_receipt(p_company_id uuid,p_receipt_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
 if exists(select 1 from erp_commercial_workflow_documents r join erp_commercial_workflow_documents i on i.company_id=r.company_id and i.parent_id=r.parent_id and i.module='purchases' and i.document_type='invoice' and not i.is_deleted and i.status<>'cancelled' where r.company_id=p_company_id and r.id=p_receipt_id) then raise exception 'receipt has active invoice'; end if;
 perform public.erp_cloud_workflow_transition(p_company_id,'purchases','receipt',p_receipt_id,array['approved','draft'],'cancelled','{}'::jsonb);
end $$;
create or replace function public.erp_approve_cloud_sales_workflow_invoice(p_company_id uuid,p_invoice_id uuid)
returns void language sql security definer set search_path=public as $$
 select public.erp_cloud_workflow_transition(p_company_id,'sales','invoice',p_invoice_id,array['draft'],'approved','{}'::jsonb)
$$;
create or replace function public.erp_cancel_cloud_sales_workflow_invoice(p_company_id uuid,p_invoice_id uuid,p_reason text default null)
returns void language plpgsql security definer set search_path=public as $$
declare v_payload jsonb;
begin
 if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
 select payload into v_payload from erp_commercial_workflow_documents where company_id=p_company_id and id=p_invoice_id and module='sales' and document_type='invoice' and not is_deleted for update;
 if not found then raise exception 'invoice not found'; end if;
 if jsonb_array_length(coalesce(v_payload->'payments','[]'::jsonb))>0 then raise exception 'paid invoice requires coordinated reversal'; end if;
 perform public.erp_cloud_workflow_transition(p_company_id,'sales','invoice',p_invoice_id,array['approved','draft'],'cancelled',jsonb_build_object('reason',p_reason));
end $$;
create or replace function public.erp_approve_cloud_purchase_workflow_invoice(p_company_id uuid,p_invoice_id uuid)
returns void language sql security definer set search_path=public as $$
 select public.erp_cloud_workflow_transition(p_company_id,'purchases','invoice',p_invoice_id,array['draft'],'approved','{}'::jsonb)
$$;
create or replace function public.erp_cancel_cloud_purchase_workflow_invoice(p_company_id uuid,p_invoice_id uuid,p_reason text default null)
returns void language plpgsql security definer set search_path=public as $$
declare v_payload jsonb;
begin
 if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
 select payload into v_payload from erp_commercial_workflow_documents where company_id=p_company_id and id=p_invoice_id and module='purchases' and document_type='invoice' and not is_deleted for update;
 if not found then raise exception 'invoice not found'; end if;
 if jsonb_array_length(coalesce(v_payload->'payments','[]'::jsonb))>0 then raise exception 'paid invoice requires coordinated reversal'; end if;
 perform public.erp_cloud_workflow_transition(p_company_id,'purchases','invoice',p_invoice_id,array['approved','draft'],'cancelled',jsonb_build_object('reason',p_reason));
end $$;

create or replace function public.erp_apply_cloud_workflow_invoice_payment(
  p_company_id uuid,p_invoice_id uuid,p_module text,p_payment jsonb
) returns void
language plpgsql security definer set search_path=public as $$
declare
  v_invoice erp_commercial_workflow_documents%rowtype;
  v_invoice_currency text;
  v_payment_currency text;
  v_mode text;
  v_remaining numeric;
  v_requested numeric;
  v_applied numeric;
  v_cash numeric;
  v_rate numeric;
  v_expected numeric;
  v_equivalent numeric;
  v_difference numeric;
  v_next numeric;
  v_tolerance numeric;
  v_enriched jsonb;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  if p_module not in ('sales','purchases') then raise exception 'invalid workflow module'; end if;
  select * into v_invoice from erp_commercial_workflow_documents
  where company_id=p_company_id and id=p_invoice_id and module=p_module
    and document_type='invoice' and status='approved' and not is_deleted
  for update;
  if not found then raise exception 'approved invoice not found'; end if;

  v_invoice_currency:=coalesce(v_invoice.payload->>'currency','');
  v_payment_currency:=coalesce(p_payment->>'paymentCurrency','');
  v_mode:=coalesce(p_payment->>'settlementMode','partial');
  v_remaining:=coalesce(nullif(v_invoice.payload->>'remainingAmount','')::numeric,0);
  v_requested:=coalesce(nullif(p_payment->>'invoiceAmount','')::numeric,0);
  v_cash:=coalesce(nullif(p_payment->>'cashAmount','')::numeric,0);
  v_rate:=coalesce(nullif(p_payment->>'exchangeRate','')::numeric,0);

  if v_invoice_currency not in ('USD','IQD') or v_payment_currency not in ('USD','IQD') then
    raise exception 'unsupported currency';
  end if;
  if trim(coalesce(p_payment->>'cashAccountId',''))='' or v_remaining<=0 or v_cash<=0 or v_rate<=0 then
    raise exception 'invalid payment';
  end if;
  perform 1
  from erp_cash_accounts c
  where c.company_id=p_company_id
    and c.id=trim(p_payment->>'cashAccountId')
    and not c.is_deleted
    and coalesce(nullif(c.data->>'isActive','')::boolean,true);
  if not found then raise exception 'cash account not found'; end if;
  if v_mode not in ('partial','fullWithExchangeDifference') then
    raise exception 'invalid settlement mode';
  end if;
  v_applied:=case when v_mode='fullWithExchangeDifference' then v_remaining else v_requested end;
  if v_applied<=0 or v_applied>v_remaining+0.01 then raise exception 'payment exceeds remaining'; end if;

  v_expected:=case
    when v_invoice_currency=v_payment_currency then v_applied
    when v_invoice_currency='USD' and v_payment_currency='IQD' then v_applied*v_rate
    else v_applied/v_rate
  end;
  v_equivalent:=case
    when v_invoice_currency=v_payment_currency then v_cash
    when v_invoice_currency='USD' and v_payment_currency='IQD' then v_cash/v_rate
    else v_cash*v_rate
  end;
  v_difference:=case when v_mode='fullWithExchangeDifference' then v_equivalent-v_applied else 0 end;
  if v_mode='partial' then
    v_tolerance:=greatest(0.01,least(1000.0,abs(v_expected)*0.005));
    if abs(v_cash-v_expected)>v_tolerance then raise exception 'cash_amount_mismatch'; end if;
  end if;
  v_next:=greatest(0,v_remaining-v_applied);
  v_enriched:=p_payment||jsonb_build_object(
    'invoiceCurrency',v_invoice_currency,
    'appliedInvoiceAmount',v_applied,
    'expectedCashAmount',v_expected,
    'actualInvoiceEquivalent',v_equivalent,
    'exchangeDifference',v_difference,
    'previousRemainingAmount',v_remaining,
    'remainingAmount',v_next
  );
  update erp_commercial_workflow_documents set
    payload=jsonb_set(
      jsonb_set(
        jsonb_set(payload,'{payments}',coalesce(payload->'payments','[]'::jsonb)||jsonb_build_array(v_enriched)),
        '{remainingAmount}',to_jsonb(v_next)
      ),
      '{paymentStatus}',to_jsonb((case when v_next<=0.01 then 'paid' else 'partial' end)::text)
    ),
    updated_at=now()
  where id=p_invoice_id and company_id=p_company_id;
end $$;

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

grant execute on all functions in schema public to authenticated;
