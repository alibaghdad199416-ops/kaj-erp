-- Quality Line ERP R70.4 — browser-reproduced Opportunity runtime repair.
-- Forward-only. Preserve R61-R69 commercial/maintenance cancellation semantics.
begin;

-- ---------------------------------------------------------------------------
-- 1) Existing Sales lifecycle operations must not be mistaken for a NEW
--    conversion from a Lost Opportunity.
--
-- The legacy validator used the Opportunity terminal state for every UPDATE
-- that mentioned is_deleted/company/customer/opportunity. Commercial cancel
-- performs an internal soft-delete/reversal and restores the same historical
-- order as Cancelled. That restoration legitimately happens after the Sales
-- lifecycle sync has projected the Opportunity to Lost, so the old validator
-- rejected the restoration as though it were a new Sales Order.
-- ---------------------------------------------------------------------------
create or replace function public.erp_validate_sales_order_opportunity_link()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_slug text;
  v_payload jsonb;
  v_opportunity_customer text;
  v_same_historical_link boolean:=false;
  v_cancel_restore boolean:=false;
  v_creates_or_relinks boolean:=false;
begin
  if nullif(btrim(coalesce(new.opportunity_id,'')),'') is null then
    return new;
  end if;

  select slug into v_slug
  from public.companies
  where id=new.company_id and is_active;
  if v_slug is null then
    raise exception 'company_not_found' using errcode='23503';
  end if;

  select payload into v_payload
  from public.erp_records
  where company_id=v_slug
    and entity_type='opportunities'
    and record_id=new.opportunity_id
    and not is_deleted
    and deleted_at is null
  limit 1;

  if v_payload is null then
    raise exception 'opportunity_not_found' using errcode='23503';
  end if;

  if tg_op='UPDATE' then
    v_same_historical_link :=
      old.company_id is not distinct from new.company_id
      and old.opportunity_id is not distinct from new.opportunity_id;

    -- R61-R67 cancellation may temporarily soft-delete the existing row while
    -- reversing downstream effects, then restore that exact row as Cancelled.
    -- This is lifecycle preservation, not a new Opportunity conversion.
    v_cancel_restore :=
      v_same_historical_link
      and coalesce(old.is_deleted,false)
      and not coalesce(new.is_deleted,false)
      and lower(coalesce(new.status,'')) in ('cancelled','canceled','void');
  end if;

  v_creates_or_relinks :=
    tg_op='INSERT'
    or not v_same_historical_link
    or (
      tg_op='UPDATE'
      and coalesce(old.is_deleted,false)
      and not coalesce(new.is_deleted,false)
      and not v_cancel_restore
    );

  -- Lost remains a strict guard for NEW creation/re-link/reactivation.
  -- It intentionally does not block mutations of the already-linked historical
  -- order, including its governed cancellation restoration.
  if lower(coalesce(v_payload->>'status','pending'))='lost'
     and v_creates_or_relinks then
    raise exception 'opportunity_is_lost' using errcode='P0001';
  end if;

  -- Customer integrity remains enforced for both new and historical operations.
  v_opportunity_customer := nullif(btrim(coalesce(v_payload->>'customerId','')),'');
  if v_opportunity_customer is not null
     and v_opportunity_customer is distinct from new.customer_id then
    raise exception 'opportunity_customer_mismatch' using errcode='23514';
  end if;

  return new;
end;
$$;

revoke all on function public.erp_validate_sales_order_opportunity_link()
  from public,anon,authenticated;
grant execute on function public.erp_validate_sales_order_opportunity_link()
  to service_role;

-- Keep the established trigger columns because they protect link/customer
-- integrity, but use the operation-aware validator above.
drop trigger if exists erp_validate_sales_order_opportunity_link_trg
on public.erp_sales_orders_cloud;
create trigger erp_validate_sales_order_opportunity_link_trg
before insert or update of company_id,customer_id,opportunity_id,is_deleted
on public.erp_sales_orders_cloud
for each row
when (not coalesce(new.is_deleted,false))
execute function public.erp_validate_sales_order_opportunity_link();

