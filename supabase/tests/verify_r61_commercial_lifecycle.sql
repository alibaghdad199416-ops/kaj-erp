\set ON_ERROR_STOP on

begin;

set local session_replication_role=replica;
insert into public.erp_cars(company_id,id,data) values(
  '11111111-1111-4111-8111-111111111111','r61-qa-car',
  '{"id":"r61-qa-car","name":"R61 rollback car","status":"sold","statusValue":"sold","currency":"USD","purchasePrice":100,"salePrice":100}'
);
insert into public.erp_sales_orders_cloud(
  id,company_id,order_number,customer_id,status,currency,exchange_rate,
  subtotal,discount,total
) values(
  '61000000-0000-4000-8000-000000000001',
  '11111111-1111-4111-8111-111111111111','R61-QA-SALES','r61-customer',
  'approved','USD',1,100,0,100
);
insert into public.erp_sales_order_items_cloud(
  id,company_id,order_id,item_type,item_id,description,quantity,unit_price,line_total
) values(
  '61000000-0000-4000-8000-000000000002',
  '11111111-1111-4111-8111-111111111111',
  '61000000-0000-4000-8000-000000000001','car','r61-qa-car','R61 rollback car',1,100,100
);
insert into public.erp_commercial_workflow_documents(
  id,company_id,module,document_type,parent_id,document_number,warehouse_id,
  status,payload
) values(
  '61000000-0000-4000-8000-000000000003',
  '11111111-1111-4111-8111-111111111111','sales','delivery',
  '61000000-0000-4000-8000-000000000001','R61-QA-DELIVERY','warehouse-main',
  'approved','{"inventoryPostedAt":"2026-08-14T00:00:00Z","allocations":[{"itemType":"car","itemId":"r61-qa-car","description":"R61 rollback car","warehouseId":"warehouse-main","quantity":1}]}'
);
set local session_replication_role=origin;

do $$
declare
  v_company constant uuid:='11111111-1111-4111-8111-111111111111';
  v_order constant uuid:='61000000-0000-4000-8000-000000000001';
  v_delivery constant uuid:='61000000-0000-4000-8000-000000000003';
  v_car constant text:='r61-qa-car';
  v_snapshot jsonb;
  v_result jsonb;
  v_payment_count bigint;
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub','5dfff075-0653-4918-bcce-293eea5e68d6',
      'role','authenticated'
    )::text,
    true
  );
  -- Reconstruct the browser-reproduced moment inside a rollback-only proof:
  -- delivery is approved and the exact car has already left current stock.
  update public.erp_sales_orders_cloud
    set status='approved',is_deleted=false,deleted_at=null
    where company_id=v_company and id=v_order;
  update public.erp_sales_order_items_cloud
    set is_deleted=false,deleted_at=null
    where company_id=v_company and order_id=v_order;
  update public.erp_commercial_workflow_documents
    set status='approved',is_deleted=false,
      payload=(payload-'cancelledAt'-'inventoryReversedAt'-'fifoReversedAt')
        ||jsonb_build_object('inventoryPostedAt',now())
    where company_id=v_company and id=v_delivery;
  update public.erp_cars
    set data=(data-'warehouseId'-'warehouse_id')||jsonb_build_object(
      'currentWarehouseId',null,'current_warehouse_id',null,
      'status','مباعة','statusValue','sold','status_value','sold'
    )
    where company_id=v_company and id=v_car;

  v_snapshot:=public.erp_v736_active_logistics(v_company,v_order,'sales');
  if v_snapshot->>'id'<>v_delivery::text then
    raise exception 'r61 did not select the authoritative approved delivery';
  end if;
  if v_snapshot->'allocations'->0->>'itemId'<>v_car then
    raise exception 'r61 lost exact delivered car identity';
  end if;

  begin
    perform public.erp_r61_validate_approved_logistics(
      v_company,v_order,'sales',
      jsonb_build_array(jsonb_build_object(
        'itemType','car','itemId',gen_random_uuid()::text,
        'warehouseId','warehouse-main','quantity',1
      ))
    );
    raise exception 'r61 accepted the wrong car';
  exception when sqlstate 'P0001' then
    if sqlerrm not like 'approved_logistics_item_mismatch:%' then raise; end if;
  end;

  select count(*) into v_payment_count
  from public.erp_cash_transactions
  where company_id=v_company and not is_deleted and data::text like '%'||v_order::text||'%';
  v_result:=public.erp_r61_cancel_commercial_order(
    v_company,v_order,'sales','R61 rollback-only cancellation proof'
  );
  if v_result->>'status'<>'cancelled' or v_result->>'orderPreserved'<>'true' then
    raise exception 'r61 cancellation did not report the governed terminal state';
  end if;
  if not exists(select 1 from public.erp_sales_orders_cloud
      where company_id=v_company and id=v_order and status='cancelled' and not is_deleted) then
    raise exception 'r61 cancellation removed the sales order';
  end if;
  if (select count(*) from public.erp_cash_transactions
      where company_id=v_company and not is_deleted
        and data::text like '%'||v_order::text||'%')<>v_payment_count then
    raise exception 'r61 cancellation changed the real payment count';
  end if;
  v_result:=public.erp_r61_cancel_commercial_order(
    v_company,v_order,'sales','R61 idempotency retry'
  );
  if v_result->>'idempotent'<>'true' then
    raise exception 'r61 cancellation retry was not idempotent';
  end if;
end;
$$;

rollback;
