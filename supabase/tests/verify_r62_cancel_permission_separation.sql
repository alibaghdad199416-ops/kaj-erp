\set ON_ERROR_STOP on

begin;

-- Two isolated browser identities: one owns only *.cancel and the other only
-- *.delete.  Every fixture and lifecycle mutation is rolled back.
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at)
values
('62000000-0000-4000-8000-000000000001','authenticated','authenticated',
 'r62-cancel@example.invalid','',now()),
('62000000-0000-4000-8000-000000000002','authenticated','authenticated',
 'r62-delete@example.invalid','',now());

insert into public.company_memberships(
  company_id,user_id,user_uid,local_user_id,user_email,role_code,is_active
) values
('11111111-1111-4111-8111-111111111111','62000000-0000-4000-8000-000000000001',
 '62000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000001',
 'r62-cancel@example.invalid','user',true),
('11111111-1111-4111-8111-111111111111','62000000-0000-4000-8000-000000000002',
 '62000000-0000-4000-8000-000000000002','62000000-0000-4000-8000-000000000002',
 'r62-delete@example.invalid','user',true);

insert into public.erp_records(company_id,entity_type,record_id,payload) values
('quality-line','users','62000000-0000-4000-8000-000000000001',
 '{"cloudAuthUid":"62000000-0000-4000-8000-000000000001","roleId":"role-r62-test","isActive":1}'),
('quality-line','users','62000000-0000-4000-8000-000000000002',
 '{"cloudAuthUid":"62000000-0000-4000-8000-000000000002","roleId":"role-r62-test","isActive":1}'),
('quality-line','user_permission_overrides','62000000-0000-4000-8000-000000000001','{"enabled":true}'),
('quality-line','user_permission_overrides','62000000-0000-4000-8000-000000000002','{"enabled":true}');

insert into public.erp_records(company_id,entity_type,record_id,payload)
select 'quality-line','user_permissions',gen_random_uuid()::text,
  jsonb_build_object('userId','62000000-0000-4000-8000-000000000001','permissionId',record_id)
from public.erp_records where company_id='quality-line' and entity_type='permissions'
  and payload->>'code' in ('sales.cancel','purchases.cancel');
insert into public.erp_records(company_id,entity_type,record_id,payload)
select 'quality-line','user_permissions',gen_random_uuid()::text,
  jsonb_build_object('userId','62000000-0000-4000-8000-000000000002','permissionId',record_id)
from public.erp_records where company_id='quality-line' and entity_type='permissions'
  and payload->>'code' in ('sales.delete','purchases.delete');

set local session_replication_role=replica;
insert into public.erp_sales_orders_cloud(
  id,company_id,order_number,customer_id,status,currency,exchange_rate,
  subtotal,discount,total
) values(
  '62000000-0000-4000-8000-000000000010',
  '11111111-1111-4111-8111-111111111111','R62-QA-SALES','r62-customer',
  'approved','USD',1,0,0,0
);
insert into public.erp_purchase_orders_cloud(
  id,company_id,order_number,supplier_id,status,currency,exchange_rate,
  subtotal,discount,total
) values(
  '62000000-0000-4000-8000-000000000011',
  '11111111-1111-4111-8111-111111111111','R62-QA-PURCHASE','r62-supplier',
  'approved','USD',1,0,0,0
);
set local session_replication_role=origin;

do $$
declare
  v_company constant uuid:='11111111-1111-4111-8111-111111111111';
  v_sales constant uuid:='62000000-0000-4000-8000-000000000010';
  v_purchase constant uuid:='62000000-0000-4000-8000-000000000011';
  v_result jsonb;
begin
  perform set_config('request.jwt.claims',
    '{"sub":"62000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
  begin
    perform public.erp_r62_cancel_commercial_order(v_company,v_sales,'sales','deny delete-only');
    raise exception 'delete-only user cancelled sales';
  exception when sqlstate '42501' then
    if sqlerrm not like 'permission_denied:sales.cancel%' then raise; end if;
  end;
  begin
    perform public.erp_r62_cancel_commercial_order(v_company,v_purchase,'purchases','deny delete-only');
    raise exception 'delete-only user cancelled purchases';
  exception when sqlstate '42501' then
    if sqlerrm not like 'permission_denied:purchases.cancel%' then raise; end if;
  end;

  perform set_config('request.jwt.claims',
    '{"sub":"62000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
  v_result:=public.erp_r62_cancel_commercial_order(v_company,v_sales,'sales','cancel-only sales proof');
  if v_result->>'status'<>'cancelled' or v_result->>'orderPreserved'<>'true' then
    raise exception 'cancel-only sales result invalid: %',v_result;
  end if;
  if not exists(select 1 from public.erp_sales_orders_cloud where company_id=v_company
      and id=v_sales and status='cancelled' and not is_deleted) then
    raise exception 'cancelled sales order was not preserved';
  end if;
  v_result:=public.erp_r62_cancel_commercial_order(v_company,v_sales,'sales','retry');
  if v_result->>'idempotent'<>'true' then raise exception 'sales retry not idempotent'; end if;

  v_result:=public.erp_r62_cancel_commercial_order(v_company,v_purchase,'purchases','cancel-only purchase proof');
  if v_result->>'status'<>'cancelled' or v_result->>'orderPreserved'<>'true' then
    raise exception 'cancel-only purchase result invalid: %',v_result;
  end if;
  if not exists(select 1 from public.erp_purchase_orders_cloud where company_id=v_company
      and id=v_purchase and status='cancelled' and not is_deleted) then
    raise exception 'cancelled purchase order was not preserved';
  end if;
  v_result:=public.erp_r62_cancel_commercial_order(v_company,v_purchase,'purchases','retry');
  if v_result->>'idempotent'<>'true' then raise exception 'purchase retry not idempotent'; end if;
end;
$$;

rollback;
