\set ON_ERROR_STOP on
\pset pager off

begin;
set local session_replication_role=replica;

insert into auth.users(
  instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at
) values(
  '00000000-0000-0000-0000-000000000000','57020000-0000-4000-8000-000000000001',
  'authenticated','authenticated','r57-cost@local.invalid','',now(),'{}','{}',now(),now()
);
insert into public.companies(id,slug,name_ar,name_en,is_active) values(
  '57020000-0000-4000-8000-000000000010','r57-cost-semantics','R57 محلي','R57 local',true
);
insert into public.company_memberships(
  company_id,user_id,user_uid,user_email,role_code,is_system_admin,is_active
) values(
  '57020000-0000-4000-8000-000000000010','57020000-0000-4000-8000-000000000001',
  '57020000-0000-4000-8000-000000000001','r57-cost@local.invalid','admin',true,true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"57020000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

insert into public.erp_warehouses(company_id,id,data) values
  ('57020000-0000-4000-8000-000000000010','r57-cost-wh-a','{"name":"Warehouse A","isActive":true}'),
  ('57020000-0000-4000-8000-000000000010','r57-cost-wh-b','{"name":"Warehouse B","isActive":true}');
insert into public.erp_cars(company_id,id,data) values(
  '57020000-0000-4000-8000-000000000010','57020000-0000-4000-8000-000000000021',
  '{"brand":"R57","model":"Cost semantics","currency":"USD"}'
);
insert into public.erp_inventory(company_id,id,data) values(
  '57020000-0000-4000-8000-000000000010','r57-cost-product',
  '{"name":"Requested part","currency":"USD","costCurrency":"USD","isActive":true}'
);
insert into public.erp_maintenance_orders(
  id,company_id,order_number,car_id,car_name,customer_name,warehouse_id,
  source_warehouse_id,status,workflow_stage,labor_cost,sale_price,currency_code
) values(
  '57020000-0000-4000-8000-000000000020','57020000-0000-4000-8000-000000000010',
  'R57-COST-001','57020000-0000-4000-8000-000000000021','R57 Vehicle','R57 Customer',
  '57020000-0000-4000-8000-000000000031','r57-cost-wh-a','approved','stock_issue_draft',
  50,999,'USD'
);

set local session_replication_role=origin;

-- Request-time average cost A is 10. Selling value is intentionally 99 so a
-- cost fallback to billing is immediately detectable.
insert into public.erp_maintenance_parts(
  id,company_id,maintenance_order_id,product_id,source_product_id,product_name,
  warehouse_id,source_warehouse_id,quantity,unit_cost,total_cost,line_type,
  unit_price,line_total_price
) values
  ('57020000-0000-4000-8000-000000000041','57020000-0000-4000-8000-000000000010',
   '57020000-0000-4000-8000-000000000020','57020000-0000-4000-8000-000000000051',
   'r57-cost-product','Requested part','57020000-0000-4000-8000-000000000031',
   'r57-cost-wh-a',5,10,50,'stock',99,495),
  ('57020000-0000-4000-8000-000000000042','57020000-0000-4000-8000-000000000010',
   '57020000-0000-4000-8000-000000000020','57020000-0000-4000-8000-000000000051',
   'r57-cost-product','Requested part','57020000-0000-4000-8000-000000000032',
   'r57-cost-wh-b',2,10,20,'stock',99,198);

insert into public.erp_inventory_cost_layers(
  id,company_id,item_type,item_id,warehouse_id,layer_number,effective_at,
  original_quantity,remaining_quantity,unit_cost,currency,status
) values
  ('57020000-0000-4000-8000-000000000061','57020000-0000-4000-8000-000000000010',
   'product','r57-cost-product','r57-cost-wh-a','R57-A1',now()-interval '3 days',3,0,20,'USD','consumed'),
  ('57020000-0000-4000-8000-000000000062','57020000-0000-4000-8000-000000000010',
   'product','r57-cost-product','r57-cost-wh-a','R57-A2',now()-interval '2 days',2,0,30,'USD','consumed'),
  ('57020000-0000-4000-8000-000000000063','57020000-0000-4000-8000-000000000010',
   'product','r57-cost-product','r57-cost-wh-b','R57-B1',now()-interval '1 day',2,0,40,'USD','consumed');

do $verify$
declare v jsonb;
begin
  v:=public.erp_r57_maintenance_cost_reconciliation(
    '57020000-0000-4000-8000-000000000010','57020000-0000-4000-8000-000000000020'
  );
  if (v->>'requestedMaterialsCost')::numeric<>70
     or (v->>'issuedMaterialsActualCost')::numeric<>0 then
    raise exception 'request_snapshot_initial_failed:%',v;
  end if;
end $verify$;

-- Partial issue: 3 units from a FIFO layer at 20, unlike requested cost 10.
insert into public.erp_inventory_fifo_consumptions(
  company_id,delivery_id,sales_order_id,layer_id,item_type,item_id,warehouse_id,
  quantity,unit_cost,effective_at,status
) values(
  '57020000-0000-4000-8000-000000000010','57020000-0000-4000-8000-000000000020',
  '57020000-0000-4000-8000-000000000020','57020000-0000-4000-8000-000000000061',
  'product','r57-cost-product','r57-cost-wh-a',3,20,now(),'active'
);
update public.erp_maintenance_parts
set unit_cost=20,total_cost=100
where id='57020000-0000-4000-8000-000000000041';

do $verify$
declare v jsonb;
begin
  v:=public.erp_r57_maintenance_cost_reconciliation(
    '57020000-0000-4000-8000-000000000010','57020000-0000-4000-8000-000000000020'
  );
  if (v->>'requestedMaterialsCost')::numeric<>70
     or (v->>'issuedMaterialsActualCost')::numeric<>60 then
    raise exception 'request_snapshot_partial_issue_failed:%',v;
  end if;
end $verify$;

-- Second FIFO layer plus a different warehouse. The mutable operational line
-- costs become 120 and 80, while the immutable request remains 50 and 20.
insert into public.erp_inventory_fifo_consumptions(
  company_id,delivery_id,sales_order_id,layer_id,item_type,item_id,warehouse_id,
  quantity,unit_cost,effective_at,status
) values
  ('57020000-0000-4000-8000-000000000010','57020000-0000-4000-8000-000000000020',
   '57020000-0000-4000-8000-000000000020','57020000-0000-4000-8000-000000000062',
   'product','r57-cost-product','r57-cost-wh-a',2,30,now(),'active'),
  ('57020000-0000-4000-8000-000000000010','57020000-0000-4000-8000-000000000020',
   '57020000-0000-4000-8000-000000000020','57020000-0000-4000-8000-000000000063',
   'product','r57-cost-product','r57-cost-wh-b',2,40,now(),'active');
update public.erp_maintenance_parts set unit_cost=24,total_cost=120
where id='57020000-0000-4000-8000-000000000041';
update public.erp_maintenance_parts set unit_cost=40,total_cost=80
where id='57020000-0000-4000-8000-000000000042';

do $verify$
declare v jsonb;
begin
  v:=public.erp_r57_maintenance_cost_reconciliation(
    '57020000-0000-4000-8000-000000000010','57020000-0000-4000-8000-000000000020'
  );
  if (v->>'requestedMaterialsCost')::numeric<>70
     or (v->>'issuedMaterialsActualCost')::numeric<>200
     or jsonb_array_length(v->'warehouses')<>2
     or (select sum((x->>'issuedActualCost')::numeric)
         from jsonb_array_elements(v->'warehouses') x)<>200 then
    raise exception 'request_snapshot_layers_warehouses_failed:%',v;
  end if;
  if exists(
    select 1 from public.erp_maintenance_parts
    where maintenance_order_id='57020000-0000-4000-8000-000000000020'
      and (requested_unit_cost<>10 or requested_total_cost<>quantity*10)
  ) then raise exception 'request_snapshot_was_overwritten'; end if;
end $verify$;

select public.erp_v66_reverse_maintenance_stock(
  '57020000-0000-4000-8000-000000000010','57020000-0000-4000-8000-000000000020',
  'R57 requested cost reversal proof'
);

do $verify$
declare v jsonb;
begin
  v:=public.erp_r57_maintenance_cost_reconciliation(
    '57020000-0000-4000-8000-000000000010','57020000-0000-4000-8000-000000000020'
  );
  if (v->>'requestedMaterialsCost')::numeric<>70
     or (v->>'issuedMaterialsActualCost')::numeric<>0 then
    raise exception 'request_snapshot_reversal_failed:%',v;
  end if;
end $verify$;

rollback;
\echo 'R57 maintenance requested cost semantic integrity PASS'
