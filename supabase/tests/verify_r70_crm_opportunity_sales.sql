\set ON_ERROR_STOP on
begin;

select set_config(
  'request.jwt.claims',
  '{"sub":"5dfff075-0653-4918-bcce-293eea5e68d6","role":"authenticated"}',
  true
);
set local role postgres;

do $$
declare
  c constant uuid:='11111111-1111-4111-8111-111111111111';
  s text;
begin
  select slug into s from public.companies where id=c;
  if s is null then raise exception 'R70 fixture company missing'; end if;

  insert into public.erp_records(
    company_id,entity_type,record_id,payload,updated_at,deleted_at
  ) values(
    s,'opportunities','r70-opportunity-1',
    jsonb_build_object(
      'id','r70-opportunity-1','opportunityNumber','OPP-R70-001',
      'customerId','r70-customer','customerName','R70 Customer',
      'customerPhone','000','title','R70 CRM proof','source','test',
      'expectedValue',1250,'currency','USD','stage','qualified','probability',40,
      'status','pending','assignedUserId','','assignedUserName','',
      'createdByUserId','5dfff075-0653-4918-bcce-293eea5e68d6',
      'createdByUserName','R70 verifier','createdAt',now(),'updatedAt',now()
    ),now(),null
  ) on conflict(company_id,entity_type,record_id) do update
    set payload=excluded.payload,updated_at=now(),deleted_at=null;
end $$;

set local role authenticated;
do $$
declare
  c constant uuid:='11111111-1111-4111-8111-111111111111';
  row_data jsonb;
begin
  select x into row_data
  from public.erp_r70_list_opportunities(c) x
  where x->>'id'='r70-opportunity-1';
  if row_data is null then raise exception 'R70 opportunity snapshot missing'; end if;
  if row_data->>'opportunityNumber'<>'OPP-R70-001' then
    raise exception 'R70 business reference mismatch';
  end if;
  if coalesce(row_data->>'workflowLinked','false')::boolean then
    raise exception 'R70 unlinked opportunity reported workflow linkage';
  end if;

  begin
    perform public.erp_r70_opportunity_command(
      'mark_won',jsonb_build_object('opportunity_id','r70-opportunity-1')
    );
    raise exception 'R70 legacy mark_won unexpectedly succeeded';
  exception when others then
    if sqlerrm<>'opportunity_won_owned_by_sales_workflow' then raise; end if;
  end;
end $$;

set local role postgres;
insert into public.erp_sales_orders_cloud(
  id,company_id,order_number,customer_id,opportunity_id,status,currency,
  exchange_rate,subtotal,discount,total,notes,is_deleted
) values(
  '70000000-0000-4000-8000-000000000001',
  '11111111-1111-4111-8111-111111111111',
  'SO-R70-001','r70-customer','r70-opportunity-1','draft','USD',1,1250,0,1250,
  'R70 rollback proof',false
);

set local role authenticated;
do $$
declare
  c constant uuid:='11111111-1111-4111-8111-111111111111';
  row_data jsonb;
  changed timestamptz;
begin
  select x into row_data
  from public.erp_r70_list_opportunities(c) x
  where x->>'id'='r70-opportunity-1';
  if row_data->>'salesOrderNumber'<>'SO-R70-001'
     or row_data->>'salesOrderStatus'<>'draft'
     or row_data->>'saleId'<>'70000000-0000-4000-8000-000000000001' then
    raise exception 'R70 two-way opportunity -> sales projection failed: %',row_data;
  end if;
  if nullif(row_data->>'invoiceNumber','') is not null then
    raise exception 'R70 sales order was falsely presented as invoice: %',row_data->>'invoiceNumber';
  end if;

  begin
    perform public.erp_r70_opportunity_command(
      'mark_lost',jsonb_build_object(
        'id','r70-opportunity-1','expected_updated_at',row_data->>'updatedAt'
      )
    );
    raise exception 'R70 mark_lost unexpectedly accepted active Sales';
  exception when others then
    if sqlerrm<>'opportunity_has_active_sales_order' then raise; end if;
  end;

  begin
    perform public.erp_r70_opportunity_command(
      'delete',jsonb_build_object(
        'id','r70-opportunity-1','expected_updated_at',row_data->>'updatedAt'
      )
    );
    raise exception 'R70 opportunity delete unexpectedly orphaned active Sales';
  exception when others then
    if sqlerrm<>'opportunity_has_sales_history' then raise; end if;
  end;

  select updated_at into changed
  from public.erp_records r join public.companies c2 on c2.slug=r.company_id
  where c2.id=c and r.entity_type='opportunities' and r.record_id='r70-opportunity-1';

  begin
    perform public.erp_r70_opportunity_command(
      'save',jsonb_build_object(
        'create_only',false,
        'expected_updated_at',changed,
        'record',jsonb_build_object(
          'id','r70-opportunity-1','customerId','different-customer',
          'currency','USD','expectedValue',1250,'probability',40,'stage','qualified'
        )
      )
    );
    raise exception 'R70 linked opportunity customer mutation unexpectedly succeeded';
  exception when others then
    if sqlerrm<>'opportunity_customer_mismatch'
       and sqlerrm<>'opportunity_sales_customer_locked' then raise; end if;
  end;
end $$;

set local role postgres;
do $$
begin
  begin
    insert into public.erp_sales_orders_cloud(
      id,company_id,order_number,customer_id,opportunity_id,status,currency,
      exchange_rate,subtotal,discount,total,is_deleted
    ) values(
      '70000000-0000-4000-8000-000000000002',
      '11111111-1111-4111-8111-111111111111',
      'SO-R70-002','r70-customer','r70-opportunity-1','draft','USD',1,1,0,1,false
    );
    raise exception 'R70 duplicate opportunity Sales link unexpectedly succeeded';
  exception when unique_violation then null;
  end;

  if position('erp_v2300_create_sales_order' in
      pg_get_functiondef('public.erp_r49_create_sales_order(uuid,jsonb)'::regprocedure))=0 then
    raise exception 'R70 runtime create endpoint no longer delegates to canonical Sales draft creation';
  end if;
  if position('opportunity_won_owned_by_sales_workflow' in
      pg_get_functiondef('public.erp_r70_opportunity_command(text,jsonb)'::regprocedure))=0 then
    raise exception 'R70 legacy direct Won shortcut is not closed';
  end if;
end $$;

rollback;
\echo 'R70 CRM opportunity-sales rollback proof PASS'
