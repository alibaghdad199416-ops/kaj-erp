begin;

-- R49 final independent quality closure.
-- Protect invoice creation at the database boundary so double-click, retry,
-- concurrent browser tabs, or a repeated RPC cannot create two active invoices
-- for the same commercial order. Existing historical rows are not rewritten.
create or replace function public.erp_r49_guard_single_active_invoice()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if new.document_type <> 'invoice'
     or new.module not in ('sales','purchases')
     or coalesce(new.is_deleted,false)
     or lower(coalesce(new.status,'')) in ('cancelled','canceled','deleted','void','reversed') then
    return new;
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      new.company_id::text||':'||new.module||':active-invoice:'||new.parent_id::text,
      0
    )
  );

  if exists (
    select 1
    from public.erp_commercial_workflow_documents d
    where d.company_id=new.company_id
      and d.module=new.module
      and d.document_type='invoice'
      and d.parent_id=new.parent_id
      and d.id is distinct from new.id
      and not d.is_deleted
      and lower(coalesce(d.status,'')) not in ('cancelled','canceled','deleted','void','reversed')
  ) then
    raise exception 'active_%_invoice_exists',new.module using errcode='23505';
  end if;

  return new;
end;
$$;

drop trigger if exists erp_r49_single_active_invoice_guard
on public.erp_commercial_workflow_documents;
create trigger erp_r49_single_active_invoice_guard
before insert or update of company_id,module,document_type,parent_id,status,is_deleted
on public.erp_commercial_workflow_documents
for each row execute function public.erp_r49_guard_single_active_invoice();

create or replace function public.erp_create_cloud_sales_workflow_invoice(
  p_company_id uuid,p_order_id uuid
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id uuid:=gen_random_uuid();
  v_existing uuid;
  o public.erp_sales_orders_cloud%rowtype;
  l jsonb;
  v_number text;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['sales.create','sales.update','sales.approve']
  );
  perform pg_advisory_xact_lock(
    hashtextextended(p_company_id::text||':sales-invoice:'||p_order_id::text,0)
  );

  select * into o
  from public.erp_sales_orders_cloud
  where company_id=p_company_id and id=p_order_id and not is_deleted
    and lower(coalesce(status,'')) not in ('draft','cancelled','canceled','reversed','deleted','void')
  for update;
  if not found then raise exception 'active_approved_sales_order_required'; end if;

  select id into v_existing
  from public.erp_commercial_workflow_documents
  where company_id=p_company_id and parent_id=p_order_id
    and module='sales' and document_type='invoice'
    and not is_deleted
    and lower(coalesce(status,'')) not in ('cancelled','canceled','deleted','void','reversed')
  order by created_at desc
  limit 1;
  if v_existing is not null then return v_existing; end if;

  l:=public.erp_v736_active_logistics(p_company_id,p_order_id,'sales');
  if nullif(l->>'id','') is null then raise exception 'approved_sales_delivery_required'; end if;

  v_number:=public.erp_next_document_number(
    p_company_id,'sales_invoice','SI',coalesce(o.effective_at,o.created_at)
  );
  insert into public.erp_commercial_workflow_documents(
    id,company_id,module,document_type,parent_id,document_number,payload,effective_at
  ) values(
    v_id,p_company_id,'sales','invoice',p_order_id,v_number,
    jsonb_build_object(
      'currency',o.currency,'totalAmount',o.total,'paidAmount',0,'remainingAmount',o.total,
      'paymentStatus','unpaid','payments','[]'::jsonb,'createdBy',auth.uid(),
      'logisticsDocumentId',l->>'id','logisticsDocumentNumber',l->>'number',
      'allocations',l->'allocations','warehouseIds',l->'warehouseIds','accountingOwner','invoice'
    ),
    coalesce(o.effective_at,o.created_at)
  );
  perform public.erp_commercial_audit(
    p_company_id,'sales',p_order_id,v_id,v_number,
    'create_invoice',null,'draft','approved delivery is authoritative; R49 idempotent creation'
  );
  return v_id;
