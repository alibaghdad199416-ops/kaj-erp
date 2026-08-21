\set ON_ERROR_STOP on
\pset pager off

-- Focused R99 regression: execute the real approval wrapper while stubbing only
-- downstream posting collaborators inside this transaction. ROLLBACK restores
-- the production function bodies after the proof.
begin;
set local session_replication_role=replica;

insert into auth.users(
  instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at
) values (
  '00000000-0000-0000-0000-000000000000',
  '99000000-0000-4000-8000-000000000001',
  'authenticated','authenticated','r99-sales-stage@local.invalid','',now(),
  '{}','{}',now(),now()
);

insert into public.companies(id,slug,name_ar,name_en,is_active) values (
  '99000000-0000-4000-8000-000000000010',
  'r99-sales-stage','R99 مرحلة بيع','R99 sales stage',true
);

insert into public.company_memberships(
  company_id,user_id,user_uid,user_email,role_code,is_system_admin,is_active
) values (
  '99000000-0000-4000-8000-000000000010',
  '99000000-0000-4000-8000-000000000001',
  '99000000-0000-4000-8000-000000000001',
  'r99-sales-stage@local.invalid','admin',true,true
);

insert into public.erp_customers(company_id,id,data) values (
  '99000000-0000-4000-8000-000000000010',
  '99000000-0000-4000-8000-000000000020',
  '{"name":"R99 Active Stage Customer","currency":"USD","isActive":true}'
);

insert into public.erp_sales_orders_cloud(
  id,company_id,order_number,customer_id,status,currency,exchange_rate,
  subtotal,discount,total
) values (
  '99000000-0000-4000-8000-000000000030',
  '99000000-0000-4000-8000-000000000010',
  'R99-ACTIVE-SO','99000000-0000-4000-8000-000000000020',
  'partially_executed','USD',1,100,0,100
);

insert into public.erp_commercial_workflow_documents(
  id,company_id,module,document_type,parent_id,document_number,status,payload
) values (
  '99000000-0000-4000-8000-000000000040',
  '99000000-0000-4000-8000-000000000010',
  'sales','invoice','99000000-0000-4000-8000-000000000030',
  'R99-ACTIVE-SINV','draft',
  '{"currency":"USD","totalAmount":100,"costJournalEntries":[]}'::jsonb
);

