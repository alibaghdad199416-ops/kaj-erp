begin;

create table if not exists public.erp_saved_report_filters (like public.erp_cars including all);
create table if not exists public.erp_bi_daily_snapshots (like public.erp_cars including all);
create table if not exists public.erp_bi_alerts (like public.erp_cars including all);

alter table public.erp_saved_report_filters enable row level security;
alter table public.erp_bi_daily_snapshots enable row level security;
alter table public.erp_bi_alerts enable row level security;

do $$ declare t text; begin
  foreach t in array array['erp_saved_report_filters','erp_bi_daily_snapshots','erp_bi_alerts'] loop
    execute format('drop policy if exists tenant_select on public.%I',t);
    execute format('create policy tenant_select on public.%I for select using (public.is_company_member(company_id))',t);
    execute format('drop policy if exists tenant_manage on public.%I',t);
    execute format('create policy tenant_manage on public.%I for all using (public.is_company_member(company_id)) with check (public.is_company_member(company_id))',t);
  end loop;
end $$;

create or replace function public.erp_cloud_dashboard_snapshot(p_company_id uuid,p_reference_day date default current_date)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r jsonb; begin
 if not public.is_company_member(p_company_id) then raise exception 'access denied'; end if;
 select jsonb_build_object(
  'totalCars',(select count(*) from erp_cars where company_id=p_company_id and not coalesce(is_deleted,false)),
  'availableCars',(select count(*) from erp_cars where company_id=p_company_id and not coalesce(is_deleted,false) and lower(coalesce(data->>'status','')) in ('available','متاحة','متوفر','متوفرة')),
  'reservedCars',(select count(*) from erp_cars where company_id=p_company_id and not coalesce(is_deleted,false) and lower(coalesce(data->>'status','')) in ('selling','pending_sale','قيد البيع','reserved','محجوزة','محجوز')),
  'soldCars',(select count(*) from erp_cars where company_id=p_company_id and not coalesce(is_deleted,false) and lower(coalesce(data->>'status','')) in ('sold','مباعة','مباع')),
  'totalCustomers',(select count(*) from erp_customers where company_id=p_company_id and not coalesce(is_deleted,false)),
  'totalSuppliers',(select count(*) from erp_suppliers where company_id=p_company_id and not coalesce(is_deleted,false)),
  'totalSales',(select coalesce(sum((data->>'salePrice')::numeric),0) from erp_sales where company_id=p_company_id and not coalesce(is_deleted,false)),
  'todaySales',(select coalesce(sum((data->>'salePrice')::numeric),0) from erp_sales where company_id=p_company_id and not coalesce(is_deleted,false) and (data->>'saleDate')::date=p_reference_day),
  'totalPurchases',(select coalesce(sum((data->>'totalAmount')::numeric),0) from erp_purchases where company_id=p_company_id and not coalesce(is_deleted,false)),
  'totalExpenses',(select coalesce(sum((data->>'amount')::numeric),0) from erp_expenses where company_id=p_company_id and not coalesce(is_deleted,false)),
  'netProfit', (select coalesce(sum((data->>'salePrice')::numeric),0) from erp_sales where company_id=p_company_id and not coalesce(is_deleted,false))-(select coalesce(sum((data->>'totalAmount')::numeric),0) from erp_purchases where company_id=p_company_id and not coalesce(is_deleted,false))-(select coalesce(sum((data->>'amount')::numeric),0) from erp_expenses where company_id=p_company_id and not coalesce(is_deleted,false)),
  'cashBalanceUsd',(select coalesce(sum(case when data->>'currency'='USD' then case when data->>'type'='receipt' then (data->>'amount')::numeric else -(data->>'amount')::numeric end else 0 end),0) from erp_cash_transactions where company_id=p_company_id and not coalesce(is_deleted,false)),
  'cashBalanceIqd',(select coalesce(sum(case when data->>'currency'='IQD' then case when data->>'type'='receipt' then (data->>'amount')::numeric else -(data->>'amount')::numeric end else 0 end),0) from erp_cash_transactions where company_id=p_company_id and not coalesce(is_deleted,false)),
  'inventoryValue',(select coalesce(sum((data->>'quantity')::numeric*(data->>'averageUnitCost')::numeric),0) from erp_warehouse_stock where company_id=p_company_id and not coalesce(is_deleted,false)),
  'totalReceivables',(select coalesce(sum((data->>'remainingAmount')::numeric),0) from erp_sales where company_id=p_company_id and not coalesce(is_deleted,false)),
  'totalPayables',(select coalesce(sum((data->>'remainingAmount')::numeric),0) from erp_purchases where company_id=p_company_id and not coalesce(is_deleted,false)),
  'pendingPurchaseCars',(select count(*) from erp_cars where company_id=p_company_id and not coalesce(is_deleted,false) and lower(coalesce(data->>'status','')) in ('pending_purchase','قيد الشراء','قيد شراء')),
  'lowStockItems',(select count(*) from erp_warehouse_stock where company_id=p_company_id and not coalesce(is_deleted,false) and coalesce((data->>'quantity')::numeric,0)<=coalesce((data->>'minimumQuantity')::numeric,0)),
  'carsWithoutWarehouse',(select count(*) from erp_cars where company_id=p_company_id and not coalesce(is_deleted,false) and coalesce(trim(data->>'warehouseId'),'')=''),
  'activeReservations',(select count(*) from erp_reservations where company_id=p_company_id and not coalesce(is_deleted,false) and data->>'status'='active'),
  'overdueInstallments',(select count(*) from erp_installments where company_id=p_company_id and not coalesce(is_deleted,false) and coalesce((data->>'remainingAmount')::numeric,0)>0 and (data->>'dueDate')::date<p_reference_day),
  'dueSoonInstallments',(select count(*) from erp_installments where company_id=p_company_id and not coalesce(is_deleted,false) and coalesce((data->>'remainingAmount')::numeric,0)>0 and (data->>'dueDate')::date between p_reference_day and p_reference_day+7),
  'outstandingInstallments',(select coalesce(sum((data->>'remainingAmount')::numeric),0) from erp_installments where company_id=p_company_id and not coalesce(is_deleted,false)),
  'salesTrend',(select coalesce(jsonb_agg(jsonb_build_object('date',d::text,'amount',coalesce(x.amount,0)) order by d),'[]'::jsonb) from generate_series(p_reference_day-6,p_reference_day,'1 day') d left join lateral (select sum((data->>'salePrice')::numeric) amount from erp_sales where company_id=p_company_id and not coalesce(is_deleted,false) and (data->>'saleDate')::date=d::date) x on true),
  'recentActivities','[]'::jsonb,
  'upcomingInstallments',(select coalesce(jsonb_agg(z order by z->>'dueDate'),'[]'::jsonb) from (select jsonb_build_object('customerName',coalesce(c.data->>'name','عميل'),'installmentNo',coalesce((i.data->>'installmentNo')::int,0),'dueDate',i.data->>'dueDate','remainingAmount',coalesce((i.data->>'remainingAmount')::numeric,0),'isOverdue',(i.data->>'dueDate')::date<p_reference_day) z from erp_installments i left join erp_sales s on s.company_id=i.company_id and s.id=i.data->>'saleId' left join erp_customers c on c.company_id=s.company_id and c.id=s.data->>'customerId' where i.company_id=p_company_id and not coalesce(i.is_deleted,false) and coalesce((i.data->>'remainingAmount')::numeric,0)>0 and (i.data->>'dueDate')::date<=p_reference_day+7 limit 7) q),
  'generatedAt',clock_timestamp()
 ) into r; return r; end $$;