-- ---------------------------------------------------------------------------
-- 2) Opportunity <-> Maintenance is already persisted by R56 using
--    erp_maintenance_orders.opportunity_id. R70 must expose it authoritatively,
--    including the latest cancelled historical order when no active one exists.
-- ---------------------------------------------------------------------------
create index if not exists idx_r70_maintenance_opportunity_history
  on public.erp_maintenance_orders(company_id,opportunity_id,updated_at desc,id)
  where opportunity_id is not null and not is_deleted;

create or replace function public.erp_r56_find_maintenance_by_opportunity(
  p_company_id uuid,p_opportunity_id text
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_result jsonb;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'maintenance.view') then
    raise exception 'permission_denied:maintenance.view' using errcode='42501';
  end if;

  select public.erp_r9_filter_result_json(
    p_company_id,
    'maintenance',
    to_jsonb(x)||jsonb_build_object(
      'updatedAt',o.updated_at,
      'opportunityId',o.opportunity_id,
      'opportunityNumber',o.opportunity_number
    ),
    'maintenance.view'
  )
  into v_result
  from public.erp_list_cloud_maintenance_orders(p_company_id) x
  join public.erp_maintenance_orders o
    on o.company_id=p_company_id and o.id=x.id
  where o.opportunity_id=p_opportunity_id
    and not o.is_deleted
  order by
    case
      when o.cancelled_at is null
       and lower(coalesce(o.workflow_stage,o.status,''))<>'cancelled'
      then 0 else 1
    end,
    o.updated_at desc,
    o.created_at desc,
    o.id desc
  limit 1;

  return v_result;
end $$;

revoke all on function public.erp_r56_find_maintenance_by_opportunity(uuid,text)
  from public,anon;
grant execute on function public.erp_r56_find_maintenance_by_opportunity(uuid,text)
  to authenticated,service_role;

