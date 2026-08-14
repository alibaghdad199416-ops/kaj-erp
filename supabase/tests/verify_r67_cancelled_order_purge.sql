\set ON_ERROR_STOP on
begin;

set local role postgres;
set local session_replication_role=replica;

-- Self-contained rollback-only fixtures. The proof must never depend on a
-- mutable local business order left behind by browser testing.
insert into public.erp_cars(company_id,id,data) values(
  '11111111-1111-4111-8111-111111111111',
  '67000000-0000-4000-8000-000000000002',
  '{"id":"67000000-0000-4000-8000-000000000002","name":"R67 rollback car","status":"available"}'
);
insert into public.erp_maintenance_orders(
  id,company_id,order_number,car_id,car_name,status,workflow_stage,
  currency_code,exchange_rate,source_car_id
) values(
  '67000000-0000-4000-8000-000000000001',
  '11111111-1111-4111-8111-111111111111','R67-QA-MAINT',
  '67000000-0000-4000-8000-000000000002','R67 rollback car',
  'completed','completed','USD',1,'67000000-0000-4000-8000-000000000002'
);
insert into public.erp_sales_orders_cloud(
  id,company_id,order_number,customer_id,status,currency,exchange_rate,
  subtotal,discount,total
) values(
  '67000000-0000-4000-8000-000000000003',
  '11111111-1111-4111-8111-111111111111','R67-QA-SALES','r67-customer',
  'cancelled','USD',1,0,0,0
);
insert into public.erp_purchase_orders_cloud(
  id,company_id,order_number,supplier_id,status,currency,exchange_rate,
  subtotal,discount,total
) values(
  '67000000-0000-4000-8000-000000000004',
  '11111111-1111-4111-8111-111111111111','R67-QA-PURCHASE','r67-supplier',
  'cancelled','USD',1,0,0,0
);
set local session_replication_role=origin;

select set_config(
  'request.jwt.claims',
  '{"sub":"5dfff075-0653-4918-bcce-293eea5e68d6","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
declare
  v_company constant uuid:='11111111-1111-4111-8111-111111111111';
  v_order constant uuid:='67000000-0000-4000-8000-000000000001';
  v_payment_ids text[];
  v_cash_count bigint;
  v_stock numeric;
  v_result jsonb;
begin
  select coalesce(array_agg(id::text order by id::text),'{}'::text[])
    into v_payment_ids
  from public.erp_maintenance_payments
  where company_id=v_company and maintenance_order_id=v_order and not is_deleted;
  select count(*) into v_cash_count from public.erp_cash_transactions
    where company_id=v_company and not is_deleted;

  v_result:=public.erp_r67_cancel_maintenance_order(
    v_company,v_order,'R67 rollback-only maintenance cancellation proof');
  if v_result->>'status'<>'cancelled' then
    raise exception 'R67 maintenance cancellation failed: %',v_result;
  end if;
  if (select workflow_stage from public.erp_maintenance_orders
      where company_id=v_company and id=v_order)<>'cancelled' then
    raise exception 'R67 maintenance order was not preserved as cancelled';
  end if;
  if exists(select 1 from public.erp_maintenance_payments
      where company_id=v_company and maintenance_order_id=v_order
        and not is_deleted and not is_unapplied) then
    raise exception 'R67 maintenance allocation was not detached';
  end if;
  if (select count(*) from public.erp_cash_transactions
      where company_id=v_company and not is_deleted)<>v_cash_count then
    raise exception 'R67 maintenance cancel deleted real cash';
  end if;

  select coalesce(sum(public.erp_try_numeric(data->>'quantity',0)),0)
    into v_stock from public.erp_warehouse_stock
    where company_id=v_company and not is_deleted;
  v_result:=public.erp_r67_delete_maintenance_order(
    v_company,v_order,'R67 rollback-only maintenance purge proof');
  if not coalesce((v_result->>'deleted')::boolean,false) then
    raise exception 'R67 maintenance purge failed: %',v_result;
  end if;
  if (select coalesce(sum(public.erp_try_numeric(data->>'quantity',0)),0)
      from public.erp_warehouse_stock where company_id=v_company and not is_deleted)<>v_stock then
    raise exception 'R67 maintenance purge reversed stock twice';
  end if;
  if (select coalesce(array_agg(id::text order by id::text),'{}'::text[])
      from public.erp_maintenance_payments
      where company_id=v_company and maintenance_order_id=v_order and not is_deleted)
      is distinct from v_payment_ids then
    raise exception 'R67 maintenance purge deleted or replaced a real payment';
  end if;
end $$;

do $$
declare
  v_company constant uuid:='11111111-1111-4111-8111-111111111111';
  v_sales constant uuid:='67000000-0000-4000-8000-000000000003';
  v_purchase constant uuid:='67000000-0000-4000-8000-000000000004';
  v_cash_count bigint;
  v_stock numeric;
  v_result jsonb;
begin
  select count(*) into v_cash_count from public.erp_cash_transactions
    where company_id=v_company and not is_deleted;
  select coalesce(sum(public.erp_try_numeric(data->>'quantity',0)),0)
    into v_stock from public.erp_warehouse_stock
    where company_id=v_company and not is_deleted;

  v_result:=public.erp_r67_delete_commercial_order(v_company,v_sales,'sales');
  if not coalesce((v_result->>'deleted')::boolean,false) then
    raise exception 'R67 sales purge failed: %',v_result;
  end if;
  v_result:=public.erp_r67_delete_commercial_order(v_company,v_purchase,'purchases');
  if not coalesce((v_result->>'deleted')::boolean,false) then
    raise exception 'R67 purchase purge failed: %',v_result;
  end if;
  if (select count(*) from public.erp_cash_transactions
      where company_id=v_company and not is_deleted)<>v_cash_count then
    raise exception 'R67 commercial purge deleted real cash';
  end if;
  if (select coalesce(sum(public.erp_try_numeric(data->>'quantity',0)),0)
      from public.erp_warehouse_stock where company_id=v_company and not is_deleted)<>v_stock then
    raise exception 'R67 commercial purge changed restored stock';
  end if;

  v_result:=public.erp_r67_delete_commercial_order(v_company,v_sales,'sales');
  if not coalesce((v_result->>'alreadyDeleted')::boolean,false) then
    raise exception 'R67 sales retry was not deterministic: %',v_result;
  end if;
  v_result:=public.erp_r67_delete_commercial_order(v_company,v_purchase,'purchases');
  if not coalesce((v_result->>'alreadyDeleted')::boolean,false) then
    raise exception 'R67 purchase retry was not deterministic: %',v_result;
  end if;
end $$;

rollback;
\echo 'R67 cancelled-order atomic purge proof PASS'