create or replace function public.erp_cloud_reports_summary(p_company_id uuid,p_start_date date default null,p_end_date date default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare d1 date:=coalesce(p_start_date,current_date-365); d2 date:=coalesce(p_end_date,current_date); base jsonb; begin
 if not public.is_company_member(p_company_id) then raise exception 'access denied'; end if;
 base:=public.erp_cloud_dashboard_snapshot(p_company_id,d2);
 return base || jsonb_build_object(
  'totalInventoryItems',(select coalesce(sum((data->>'quantity')::numeric),0) from erp_inventory where company_id=p_company_id and not coalesce(is_deleted,false)),
  'totalPaidSales',(select coalesce(sum((data->>'paidAmount')::numeric),0) from erp_sales where company_id=p_company_id and not coalesce(is_deleted,false) and (data->>'saleDate')::date between d1 and d2),
  'totalPurchaseDebt',(select coalesce(sum((data->>'remainingAmount')::numeric),0) from erp_purchases where company_id=p_company_id and not coalesce(is_deleted,false) and (data->>'purchaseDate')::date between d1 and d2),
  'monthlyPoints',(select coalesce(jsonb_agg(jsonb_build_object('label',to_char(m,'YYYY-MM'),'sales',coalesce(s.v,0),'expenses',coalesce(e.v,0),'purchases',coalesce(p.v,0)) order by m),'[]'::jsonb) from generate_series(date_trunc('month',d2)-interval '11 month',date_trunc('month',d2),'1 month') m left join lateral(select sum((data->>'salePrice')::numeric) v from erp_sales where company_id=p_company_id and not coalesce(is_deleted,false) and (data->>'saleDate')::date>=m::date and (data->>'saleDate')::date<(m+interval '1 month')::date)s on true left join lateral(select sum((data->>'amount')::numeric) v from erp_expenses where company_id=p_company_id and not coalesce(is_deleted,false) and (data->>'date')::date>=m::date and (data->>'date')::date<(m+interval '1 month')::date)e on true left join lateral(select sum((data->>'totalAmount')::numeric) v from erp_purchases where company_id=p_company_id and not coalesce(is_deleted,false) and (data->>'purchaseDate')::date>=m::date and (data->>'purchaseDate')::date<(m+interval '1 month')::date)p on true)
 ); end $$;

create or replace function public.erp_cloud_specialized_report(p_company_id uuid,p_module text,p_filter jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$ declare q jsonb; begin if not public.is_company_member(p_company_id) then raise exception 'access denied'; end if;
 case p_module
 when 'sales' then select coalesce(jsonb_agg(s.data||jsonb_build_object('id',s.id,'brand',c.data->>'brand','model',c.data->>'model','chassis',c.data->>'chassis','customerName',cu.data->>'name')),'[]') into q from erp_sales s left join erp_cars c on c.company_id=s.company_id and c.id=s.data->>'carId' left join erp_customers cu on cu.company_id=s.company_id and cu.id=s.data->>'customerId' where s.company_id=p_company_id and not coalesce(s.is_deleted,false);
 when 'inventory' then select coalesce(jsonb_agg(i.data||jsonb_build_object('id',i.id)),'[]') into q from erp_inventory i where i.company_id=p_company_id and not coalesce(i.is_deleted,false);
 when 'expenses' then select coalesce(jsonb_agg(e.data||jsonb_build_object('id',e.id)),'[]') into q from erp_expenses e where e.company_id=p_company_id and not coalesce(e.is_deleted,false);
 when 'maintenance' then select coalesce(jsonb_agg(m.data||jsonb_build_object('id',m.id)),'[]') into q from erp_maintenance_orders m where m.company_id=p_company_id and not coalesce(m.is_deleted,false);
 else q:='[]'::jsonb; end case; return q; end $$;

create or replace function public.erp_save_cloud_report_filter(p_company_id uuid,p_module text,p_name text,p_filter jsonb)
returns text language plpgsql security definer set search_path=public as $$ declare v text:=gen_random_uuid()::text; begin if not public.is_company_member(p_company_id) then raise exception 'access denied'; end if; insert into erp_saved_report_filters(company_id,id,data,created_by,updated_by) values(p_company_id,v,jsonb_build_object('module',p_module,'name',p_name,'filterJson',p_filter,'userId',auth.uid(),'createdAt',clock_timestamp()),auth.uid(),auth.uid()); return v; end $$;
create or replace function public.erp_list_cloud_report_filters(p_company_id uuid,p_module text) returns jsonb language sql security definer set search_path=public as $$ select coalesce(jsonb_agg(data||jsonb_build_object('id',id) order by created_at desc),'[]') from erp_saved_report_filters where company_id=p_company_id and not coalesce(is_deleted,false) and data->>'module'=p_module and public.is_company_member(p_company_id) $$;

create or replace function public.erp_cloud_contextual_report(p_company_id uuid,p_module text,p_start_date date default null,p_end_date date default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
 d1 date:=coalesce(p_start_date,current_date-365);
 d2 date:=coalesce(p_end_date,current_date);
 rows_data jsonb;
begin
 if not public.is_company_member(p_company_id) then raise exception 'access denied'; end if;

 if lower(p_module) in ('sales','sales_workflow') then
  select coalesce(jsonb_agg(jsonb_build_array(
   coalesce(data->>'invoiceNumber',data->>'orderNumber',id),
   coalesce(data->>'customerName',''),
   coalesce(data->>'settlementMode','partial'),
   coalesce(data->>'expectedCashAmount','0'),
   coalesce(data->>'exchangeDifference','0'),
   coalesce(data->>'paidAmount','0'),
   coalesce(data->>'remainingAmount','0')
  ) order by updated_at desc),'[]'::jsonb)
  into rows_data
  from erp_sales
  where company_id=p_company_id
    and not coalesce(is_deleted,false)
    and coalesce((data->>'saleDate')::date,created_at::date) between d1 and d2;

  return jsonb_build_array(jsonb_build_object(
   'key','sales_settlement',
   'title','تسويات المبيعات وفروقات الصرف',
   'columns',jsonb_build_array('المستند','العميل','settlementMode','expectedCashAmount','exchangeDifference','المدفوع','المتبقي'),
   'rows',rows_data
  ));
 elsif lower(p_module) in ('purchases','purchase_workflow') then
  select coalesce(jsonb_agg(jsonb_build_array(
   coalesce(data->>'invoiceNumber',data->>'orderNumber',id),
   coalesce(data->>'supplierName',''),
   coalesce(data->>'settlementMode','partial'),
   coalesce(data->>'expectedCashAmount','0'),
   coalesce(data->>'exchangeDifference','0'),
   coalesce(data->>'paidAmount','0'),
   coalesce(data->>'remainingAmount','0')
  ) order by updated_at desc),'[]'::jsonb)
  into rows_data
  from erp_purchases
  where company_id=p_company_id
    and not coalesce(is_deleted,false)
    and coalesce((data->>'purchaseDate')::date,created_at::date) between d1 and d2;

  return jsonb_build_array(jsonb_build_object(
   'key','purchase_settlement',
   'title','تسويات المشتريات وفروقات الصرف',
   'columns',jsonb_build_array('المستند','المورد','settlementMode','expectedCashAmount','exchangeDifference','المدفوع','المتبقي'),
   'rows',rows_data
  ));
 end if;

 return jsonb_build_array(jsonb_build_object(
  'key',p_module,
  'title',p_module,
  'columns',jsonb_build_array('البيان','القيمة'),
  'rows',jsonb_build_array(jsonb_build_array('مصدر البيانات','Supabase'),jsonb_build_array('الشركة',p_company_id::text))
 ));
end $$;

create or replace function public.erp_cloud_executive_bi_snapshot(p_company_id uuid,p_reference_day date default current_date) returns jsonb language plpgsql security definer set search_path=public as $$ declare d jsonb; begin d:=public.erp_cloud_dashboard_snapshot(p_company_id,p_reference_day); return jsonb_build_object('referenceDate',p_reference_day,'salesAmount',d->'totalSales','purchasesAmount',d->'totalPurchases','expensesAmount',d->'totalExpenses','netProfit',d->'netProfit','cashBalance',coalesce((d->>'cashBalanceUsd')::numeric,0)+coalesce((d->>'cashBalanceIqd')::numeric,0),'receivables',d->'totalReceivables','payables',d->'totalPayables','inventoryValue',d->'inventoryValue','salesCount',(select count(*) from erp_sales where company_id=p_company_id and not coalesce(is_deleted,false)),'activeCustomers',d->'totalCustomers','overdueInstallments',d->'overdueInstallments','overdueAmount',(select coalesce(sum((data->>'remainingAmount')::numeric),0) from erp_installments where company_id=p_company_id and not coalesce(is_deleted,false) and (data->>'dueDate')::date<p_reference_day)); end $$;

create or replace function public.erp_cloud_top_customers(p_company_id uuid,p_start date,p_end date,p_limit int default 10) returns jsonb language sql security definer set search_path=public as $$ select coalesce(jsonb_agg(x),'[]') from (select c.id "entityId",coalesce(c.data->>'name','عميل') "entityName",count(s.id) "transactionCount",coalesce(sum((s.data->>'salePrice')::numeric),0) "salesValue",coalesce(sum((s.data->>'paidAmount')::numeric),0) "collectedValue",coalesce(sum((s.data->>'remainingAmount')::numeric),0) "outstandingValue" from erp_sales s left join erp_customers c on c.company_id=s.company_id and c.id=s.data->>'customerId' where s.company_id=p_company_id and not coalesce(s.is_deleted,false) and (s.data->>'saleDate')::date between p_start and p_end and public.is_company_member(p_company_id) group by c.id,c.data->>'name' order by 4 desc limit p_limit)x $$;
create or replace function public.erp_cloud_top_products(p_company_id uuid,p_start date,p_end date,p_limit int default 10) returns jsonb language sql security definer set search_path=public as $$ select coalesce(jsonb_agg(x),'[]') from (select data->>'productId' "entityId",data->>'productName' "entityName",sum((data->>'quantity')::numeric) "quantitySold",sum((data->>'totalSale')::numeric) "salesValue",sum((data->>'profit')::numeric) "profitValue" from erp_inventory_product_sales where company_id=p_company_id and not coalesce(is_deleted,false) and (data->>'saleDate')::date between p_start and p_end and public.is_company_member(p_company_id) group by data->>'productId',data->>'productName' order by 5 desc limit p_limit)x $$;
create or replace function public.erp_cloud_branch_performance(p_company_id uuid,p_start date,p_end date) returns jsonb language sql security definer set search_path=public as $$ select coalesce(jsonb_agg(x),'[]') from (select coalesce(data->>'branchId','branch-main') "entityId",count(*) "transactionCount",sum((data->>'salePrice')::numeric) "salesValue",sum((data->>'paidAmount')::numeric) "collectedValue",sum((data->>'remainingAmount')::numeric) "outstandingValue" from erp_sales where company_id=p_company_id and not coalesce(is_deleted,false) and (data->>'saleDate')::date between p_start and p_end and public.is_company_member(p_company_id) group by coalesce(data->>'branchId','branch-main'))x $$;
create or replace function public.erp_cloud_profitability(p_company_id uuid,p_start date,p_end date) returns jsonb language sql security definer set search_path=public as $$ select jsonb_build_object('vehicleGrossProfit',coalesce((select sum((s.data->>'salePrice')::numeric-coalesce((c.data->>'purchasePrice')::numeric,0)-coalesce((c.data->>'maintenanceCost')::numeric,0)) from erp_sales s join erp_cars c on c.company_id=s.company_id and c.id=s.data->>'carId' where s.company_id=p_company_id and not coalesce(s.is_deleted,false) and (s.data->>'saleDate')::date between p_start and p_end),0),'productGrossProfit',coalesce((select sum((data->>'profit')::numeric) from erp_inventory_product_sales where company_id=p_company_id and not coalesce(is_deleted,false) and (data->>'saleDate')::date between p_start and p_end),0),'operatingExpenses',coalesce((select sum((data->>'amount')::numeric) from erp_expenses where company_id=p_company_id and not coalesce(is_deleted,false) and (data->>'date')::date between p_start and p_end),0)) where public.is_company_member(p_company_id) $$;
create or replace function public.erp_cloud_inventory_turnover(p_company_id uuid,p_limit int default 10) returns jsonb language sql security definer set search_path=public as $$ select coalesce(jsonb_agg(x),'[]') from (select i.id "entityId",i.data->>'name' "entityName",coalesce((i.data->>'quantity')::numeric,0) "onHand",coalesce(sum((s.data->>'quantity')::numeric),0) "quantitySold",coalesce(sum((s.data->>'quantity')::numeric),0)/greatest(coalesce((i.data->>'quantity')::numeric,0),1) "turnoverRate" from erp_inventory i left join erp_inventory_product_sales s on s.company_id=i.company_id and s.data->>'productId'=i.id and not coalesce(s.is_deleted,false) where i.company_id=p_company_id and not coalesce(i.is_deleted,false) and public.is_company_member(p_company_id) group by i.id,i.data order by 5 desc limit p_limit)x $$;
create or replace function public.erp_cloud_compare_periods(p_company_id uuid,p_current_start date,p_current_end date,p_previous_start date,p_previous_end date) returns jsonb language plpgsql security definer set search_path=public as $$ begin return jsonb_build_array(); end $$;
create or replace function public.erp_cloud_advanced_analytics(p_company_id uuid,p_days int default 30) returns jsonb language plpgsql security definer set search_path=public as $$ declare e date:=current_date;s date:=e-greatest(p_days-1,0); begin return jsonb_build_object('comparison',public.erp_cloud_compare_periods(p_company_id,s,e,s-p_days,e-p_days),'customers',public.erp_cloud_top_customers(p_company_id,s,e,10),'products',public.erp_cloud_top_products(p_company_id,s,e,10),'branches',public.erp_cloud_branch_performance(p_company_id,s,e),'profitability',public.erp_cloud_profitability(p_company_id,s,e),'inventory',public.erp_cloud_inventory_turnover(p_company_id,10)); end $$;

-- BI persistence and alert APIs. Snapshots are cloud-only and tenant scoped.
create or replace function public.erp_refresh_cloud_bi_snapshots(p_company_id uuid,p_from date,p_to date) returns jsonb language plpgsql security definer set search_path=public as $$ declare d date; n int:=0; snap jsonb; begin if not public.is_company_member(p_company_id) then raise exception 'access denied'; end if; for d in select generate_series(p_from,p_to,'1 day')::date loop snap:=public.erp_cloud_executive_bi_snapshot(p_company_id,d); insert into erp_bi_daily_snapshots(company_id,id,data,created_by,updated_by) values(p_company_id,p_company_id::text||':'||d::text,snap||jsonb_build_object('snapshotDate',d),auth.uid(),auth.uid()) on conflict(company_id,id) do update set data=excluded.data,updated_at=clock_timestamp(),updated_by=auth.uid(); n:=n+1; end loop; return jsonb_build_object('snapshots',n); end $$;
create or replace function public.erp_cloud_bi_latest_snapshots(p_company_id uuid,p_limit int default 30) returns jsonb language sql security definer set search_path=public as $$ select coalesce(jsonb_agg(data order by data->>'snapshotDate' desc),'[]') from (select data from erp_bi_daily_snapshots where company_id=p_company_id and not coalesce(is_deleted,false) and public.is_company_member(p_company_id) order by data->>'snapshotDate' desc limit p_limit)x $$;
create or replace function public.erp_cloud_bi_kpi_trend(p_company_id uuid,p_metric_code text,p_days int default 30) returns jsonb language sql security definer set search_path=public as $$ select coalesce(jsonb_agg(jsonb_build_object('day',data->>'snapshotDate','value',data->p_metric_code) order by data->>'snapshotDate'),'[]') from erp_bi_daily_snapshots where company_id=p_company_id and not coalesce(is_deleted,false) and (data->>'snapshotDate')::date>=current_date-p_days and public.is_company_member(p_company_id) $$;
create or replace function public.erp_cloud_bi_dashboard(p_company_id uuid,p_days int default 30) returns jsonb language plpgsql security definer set search_path=public as $$ begin return jsonb_build_object('snapshot',public.erp_cloud_executive_bi_snapshot(p_company_id,current_date),'trend',public.erp_cloud_bi_latest_snapshots(p_company_id,p_days),'alerts',public.erp_list_cloud_bi_alerts(p_company_id,null)); end $$;
create or replace function public.erp_evaluate_cloud_bi_alerts(p_company_id uuid,p_reference_day date default current_date) returns void language plpgsql security definer set search_path=public as $$ begin if not public.is_company_member(p_company_id) then raise exception 'access denied'; end if; end $$;
create or replace function public.erp_list_cloud_bi_alerts(p_company_id uuid,p_severity text default null) returns jsonb language sql security definer set search_path=public as $$ select coalesce(jsonb_agg(data||jsonb_build_object('id',id) order by created_at desc),'[]') from erp_bi_alerts where company_id=p_company_id and not coalesce(is_deleted,false) and coalesce(data->>'status','open')='open' and (p_severity is null or data->>'severity'=p_severity) and public.is_company_member(p_company_id) $$;
create or replace function public.erp_acknowledge_cloud_bi_alert(p_company_id uuid,p_alert_id text) returns void language plpgsql security definer set search_path=public as $$ begin if not public.is_company_member(p_company_id) then raise exception 'access denied'; end if; update erp_bi_alerts set data=data||jsonb_build_object('status','acknowledged','acknowledgedAt',clock_timestamp(),'acknowledgedBy',auth.uid()),updated_at=clock_timestamp() where company_id=p_company_id and id=p_alert_id; end $$;
create or replace function public.erp_cloud_bi_drilldown(p_company_id uuid,p_metric_code text,p_snapshot_day date) returns jsonb language plpgsql security definer set search_path=public as $$ begin if not public.is_company_member(p_company_id) then raise exception 'access denied'; end if; if p_metric_code='receivables' then return (select coalesce(jsonb_agg(data||jsonb_build_object('sourceEntityId',id)),'[]') from erp_sales where company_id=p_company_id and not coalesce(is_deleted,false) and coalesce((data->>'remainingAmount')::numeric,0)>0); end if; return '[]'::jsonb; end $$;


create or replace function public.erp_cloud_report_audit(p_company_id uuid,p_module text,p_start_date timestamptz default null,p_end_date timestamptz default null,p_limit int default 10000)
returns jsonb language sql security definer set search_path=public as $$
 select coalesce(jsonb_agg(payload order by updated_at desc),'[]'::jsonb)
 from (
  select payload,updated_at from public.erp_records
  where company_id=p_company_id::text and entity_type='audit_logs' and deleted_at is null
    and public.is_company_member(p_company_id)
    and (p_module='overview' or payload->>'module'=p_module)
    and (p_start_date is null or coalesce((payload->>'createdAt')::timestamptz,updated_at)>=p_start_date)
    and (p_end_date is null or coalesce((payload->>'createdAt')::timestamptz,updated_at)<p_end_date)
  order by updated_at desc limit p_limit
 ) q
$$;

commit;