-- ---------------------------------------------------------------------------
-- 3) One coherent Opportunity read now carries BOTH commercial Sales and
--    Maintenance identities. Maintenance data is read from its canonical table,
--    never from duplicated client JSON.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r70_list_opportunities(p_company_id uuid)
returns setof jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_slug text;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'customer_service.view') then
    raise exception 'permission_denied:customer_service.view' using errcode='42501';
  end if;

  select slug into v_slug
  from public.companies
  where id=p_company_id and is_active;
  if v_slug is null then
    raise exception 'company_not_found' using errcode='23503';
  end if;

  return query
  select public.erp_r9_filter_readable_json(
    p_company_id,
    'opportunities',
    (r.payload - array[
      'saleId','salesOrderId','salesOrderNumber','salesOrderStatus',
      'deliveryId','deliveryNumber','deliveryStatus',
      'invoiceId','invoiceNumber','invoiceStatus','invoiceCurrency',
      'paidAmount','remainingAmount','paymentStatus','workflowLinked',
      'workflowCanOpen','workflowCompleted',
      'maintenanceOrderId','maintenanceOrderNumber','maintenanceOrderStatus'
    ]::text[]) ||
    jsonb_build_object(
      'id',r.record_id,
      'opportunityNumber',coalesce(nullif(r.payload->>'opportunityNumber',''),r.record_id),
      'salesOrderId',case when o.id is null then null else o.id::text end,
      'saleId',case when o.id is null then null else o.id::text end,
      'salesOrderNumber',o.order_number,
      'salesOrderStatus',o.status,
      'deliveryId',case when d.id is null then null else d.id::text end,
      'deliveryNumber',d.document_number,
      'deliveryStatus',d.status,
      'invoiceId',case when i.id is null then null else i.id::text end,
      'invoiceNumber',i.document_number,
      'invoiceStatus',i.status,
      'invoiceCurrency',i.payload->>'currency',
      'paidAmount',case when i.id is null then 0 else public.erp_try_numeric(i.payload->>'paidAmount',0) end,
      'remainingAmount',case when i.id is null then 0 else greatest(0,public.erp_try_numeric(
        i.payload->>'remainingAmount',
        public.erp_try_numeric(i.payload->>'totalAmount',0)-public.erp_try_numeric(i.payload->>'paidAmount',0)
      )) end,
      'paymentStatus',case
        when i.id is null then 'not_invoiced'
        when greatest(0,public.erp_try_numeric(i.payload->>'remainingAmount',
          public.erp_try_numeric(i.payload->>'totalAmount',0)-public.erp_try_numeric(i.payload->>'paidAmount',0)))<=0.001 then 'paid'
        when public.erp_try_numeric(i.payload->>'paidAmount',0)>0 then 'partial'
        else 'unpaid' end,
      'workflowLinked',o.id is not null,
      'workflowCanOpen',o.id is not null,
      'workflowCompleted',i.id is not null
        and lower(coalesce(i.status,'')) in ('approved','paid','completed')
        and greatest(0,public.erp_try_numeric(i.payload->>'remainingAmount',
          public.erp_try_numeric(i.payload->>'totalAmount',0)-public.erp_try_numeric(i.payload->>'paidAmount',0)))<=0.001,
      'maintenanceOrderId',case when m.id is null then null else m.id::text end,
      'maintenanceOrderNumber',m.order_number,
      'maintenanceOrderStatus',coalesce(nullif(m.workflow_stage,''),m.status),
      'updatedAt',greatest(r.updated_at,coalesce(m.updated_at,r.updated_at)),
      '_cloudUpdatedAt',greatest(r.updated_at,coalesce(m.updated_at,r.updated_at))
    )
  )
  from public.erp_records r
  left join lateral (
    select so.*
    from public.erp_sales_orders_cloud so
    where so.company_id=p_company_id
      and so.opportunity_id=r.record_id
      and not so.is_deleted
    order by so.updated_at desc,so.created_at desc,so.id desc
    limit 1
  ) o on true
  left join lateral (
    select doc.*
    from public.erp_commercial_workflow_documents doc
    where o.id is not null
      and doc.company_id=p_company_id
      and doc.parent_id=o.id
      and doc.module='sales'
      and doc.document_type='delivery'
      and not doc.is_deleted
    order by doc.updated_at desc,doc.created_at desc,doc.id desc
    limit 1
  ) d on true
  left join lateral (
    select doc.*
    from public.erp_commercial_workflow_documents doc
    where o.id is not null
      and doc.company_id=p_company_id
      and doc.parent_id=o.id
      and doc.module='sales'
      and doc.document_type='invoice'
      and not doc.is_deleted
    order by doc.updated_at desc,doc.created_at desc,doc.id desc
    limit 1
  ) i on true
  left join lateral (
    select mo.*
    from public.erp_maintenance_orders mo
    where mo.company_id=p_company_id
      and mo.opportunity_id=r.record_id
      and not mo.is_deleted
    order by
      case
        when mo.cancelled_at is null
         and lower(coalesce(mo.workflow_stage,mo.status,''))<>'cancelled'
        then 0 else 1
      end,
      mo.updated_at desc,
      mo.created_at desc,
      mo.id desc
    limit 1
  ) m on true
  where r.company_id=v_slug
    and r.entity_type='opportunities'
    and not r.is_deleted
    and r.deleted_at is null
  order by greatest(r.updated_at,coalesce(m.updated_at,r.updated_at)) desc
  limit 500;
end $$;

revoke all on function public.erp_r70_list_opportunities(uuid)
  from public,anon;
grant execute on function public.erp_r70_list_opportunities(uuid)
  to authenticated,service_role;

notify pgrst,'reload schema';
commit;