set local session_replication_role=origin;
select set_config(
  'request.jwt.claims',
  '{"sub":"99000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

do $$
declare v_def text;
begin
  select pg_get_functiondef(
    'public.erp_r22_approve_workflow_invoice(uuid,uuid,text)'::regprocedure
  ) into v_def;
  if v_def not like '%acceptedOrderStage%'
     or v_def not like '%partially_executed%' and v_def not like '%v_order_status%'
     or v_def not like '%erp_v73_recompute_commercial_order_status%'
     or v_def not like '%active_%_order_required%' then
    raise exception 'r99_active_order_stage_wrapper_not_installed';
  end if;
end $$;

-- Keep authorization real, but isolate the R99 wrapper from unrelated invoice
-- accounting/logistics fixtures. These definitions are transaction-local.
create or replace function public.erp_r22_invoice_preflight(
  p_company_id uuid,p_invoice_id uuid,p_module text
) returns jsonb
language sql security definer set search_path=public as $$
  select jsonb_build_object('ok',true,'stage','r99_test_preflight')
$$;

create or replace function public.erp_v762_assert_posted_journal_balanced(
  p_company_id uuid,p_entry_id text,p_context text
) returns void
language plpgsql security definer set search_path=public as $$
begin
  if nullif(btrim(coalesce(p_entry_id,'')),'') is null then
    raise exception 'r99_test_journal_missing';
  end if;
end;
$$;

create or replace function public.erp_approve_cloud_workflow_invoice(
  p_company_id uuid,p_invoice_id uuid,p_module text
) returns void
language plpgsql security definer set search_path=public as $$
declare
  v_order_id uuid;
  v_status text;
begin
  select parent_id into v_order_id
  from public.erp_commercial_workflow_documents
  where company_id=p_company_id and id=p_invoice_id and module=p_module;

  select status into v_status
  from public.erp_sales_orders_cloud
  where company_id=p_company_id and id=v_order_id;

  if v_status<>'approved' then
    raise exception 'r99_test_posting_engine_did_not_receive_approved_order:%',v_status;
  end if;

  update public.erp_commercial_workflow_documents
  set status='approved',
      payload=payload||jsonb_build_object('journalEntryId','r99-test-journal'),
      updated_at=now()
  where company_id=p_company_id and id=p_invoice_id;
end;
$$;

create or replace function public.erp_v73_recompute_commercial_order_status(
  p_company_id uuid,p_module text,p_order_id uuid
) returns text
language plpgsql security definer set search_path=public as $$
begin
  update public.erp_sales_orders_cloud
  set status='partially_executed',updated_at=now()
  where company_id=p_company_id and id=p_order_id;
  return 'partially_executed';
end;
$$;

do $$
declare
  v_result jsonb;
  v_order_status text;
  v_invoice_status text;
begin
  v_result:=public.erp_r22_approve_workflow_invoice(
    '99000000-0000-4000-8000-000000000010',
    '99000000-0000-4000-8000-000000000040',
    'sales'
  );

  select status into v_order_status
  from public.erp_sales_orders_cloud
  where id='99000000-0000-4000-8000-000000000030';
  select status into v_invoice_status
  from public.erp_commercial_workflow_documents
  where id='99000000-0000-4000-8000-000000000040';

  if coalesce((v_result->>'ok')::boolean,false) is not true
     or v_result->>'acceptedOrderStage'<>'partially_executed'
     or v_invoice_status<>'approved'
     or v_order_status<>'partially_executed' then
    raise exception 'r99_active_stage_approval_failed:result=% order=% invoice=%',
      v_result,v_order_status,v_invoice_status;
  end if;
end $$;

-- Prove the temporary normalization is atomic: force the downstream poster to
-- fail after R99 changes the active order to approved. The EXCEPTION
-- subtransaction must restore both order and invoice state.
create or replace function public.erp_approve_cloud_workflow_invoice(
  p_company_id uuid,p_invoice_id uuid,p_module text
) returns void
language plpgsql security definer set search_path=public as $$
begin
  if not exists(
    select 1 from public.erp_sales_orders_cloud
    where company_id=p_company_id
      and id=(select parent_id from public.erp_commercial_workflow_documents
              where company_id=p_company_id and id=p_invoice_id)
      and status='approved'
  ) then
    raise exception 'r99_test_normalization_missing_before_forced_failure';
  end if;
  raise exception 'r99_forced_posting_failure';
end;
$$;

update public.erp_commercial_workflow_documents
set status='draft',payload=payload-'journalEntryId'
where id='99000000-0000-4000-8000-000000000040';
update public.erp_sales_orders_cloud
set status='partially_executed'
where id='99000000-0000-4000-8000-000000000030';

do $$
declare
  v_result jsonb;
  v_order_status text;
  v_invoice_status text;
begin
  v_result:=public.erp_r22_approve_workflow_invoice(
    '99000000-0000-4000-8000-000000000010',
    '99000000-0000-4000-8000-000000000040',
    'sales'
  );
  select status into v_order_status from public.erp_sales_orders_cloud
   where id='99000000-0000-4000-8000-000000000030';
  select status into v_invoice_status from public.erp_commercial_workflow_documents
   where id='99000000-0000-4000-8000-000000000040';

  if coalesce((v_result->>'ok')::boolean,true) is not false
     or v_result->>'stage'<>'posting'
     or v_result->>'error' not like '%r99_forced_posting_failure%'
     or v_order_status<>'partially_executed'
     or v_invoice_status<>'draft' then
    raise exception 'r99_posting_rollback_failed:result=% order=% invoice=%',
      v_result,v_order_status,v_invoice_status;
  end if;
end $$;

rollback;
select 'R99 Sales active-order-stage approval runtime PASS' as result;