end;
$$;



-- Financial summaries must never add unlike currencies. The legacy scalar
-- keys remain in the older snapshot contracts for backward compatibility,
-- while R49 exposes canonical per-currency maps consumed by the current UI.
create or replace function public.erp_r49_financial_summary_by_currency(
  p_company_id uuid,p_reference_day date default current_date
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_sales jsonb:='{}'::jsonb;
  v_today_sales jsonb:='{}'::jsonb;
  v_paid_sales jsonb:='{}'::jsonb;
  v_receivables jsonb:='{}'::jsonb;
  v_purchases jsonb:='{}'::jsonb;
  v_payables jsonb:='{}'::jsonb;
  v_expenses jsonb:='{}'::jsonb;
  v_inventory jsonb:='{}'::jsonb;
  v_profit jsonb:='{}'::jsonb;
begin
  if not public.erp_is_company_member(p_company_id) then
    raise exception 'access denied' using errcode='42501';
  end if;

  with rows as (
    select upper(coalesce(nullif(btrim(s.data->>'currencyCode'),''),nullif(btrim(s.data->>'currency'),''),'USD')) currency,
           public.erp_try_numeric(s.data->>'salePrice',0) total,
           public.erp_try_numeric(s.data->>'paidAmount',0) paid,
           public.erp_try_numeric(s.data->>'remainingAmount',0) remaining,
           public.erp_try_date(s.data->>'saleDate',null) effective_day
    from public.erp_sales s
    where s.company_id=p_company_id and not coalesce(s.is_deleted,false)
    union all
    select upper(coalesce(nullif(btrim(d.payload->>'currency'),''),'USD')),
           public.erp_try_numeric(d.payload->>'totalAmount',0),
           public.erp_try_numeric(d.payload->>'paidAmount',0),
           public.erp_try_numeric(d.payload->>'remainingAmount',0),
           coalesce(d.effective_at,d.created_at)::date
    from public.erp_commercial_workflow_documents d
    where d.company_id=p_company_id and d.module='sales' and d.document_type='invoice'
      and d.status='approved' and not d.is_deleted
  ), grouped as (
    select currency,sum(total) total,sum(paid) paid,sum(remaining) remaining,
           sum(case when effective_day=p_reference_day then total else 0 end) today_total
    from rows where currency in ('USD','IQD') group by currency
  )
  select coalesce(jsonb_object_agg(currency,total),'{}'::jsonb),
         coalesce(jsonb_object_agg(currency,paid),'{}'::jsonb),
         coalesce(jsonb_object_agg(currency,remaining),'{}'::jsonb),
         coalesce(jsonb_object_agg(currency,today_total),'{}'::jsonb)
  into v_sales,v_paid_sales,v_receivables,v_today_sales from grouped;

  with rows as (
    select upper(coalesce(nullif(btrim(p.data->>'currencyCode'),''),nullif(btrim(p.data->>'currency'),''),'USD')) currency,
           public.erp_try_numeric(p.data->>'totalAmount',0) total,
           public.erp_try_numeric(p.data->>'remainingAmount',0) remaining
    from public.erp_purchases p
    where p.company_id=p_company_id and not coalesce(p.is_deleted,false)
    union all
    select upper(coalesce(nullif(btrim(d.payload->>'currency'),''),'USD')),
           public.erp_try_numeric(d.payload->>'totalAmount',0),
           public.erp_try_numeric(d.payload->>'remainingAmount',0)
    from public.erp_commercial_workflow_documents d
    where d.company_id=p_company_id and d.module='purchases' and d.document_type='invoice'
      and d.status='approved' and not d.is_deleted
  ), grouped as (
    select currency,sum(total) total,sum(remaining) remaining
    from rows where currency in ('USD','IQD') group by currency
  )
  select coalesce(jsonb_object_agg(currency,total),'{}'::jsonb),
         coalesce(jsonb_object_agg(currency,remaining),'{}'::jsonb)
  into v_purchases,v_payables from grouped;

  with grouped as (
    select upper(coalesce(nullif(btrim(e.data->>'currency'),''),nullif(btrim(e.data->>'currencyCode'),''),'USD')) currency,
           sum(public.erp_try_numeric(e.data->>'amount',0)) amount
    from public.erp_expenses e
    where e.company_id=p_company_id and not coalesce(e.is_deleted,false)
    group by 1
  )
  select coalesce(jsonb_object_agg(currency,amount) filter(where currency in ('USD','IQD')),'{}'::jsonb)
  into v_expenses from grouped;

  with grouped as (
    select upper(coalesce(nullif(btrim(l.currency),''),'USD')) currency,
           sum(l.remaining_quantity*l.unit_cost) amount
    from public.erp_inventory_cost_layers l
    where l.company_id=p_company_id and l.status in ('active','consumed')
      and l.remaining_quantity>0 and l.item_type='product'
    group by 1
  )
  select coalesce(jsonb_object_agg(currency,amount) filter(where currency in ('USD','IQD')),'{}'::jsonb)
  into v_inventory from grouped;

  with currencies as (
    select unnest(array['USD','IQD']) currency
  ), amounts as (
    select c.currency,
      coalesce((v_sales->>c.currency)::numeric,0)
      -coalesce((v_purchases->>c.currency)::numeric,0)
      -coalesce((v_expenses->>c.currency)::numeric,0) amount
    from currencies c
  )
  select jsonb_object_agg(currency,amount) into v_profit from amounts;

  return jsonb_build_object(
    'totalSalesByCurrency',v_sales,
    'todaySalesByCurrency',v_today_sales,
    'totalPaidSalesByCurrency',v_paid_sales,
    'totalReceivablesByCurrency',v_receivables,
    'totalPurchasesByCurrency',v_purchases,
    'totalPayablesByCurrency',v_payables,
    'totalPurchaseDebtByCurrency',v_payables,
    'totalExpensesByCurrency',v_expenses,
    'inventoryValueByCurrency',v_inventory,
    'netProfitByCurrency',v_profit
  );
end;
$$;

create or replace function public.erp_r49_financial_report_summary_by_currency(
  p_company_id uuid,p_start_date date default null,p_end_date date default null
) returns jsonb
language plpgsql stable security definer set search_path=public
as $$
declare
  d1 date:=coalesce(p_start_date,current_date-365);
  d2 date:=coalesce(p_end_date,current_date);
  v_sales jsonb:='{}'::jsonb; v_paid jsonb:='{}'::jsonb; v_receivables jsonb:='{}'::jsonb;
  v_purchases jsonb:='{}'::jsonb; v_payables jsonb:='{}'::jsonb; v_expenses jsonb:='{}'::jsonb;
  v_inventory jsonb:='{}'::jsonb; v_profit jsonb:='{}'::jsonb;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'access denied' using errcode='42501'; end if;

  with grouped as (
    select upper(coalesce(nullif(btrim(s.data->>'currencyCode'),''),nullif(btrim(s.data->>'currency'),''),'USD')) currency,
           sum(public.erp_try_numeric(s.data->>'salePrice',0)) total,
           sum(public.erp_try_numeric(s.data->>'paidAmount',0)) paid,
           sum(public.erp_try_numeric(s.data->>'remainingAmount',0)) remaining
    from public.erp_sales s
    where s.company_id=p_company_id and not coalesce(s.is_deleted,false)
      and coalesce(public.erp_try_date(s.data->>'saleDate',null),s.created_at::date) between d1 and d2
    group by 1
  )
  select coalesce(jsonb_object_agg(currency,total) filter(where currency in ('USD','IQD')),'{}'::jsonb),
         coalesce(jsonb_object_agg(currency,paid) filter(where currency in ('USD','IQD')),'{}'::jsonb),
         coalesce(jsonb_object_agg(currency,remaining) filter(where currency in ('USD','IQD')),'{}'::jsonb)
  into v_sales,v_paid,v_receivables from grouped;

  with grouped as (
    select upper(coalesce(nullif(btrim(p.data->>'currencyCode'),''),nullif(btrim(p.data->>'currency'),''),'USD')) currency,
           sum(public.erp_try_numeric(p.data->>'totalAmount',0)) total,
           sum(public.erp_try_numeric(p.data->>'remainingAmount',0)) remaining
    from public.erp_purchases p
    where p.company_id=p_company_id and not coalesce(p.is_deleted,false)
      and coalesce(public.erp_try_date(p.data->>'purchaseDate',null),p.created_at::date) between d1 and d2
    group by 1
  )
  select coalesce(jsonb_object_agg(currency,total) filter(where currency in ('USD','IQD')),'{}'::jsonb),
         coalesce(jsonb_object_agg(currency,remaining) filter(where currency in ('USD','IQD')),'{}'::jsonb)
  into v_purchases,v_payables from grouped;

  with grouped as (
    select upper(coalesce(nullif(btrim(e.data->>'currency'),''),nullif(btrim(e.data->>'currencyCode'),''),'USD')) currency,
           sum(public.erp_try_numeric(e.data->>'amount',0)) amount
    from public.erp_expenses e
    where e.company_id=p_company_id and not coalesce(e.is_deleted,false)
      and coalesce(public.erp_try_date(e.data->>'date',null),e.created_at::date) between d1 and d2
    group by 1
  ) select coalesce(jsonb_object_agg(currency,amount) filter(where currency in ('USD','IQD')),'{}'::jsonb) into v_expenses from grouped;

  with grouped as (
    select upper(coalesce(nullif(btrim(l.currency),''),'USD')) currency,sum(l.remaining_quantity*l.unit_cost) amount
    from public.erp_inventory_cost_layers l
    where l.company_id=p_company_id and l.status in ('active','consumed') and l.remaining_quantity>0 and l.item_type='product'
    group by 1
  ) select coalesce(jsonb_object_agg(currency,amount) filter(where currency in ('USD','IQD')),'{}'::jsonb) into v_inventory from grouped;

  with currencies as (select unnest(array['USD','IQD']) currency), amounts as (
    select c.currency,coalesce((v_sales->>c.currency)::numeric,0)-coalesce((v_purchases->>c.currency)::numeric,0)-coalesce((v_expenses->>c.currency)::numeric,0) amount
    from currencies c
  ) select jsonb_object_agg(currency,amount) into v_profit from amounts;

  return jsonb_build_object(
    'totalSalesByCurrency',v_sales,'totalPaidSalesByCurrency',v_paid,'totalReceivablesByCurrency',v_receivables,
    'totalPurchasesByCurrency',v_purchases,'totalPurchaseDebtByCurrency',v_payables,'totalExpensesByCurrency',v_expenses,
    'inventoryValueByCurrency',v_inventory,'netProfitByCurrency',v_profit
  );
end;
$$;

create or replace function public.erp_r9_cloud_dashboard_snapshot(
  p_company_id uuid,
  p_reference_day date default current_date
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_raw jsonb;
  v_money jsonb;
  v_result jsonb := '{}'::jsonb;
  v_item record;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if not public.erp_cloud_user_has_permission(p_company_id,'dashboard.view')
     and not public.is_company_admin(p_company_id) then
    raise exception 'permission_denied:dashboard.view' using errcode='42501';
  end if;

  v_raw := public.erp_cloud_dashboard_snapshot(p_company_id,p_reference_day);
  v_money := public.erp_r49_financial_summary_by_currency(p_company_id,p_reference_day);
  if not public.erp_cloud_user_has_permission(p_company_id,'dashboard.fields.restrict') then
    return v_raw || v_money;
  end if;

  for v_item in select key,value from jsonb_each(coalesce(v_raw,'{}'::jsonb)) loop
    if public.erp_cloud_user_can_view_field(
         p_company_id,'dashboard',v_item.key,'dashboard.view'
       ) then
      v_result := v_result || jsonb_build_object(v_item.key,v_item.value);
    end if;
  end loop;

  if public.erp_cloud_user_can_view_field(p_company_id,'dashboard','totalSales','dashboard.view') then
    v_result:=v_result||jsonb_build_object('totalSalesByCurrency',v_money->'totalSalesByCurrency');
  end if;
  if public.erp_cloud_user_can_view_field(p_company_id,'dashboard','todaySales','dashboard.view') then
    v_result:=v_result||jsonb_build_object('todaySalesByCurrency',v_money->'todaySalesByCurrency');
  end if;
  if public.erp_cloud_user_can_view_field(p_company_id,'dashboard','totalPurchases','dashboard.view') then
    v_result:=v_result||jsonb_build_object('totalPurchasesByCurrency',v_money->'totalPurchasesByCurrency');
  end if;
  if public.erp_cloud_user_can_view_field(p_company_id,'dashboard','totalExpenses','dashboard.view') then
    v_result:=v_result||jsonb_build_object('totalExpensesByCurrency',v_money->'totalExpensesByCurrency');
  end if;
  if public.erp_cloud_user_can_view_field(p_company_id,'dashboard','netProfit','dashboard.view') then
    v_result:=v_result||jsonb_build_object('netProfitByCurrency',v_money->'netProfitByCurrency');
  end if;
  if public.erp_cloud_user_can_view_field(p_company_id,'dashboard','inventoryValue','dashboard.view') then
    v_result:=v_result||jsonb_build_object('inventoryValueByCurrency',v_money->'inventoryValueByCurrency');
  end if;
  if public.erp_cloud_user_can_view_field(p_company_id,'dashboard','totalReceivables','dashboard.view') then
    v_result:=v_result||jsonb_build_object('totalReceivablesByCurrency',v_money->'totalReceivablesByCurrency');
  end if;
  if public.erp_cloud_user_can_view_field(p_company_id,'dashboard','totalPayables','dashboard.view') then
    v_result:=v_result||jsonb_build_object('totalPayablesByCurrency',v_money->'totalPayablesByCurrency');
  end if;
  return v_result;
end;
$$;

create or replace function public.erp_r9_cloud_reports_summary(
  p_company_id uuid,p_start_date date default null,p_end_date date default null
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v jsonb; m jsonb; r jsonb:='{}'::jsonb; points jsonb:='[]'::jsonb;
begin
  if not public.erp_cloud_user_has_permission(p_company_id,'reports.view') then
    raise exception 'permission_denied:reports.view' using errcode='42501';
  end if;
  v:=public.erp_cloud_reports_summary(p_company_id,p_start_date,p_end_date);
  m:=public.erp_r49_financial_report_summary_by_currency(p_company_id,p_start_date,p_end_date);
  if not public.erp_cloud_user_has_permission(p_company_id,'reports.fields.restrict') then
    return v||m;
  end if;

  if public.erp_cloud_user_can_view_field(p_company_id,'reports','summaryCards',null) then
    r:=r||jsonb_build_object(
      'totalCars',v->'totalCars','availableCars',v->'availableCars','reservedCars',v->'reservedCars','soldCars',v->'soldCars',
      'totalCustomers',v->'totalCustomers','totalSuppliers',v->'totalSuppliers','totalInventoryItems',v->'totalInventoryItems',
      'activeReservations',v->'activeReservations','overdueInstallments',v->'overdueInstallments'
    );
    if public.erp_cloud_user_can_view_field(p_company_id,'sales','total','sales.view') then
      r:=r||jsonb_build_object('totalSales',v->'totalSales','totalSalesByCurrency',m->'totalSalesByCurrency');
    end if;
    if public.erp_cloud_user_can_view_field(p_company_id,'sales','payments','sales.view') then
      r:=r||jsonb_build_object('totalPaidSales',v->'totalPaidSales','totalPaidSalesByCurrency',m->'totalPaidSalesByCurrency');
      if public.erp_cloud_user_can_view_field(p_company_id,'reports','receivablesPayables',null) then
        r:=r||jsonb_build_object('totalReceivables',v->'totalReceivables','totalReceivablesByCurrency',m->'totalReceivablesByCurrency');
      end if;
    end if;
    if public.erp_cloud_user_can_view_field(p_company_id,'purchases','total','purchases.view') then
      r:=r||jsonb_build_object('totalPurchases',v->'totalPurchases','totalPurchasesByCurrency',m->'totalPurchasesByCurrency');
    end if;
    if public.erp_cloud_user_can_view_field(p_company_id,'purchases','payments','purchases.view')
       and public.erp_cloud_user_can_view_field(p_company_id,'reports','receivablesPayables',null) then
      r:=r||jsonb_build_object('totalPurchaseDebt',v->'totalPurchaseDebt','totalPurchaseDebtByCurrency',m->'totalPurchaseDebtByCurrency');
    end if;
    if public.erp_cloud_user_can_view_field(p_company_id,'expenses','amount','accounting.view') then
      r:=r||jsonb_build_object('totalExpenses',v->'totalExpenses','totalExpensesByCurrency',m->'totalExpensesByCurrency');
    end if;
    if public.erp_cloud_user_can_view_field(p_company_id,'reports','inventoryValue',null) then
      r:=r||jsonb_build_object('inventoryValue',v->'inventoryValue','inventoryValueByCurrency',m->'inventoryValueByCurrency');
    end if;
    if public.erp_cloud_user_can_view_field(p_company_id,'reports','cashBalances',null)
       and public.erp_cloud_user_can_view_field(p_company_id,'cashbox','balance','accounting.view') then
      r:=r||jsonb_build_object('cashBalanceUsd',v->'cashBalanceUsd','cashBalanceIqd',v->'cashBalanceIqd');
    end if;
    if public.erp_cloud_user_can_view_field(p_company_id,'reports','netProfit',null) then
      r:=r||jsonb_build_object('netProfit',v->'netProfit','netProfitByCurrency',m->'netProfitByCurrency');
    end if;
  end if;

  if public.erp_cloud_user_can_view_field(p_company_id,'reports','monthlyTrend',null) then
    select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'label',p->'label',
      'sales',case when public.erp_cloud_user_can_view_field(p_company_id,'sales','total','sales.view') then p->'sales' end,
      'expenses',case when public.erp_cloud_user_can_view_field(p_company_id,'expenses','amount','accounting.view') then p->'expenses' end,
      'purchases',case when public.erp_cloud_user_can_view_field(p_company_id,'purchases','total','purchases.view') then p->'purchases' end
    ))),'[]'::jsonb) into points
    from jsonb_array_elements(coalesce(v->'monthlyPoints','[]'::jsonb)) p;
  end if;
  return r||jsonb_build_object('monthlyPoints',points);
end;
$$;

revoke all on function public.erp_r49_guard_single_active_invoice() from public,anon;
revoke all on function public.erp_create_cloud_sales_workflow_invoice(uuid,uuid) from public,anon;
revoke all on function public.erp_r49_financial_summary_by_currency(uuid,date) from public,anon;
revoke all on function public.erp_r49_financial_report_summary_by_currency(uuid,date,date) from public,anon;
revoke all on function public.erp_r9_cloud_dashboard_snapshot(uuid,date) from public,anon;
revoke all on function public.erp_r9_cloud_reports_summary(uuid,date,date) from public,anon;
grant execute on function public.erp_r49_guard_single_active_invoice() to authenticated,service_role;
grant execute on function public.erp_create_cloud_sales_workflow_invoice(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r49_financial_summary_by_currency(uuid,date) to authenticated,service_role;
grant execute on function public.erp_r49_financial_report_summary_by_currency(uuid,date,date) to authenticated,service_role;
grant execute on function public.erp_r9_cloud_dashboard_snapshot(uuid,date) to authenticated,service_role;
grant execute on function public.erp_r9_cloud_reports_summary(uuid,date,date) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
