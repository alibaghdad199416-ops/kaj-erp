\set ON_ERROR_STOP on
begin;

select set_config(
  'request.jwt.claims',
  '{"sub":"5dfff075-0653-4918-bcce-293eea5e68d6","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
declare
  v_company constant uuid:='11111111-1111-4111-8111-111111111111';
  v_order constant uuid:='b0839af5-e93e-4ea5-b75a-0b7b61cd4946';
  v_invoice constant uuid:='a98b23dd-67b7-4f72-933c-1bee4f55ef05';
  v_car constant text:='5fb4c9d2-93c5-4efa-9900-c6021ffadbfd';
  v_delivery constant uuid:='c7fe417d-81ef-4a86-9f7a-1ce9e1b87d2a';
  v_result jsonb; v_retry jsonb; v_vin text; v_consumptions bigint;
begin
  select data->>'vin' into v_vin from public.erp_cars
    where company_id=v_company and id=v_car and not is_deleted;
  if v_vin<>'B123456543234567' then raise exception 'R66 exact car identity precondition failed'; end if;
  if not exists(select 1 from public.erp_commercial_workflow_documents
    where company_id=v_company and id=v_delivery and parent_id=v_order
      and module='sales' and document_type='delivery' and status='approved'
      and payload->'allocations' @> jsonb_build_array(jsonb_build_object(
        'itemId',v_car,'itemType','car','quantity',1,'warehouseId','warehouse-main')))
    then raise exception 'R66 approved exact delivery evidence missing'; end if;
  select count(*) into v_consumptions from public.erp_inventory_fifo_consumptions
    where company_id=v_company and delivery_id=v_delivery and status='active';

  v_result:=public.erp_r22_approve_sales_invoice(v_company,v_invoice);
  if not coalesce((v_result->>'ok')::boolean,false) or v_result->>'status'<>'approved'
    then raise exception 'R66 exact SI00006 approval failed: %',v_result; end if;
  if (select count(*) from public.erp_inventory_fifo_consumptions
      where company_id=v_company and delivery_id=v_delivery and status='active')<>v_consumptions
    then raise exception 'R66 invoice consumed inventory a second time'; end if;
  if (select data->>'vin' from public.erp_cars where company_id=v_company and id=v_car)<>v_vin
    then raise exception 'R66 invoice changed exact car identity'; end if;

  v_retry:=public.erp_r22_approve_sales_invoice(v_company,v_invoice);
  if not coalesce((v_retry->>'ok')::boolean,false)
    or not coalesce((v_retry->>'idempotent')::boolean,false)
    then raise exception 'R66 invoice retry is not idempotent: %',v_retry; end if;
end $$;

create temporary table r66_notification_proof(
  notification_id uuid primary key, user_key text not null,
  events_before bigint, first_result jsonb, retry_result jsonb
) on commit drop;
insert into r66_notification_proof(notification_id,user_key)
select (n->>'id')::uuid,public.erp_r49_notification_user_key()
from public.erp_r49_list_cloud_notifications(
  '11111111-1111-4111-8111-111111111111'::uuid,false,500,0
) n limit 1;

set local role postgres;
update r66_notification_proof p set events_before=(
  select count(*) from public.erp_enterprise_notifications n
  where n.company_id='11111111-1111-4111-8111-111111111111'::uuid
    and n.id=p.notification_id
);
set local role authenticated;
update r66_notification_proof p set first_result=
  public.erp_r66_delete_cloud_notification(
    '11111111-1111-4111-8111-111111111111'::uuid,p.notification_id
  );
update r66_notification_proof p set retry_result=
  public.erp_r66_delete_cloud_notification(
    '11111111-1111-4111-8111-111111111111'::uuid,p.notification_id
  );
set local role postgres;
do $$
declare p r66_notification_proof%rowtype;
begin
  select * into p from r66_notification_proof;
  if p.notification_id is null then raise exception 'R66 notification fixture missing'; end if;
  if not coalesce((p.first_result->>'ok')::boolean,false)
    or not coalesce((p.retry_result->>'ok')::boolean,false)
    then raise exception 'R66 notification delete/retry failed'; end if;
  if (select count(*) from public.erp_enterprise_notifications n
      where n.company_id='11111111-1111-4111-8111-111111111111'::uuid
        and n.id=p.notification_id)<>p.events_before
    then raise exception 'R66 recipient delete mutated shared notification event'; end if;
  if not exists(select 1 from public.erp_notification_user_states s
      where s.company_id='11111111-1111-4111-8111-111111111111'::uuid
        and s.notification_id=p.notification_id and s.user_key=p.user_key and s.deleted)
    then raise exception 'R66 recipient tombstone missing'; end if;
end $$;
set local role authenticated;
do $$
declare v_id uuid;
begin
  select notification_id into v_id from r66_notification_proof;
  if exists(select 1 from public.erp_r49_list_cloud_notifications(
      '11111111-1111-4111-8111-111111111111'::uuid,false,500,0) n
      where n->>'id'=v_id::text)
    then raise exception 'R66 deleted notification remains visible'; end if;
end $$;

do $$
begin
  begin
    perform public.erp_r66_delete_commercial_draft(
      '11111111-1111-4111-8111-111111111111'::uuid,
      'b0839af5-e93e-4ea5-b75a-0b7b61cd4946'::uuid,
      'sales'
    );
    raise exception 'R66.1 executed Sales order delete unexpectedly succeeded';
  exception when others then
    if sqlerrm not like 'draft_delete_only:%' then raise; end if;
  end;
end $$;

rollback;
\echo 'R66 authenticated runtime defect proof PASS'
