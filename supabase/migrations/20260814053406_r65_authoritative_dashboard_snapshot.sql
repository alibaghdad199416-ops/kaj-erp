-- R65: one coherent, currency-safe, invoice/accounting/FIFO authoritative
-- Dashboard read model. Forward-only; historical Dashboard functions remain
-- available to older clients but the current client moves to this endpoint.
begin;

create or replace function public.erp_r65_get_authoritative_dashboard_snapshot(
  p_company_id uuid,
  p_from_date date default null,
  p_to_date date default current_date
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_from date:=p_from_date;
  v_to date:=coalesce(p_to_date,current_date);
  v_result jsonb:='{}'::jsonb;
  v_financial jsonb:='{}'::jsonb;
  v_status jsonb:='{}'::jsonb;
  v_recent jsonb:='[]'::jsonb;
  v_trend jsonb:='[]'::jsonb;
  v_installments jsonb:='{}'::jsonb;
  v_invalid integer:=0;
  v_item record;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'dashboard.view') then
    raise exception 'permission_denied:dashboard.view' using errcode='42501';
  end if;
  if v_from is not null and v_from>v_to then
    raise exception 'invalid_dashboard_date_range' using errcode='22023';
  end if;

  -- Fail closed instead of silently relabelling malformed finance rows.
  select count(*) into v_invalid from (
    select d.payload->>'currency' currency
    from public.erp_commercial_workflow_documents d
    where d.company_id=p_company_id and d.document_type='invoice'
      and d.status='approved' and not d.is_deleted
    union all
    select m.currency_code from public.erp_maintenance_orders m
    where m.company_id=p_company_id and not m.is_deleted
      and m.workflow_stage in ('invoice_approved','paid','completed')
      and nullif(m.invoice_number,'') is not null and m.invoice_number<>'PENDING'
    union all
    select l.currency from public.erp_inventory_cost_layers l
    where l.company_id=p_company_id and l.status in ('active','consumed')
      and l.remaining_quantity>0
    union all
    select a.currency from public.erp_accounts a
    where a.organization_id=p_company_id and a.is_active
      and a.account_type in ('revenue','expense')
  ) x where public.erp_r49_normalize_supported_currency(x.currency) is null;
  if v_invalid>0 then
    raise exception 'dashboard_financial_currency_invalid:%',v_invalid using errcode='22023';
  end if;

  with sales as (
    select public.erp_r49_normalize_supported_currency(d.payload->>'currency') currency,
      sum(public.erp_try_numeric(d.payload->>'totalAmount',0)) total,
      sum(greatest(public.erp_try_numeric(d.payload->>'remainingAmount',0),0)) outstanding,
      sum(public.erp_try_numeric(d.payload->>'paidAmount',0)) paid,
      sum(case when (coalesce(d.effective_at,d.created_at) at time zone 'Asia/Baghdad')::date=v_to
        then public.erp_try_numeric(d.payload->>'totalAmount',0) else 0 end) today_total
    from public.erp_commercial_workflow_documents d
    where d.company_id=p_company_id and d.module='sales' and d.document_type='invoice'
      and d.status='approved' and not d.is_deleted
      and (v_from is null or (coalesce(d.effective_at,d.created_at) at time zone 'Asia/Baghdad')::date>=v_from)
      and (coalesce(d.effective_at,d.created_at) at time zone 'Asia/Baghdad')::date<=v_to
    group by 1
  ), purchases as (
    select public.erp_r49_normalize_supported_currency(d.payload->>'currency') currency,
      sum(public.erp_try_numeric(d.payload->>'totalAmount',0)) total,
      sum(greatest(public.erp_try_numeric(d.payload->>'remainingAmount',0),0)) outstanding,
      sum(public.erp_try_numeric(d.payload->>'paidAmount',0)) paid
    from public.erp_commercial_workflow_documents d
    where d.company_id=p_company_id and d.module='purchases' and d.document_type='invoice'
      and d.status='approved' and not d.is_deleted
      and (v_from is null or (coalesce(d.effective_at,d.created_at) at time zone 'Asia/Baghdad')::date>=v_from)
      and (coalesce(d.effective_at,d.created_at) at time zone 'Asia/Baghdad')::date<=v_to
    group by 1
  ), maintenance as (
    select public.erp_r49_normalize_supported_currency(m.currency_code) currency,
      sum(m.sale_price) revenue,
      sum(m.paid_amount) paid,
      sum(greatest(m.sale_price-m.paid_amount,0)) outstanding
    from public.erp_maintenance_orders m
    where m.company_id=p_company_id and not m.is_deleted
      and m.status<>'cancelled'
      and m.workflow_stage in ('invoice_approved','paid','completed')
      and nullif(m.invoice_number,'') is not null and m.invoice_number<>'PENDING'
      and (v_from is null or (coalesce(
        public.erp_try_timestamptz(m.accounting_payload->>'effectiveAt',null),m.maintenance_date
      ) at time zone 'Asia/Baghdad')::date>=v_from)
      and (coalesce(public.erp_try_timestamptz(
        m.accounting_payload->>'effectiveAt',null),m.maintenance_date
      ) at time zone 'Asia/Baghdad')::date<=v_to
    group by 1
  ), maintenance_cost as (
    select public.erp_r49_normalize_supported_currency(l.currency) currency,
      sum(c.total_cost) cost
    from public.erp_inventory_fifo_consumptions c
    join public.erp_inventory_cost_layers l on l.company_id=c.company_id and l.id=c.layer_id
    join public.erp_maintenance_orders m on m.company_id=c.company_id and m.id=c.delivery_id
    where c.company_id=p_company_id and c.status='active' and c.item_type='product'
      and c.delivery_id=c.sales_order_id and not m.is_deleted and m.status<>'cancelled'
      and (v_from is null or (c.effective_at at time zone 'Asia/Baghdad')::date>=v_from)
      and (c.effective_at at time zone 'Asia/Baghdad')::date<=v_to
    group by 1
  ), inventory as (
    select public.erp_r49_normalize_supported_currency(l.currency) currency,
      sum(l.remaining_quantity*l.unit_cost) value
    from public.erp_inventory_cost_layers l
    where l.company_id=p_company_id and l.status in ('active','consumed')
      and l.remaining_quantity>0 and l.item_type in ('product','car')
    group by 1
  ), cash as (
    select public.erp_r49_normalize_supported_currency(a.data->>'currency') currency,
      sum(b.balance) balance
    from public.erp_cloud_cash_account_balances(p_company_id) b
    join public.erp_cash_accounts a on a.company_id=p_company_id and a.id=b.cash_account_id
      and not a.is_deleted
    group by 1
  ), advances as (
    select public.erp_r49_normalize_supported_currency(t.data->>'currency') currency,
      lower(coalesce(t.data->>'partyType',t.data->>'party_type','')) party_type,
      sum(public.erp_try_numeric(t.data->>'amount',0)) amount
    from public.erp_cash_transactions t
    where t.company_id=p_company_id and not t.is_deleted
      and lower(coalesce(t.data->>'referenceType',t.data->>'reference_type',''))='partner_advance'
      and public.erp_try_boolean(t.data->>'unapplied',false)
    group by 1,2
  ), pnl as (
    select public.erp_r49_normalize_supported_currency(a.currency) currency,
      sum(case when a.account_type='revenue'
        then public.erp_try_numeric(jl.data->>'credit',0)-public.erp_try_numeric(jl.data->>'debit',0)
        else 0 end) revenue,
      sum(case when a.account_type='expense'
        then public.erp_try_numeric(jl.data->>'debit',0)-public.erp_try_numeric(jl.data->>'credit',0)
        else 0 end) expense
    from public.erp_journal_lines jl
    join public.erp_journal_entries je on je.company_id=jl.company_id
      and je.id=jl.data->>'entryId' and not je.is_deleted and je.data->>'status'='posted'
    join public.erp_accounts a on a.organization_id=jl.company_id
      and a.account_id=jl.data->>'accountId' and a.is_active
    where jl.company_id=p_company_id and not jl.is_deleted
      and a.account_type in ('revenue','expense')
      and (v_from is null or coalesce(public.erp_try_date(je.data->>'entryDate',null),je.created_at::date)>=v_from)
      and coalesce(public.erp_try_date(je.data->>'entryDate',null),je.created_at::date)<=v_to
    group by 1
  ), currencies as (select unnest(array['USD','IQD']) currency)
  select jsonb_build_object(
    'salesInvoicesByCurrency',jsonb_object_agg(c.currency,coalesce(s.total,0)),
    'todaySalesInvoicesByCurrency',jsonb_object_agg(c.currency,coalesce(s.today_total,0)),
    'salesCollectionsByCurrency',jsonb_object_agg(c.currency,coalesce(s.paid,0)),
    'salesReceivablesByCurrency',jsonb_object_agg(c.currency,coalesce(s.outstanding,0)),
    'purchaseInvoicesByCurrency',jsonb_object_agg(c.currency,coalesce(p.total,0)),
    'purchasePaymentsByCurrency',jsonb_object_agg(c.currency,coalesce(p.paid,0)),
    'purchasePayablesByCurrency',jsonb_object_agg(c.currency,coalesce(p.outstanding,0)),
    'maintenanceRevenueByCurrency',jsonb_object_agg(c.currency,coalesce(m.revenue,0)),
    'maintenancePaidByCurrency',jsonb_object_agg(c.currency,coalesce(m.paid,0)),
    'maintenanceOutstandingByCurrency',jsonb_object_agg(c.currency,coalesce(m.outstanding,0)),
    'maintenanceActualCostByCurrency',jsonb_object_agg(c.currency,coalesce(mc.cost,0)),
    'receivablesByCurrency',jsonb_object_agg(c.currency,coalesce(s.outstanding,0)+coalesce(m.outstanding,0)),
    'payablesByCurrency',jsonb_object_agg(c.currency,coalesce(p.outstanding,0)),
    'customerAdvancesByCurrency',jsonb_object_agg(c.currency,coalesce(ca.amount,0)),
    'supplierAdvancesByCurrency',jsonb_object_agg(c.currency,coalesce(sa.amount,0)),
    'cashByCurrency',jsonb_object_agg(c.currency,coalesce(ch.balance,0)),
    'inventoryValueByCurrency',jsonb_object_agg(c.currency,coalesce(i.value,0)),
    'recognizedRevenueByCurrency',jsonb_object_agg(c.currency,coalesce(pl.revenue,0)),
    'recognizedExpenseByCurrency',jsonb_object_agg(c.currency,coalesce(pl.expense,0)),
    'netProfitByCurrency',jsonb_object_agg(c.currency,coalesce(pl.revenue,0)-coalesce(pl.expense,0))
  ) into v_financial
  from currencies c
  left join sales s using(currency) left join purchases p using(currency)
  left join maintenance m using(currency) left join maintenance_cost mc using(currency)
  left join inventory i using(currency) left join cash ch using(currency)
  left join advances ca on ca.currency=c.currency and ca.party_type='customer'
  left join advances sa on sa.currency=c.currency and sa.party_type='supplier'
  left join pnl pl using(currency);

  select jsonb_build_object(
    'sales',coalesce((select jsonb_object_agg(status,n) from (
      select status,count(*) n from public.erp_sales_orders_cloud
      where company_id=p_company_id and not is_deleted group by status
    ) q),'{}'::jsonb),
    'purchases',coalesce((select jsonb_object_agg(status,n) from (
      select status,count(*) n from public.erp_purchase_orders_cloud
      where company_id=p_company_id and not is_deleted group by status
    ) q),'{}'::jsonb),
    'maintenance',coalesce((select jsonb_object_agg(status,n) from (
      select status,count(*) n from public.erp_maintenance_orders
      where company_id=p_company_id and not is_deleted group by status
    ) q),'{}'::jsonb)
  ) into v_status;

  select coalesce(jsonb_agg(row_payload order by occurred_at desc),'[]'::jsonb)
  into v_recent from (
    select jsonb_build_object('module',d.module,'documentType',d.document_type,
      'reference',d.document_number,'status',d.status,
      'partner',coalesce(c.data->>'name',s.data->>'name',''),'currency',upper(coalesce(d.payload->>'currency','')),
      'amount',public.erp_try_numeric(d.payload->>'totalAmount',0),'occurredAt',coalesce(d.effective_at,d.updated_at)
    ) row_payload,coalesce(d.effective_at,d.updated_at) occurred_at
    from public.erp_commercial_workflow_documents d
    left join public.erp_sales_orders_cloud so on d.module='sales'
      and so.company_id=d.company_id and so.id=d.parent_id
    left join public.erp_purchase_orders_cloud po on d.module='purchases'
      and po.company_id=d.company_id and po.id=d.parent_id
    left join public.erp_customers c on c.company_id=d.company_id and c.id=so.customer_id
      and not c.is_deleted
    left join public.erp_suppliers s on s.company_id=d.company_id and s.id=po.supplier_id
      and not s.is_deleted
    where d.company_id=p_company_id and d.document_type='invoice'
    union all
    select jsonb_build_object('module','maintenance','documentType','invoice',
      'reference',coalesce(nullif(m.invoice_number,''),m.order_number),'status',m.status,
      'partner',m.customer_name,'currency',upper(m.currency_code),'amount',m.sale_price,
      'occurredAt',coalesce(m.cancelled_at,m.updated_at)) row_payload,
      coalesce(m.cancelled_at,m.updated_at) occurred_at
    from public.erp_maintenance_orders m
    where m.company_id=p_company_id and nullif(m.invoice_number,'') is not null
    order by occurred_at desc limit 10
  ) q;

  select coalesce(jsonb_agg(jsonb_build_object('date',day::text,'amounts',amounts) order by day),'[]'::jsonb)
  into v_trend from (
    select d.day,jsonb_build_object(
      'USD',coalesce(sum(x.amount) filter(where x.currency='USD'),0),
      'IQD',coalesce(sum(x.amount) filter(where x.currency='IQD'),0)) amounts
    from generate_series(greatest(coalesce(v_from,v_to-6),v_to-30),v_to,'1 day') d(day)
    left join lateral (
      select public.erp_r49_normalize_supported_currency(i.payload->>'currency') currency,
        public.erp_try_numeric(i.payload->>'totalAmount',0) amount
      from public.erp_commercial_workflow_documents i
      where i.company_id=p_company_id and i.module='sales' and i.document_type='invoice'
        and i.status='approved' and not i.is_deleted
        and (coalesce(i.effective_at,i.created_at) at time zone 'Asia/Baghdad')::date=d.day::date
    ) x on true group by d.day
  ) q;

  v_installments:=public.erp_r49_installment_dashboard_summary(p_company_id,v_to);
  v_result:=jsonb_build_object(
    'filter',jsonb_build_object('fromDate',v_from,'toDate',v_to,'timezone','Asia/Baghdad'),
    'financial',v_financial,'statusCounts',v_status,'salesTrend',v_trend,
    'recentDocuments',v_recent,
    'totalCars',(select count(*) from public.erp_cars where company_id=p_company_id and not is_deleted),
    'availableCars',(select count(*) from public.erp_cars where company_id=p_company_id and not is_deleted and lower(coalesce(data->>'status','')) in ('available','متاحة','متوفر','متوفرة')),
    'reservedCars',(select count(*) from public.erp_cars where company_id=p_company_id and not is_deleted and lower(coalesce(data->>'status','')) in ('reserved','selling','pending_sale','محجوز','محجوزة','قيد البيع')),
    'soldCars',(select count(*) from public.erp_cars where company_id=p_company_id and not is_deleted and lower(coalesce(data->>'status','')) in ('sold','مباع','مباعة')),
    'totalCustomers',(select count(*) from public.erp_customers where company_id=p_company_id and not is_deleted),
    'totalSuppliers',(select count(*) from public.erp_suppliers where company_id=p_company_id and not is_deleted),
    'pendingPurchaseCars',(select count(*) from public.erp_cars where company_id=p_company_id and not is_deleted and lower(coalesce(data->>'status','')) in ('pending_purchase','قيد الشراء','قيد شراء')),
    'carsWithoutWarehouse',(select count(*) from public.erp_cars where company_id=p_company_id and not is_deleted and nullif(btrim(coalesce(data->>'warehouseId',data->>'warehouse_id','')), '') is null),
    'lowStockItems',(select count(*) from public.erp_warehouse_stock where company_id=p_company_id and not is_deleted and public.erp_try_numeric(data->>'quantity',0)<=public.erp_try_numeric(data->>'minimumQuantity',0)),
    'activeReservations',(select count(*) from public.erp_reservations where company_id=p_company_id and not is_deleted and lower(data->>'status')='active'),
    'pendingSyncOperations',0,
    'overdueInstallments',coalesce((v_installments->>'overdueInstallments')::integer,0),
    'dueSoonInstallments',coalesce((v_installments->>'dueSoonInstallments')::integer,0),
    'outstandingInstallmentsByCurrency',coalesce(v_installments->'outstandingInstallmentsByCurrency','{}'::jsonb),
    'upcomingInstallments',coalesce(v_installments->'upcomingInstallments','[]'::jsonb),
    'generatedAt',clock_timestamp()
  );

  if not public.erp_cloud_user_has_permission(p_company_id,'dashboard.fields.restrict') then
    return v_result;
  end if;
  v_result:='{}'::jsonb;
  for v_item in select key,value from jsonb_each(jsonb_build_object(
    'filter',jsonb_build_object('fromDate',v_from,'toDate',v_to,'timezone','Asia/Baghdad'),
    'financial',v_financial,'statusCounts',v_status,'salesTrend',v_trend,
    'recentDocuments',v_recent,'generatedAt',clock_timestamp()
  )) loop
    if public.erp_cloud_user_can_view_field(p_company_id,'dashboard',v_item.key,'dashboard.view') then
      v_result:=v_result||jsonb_build_object(v_item.key,v_item.value);
    end if;
  end loop;
  return v_result;
end;
$$;

revoke all on function public.erp_r65_get_authoritative_dashboard_snapshot(uuid,date,date)
  from public,anon,authenticated;
grant execute on function public.erp_r65_get_authoritative_dashboard_snapshot(uuid,date,date)
  to authenticated,service_role;

notify pgrst,'reload schema';
commit;
