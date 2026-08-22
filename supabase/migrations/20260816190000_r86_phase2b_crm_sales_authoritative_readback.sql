-- Quality Line ERP R86 — Phase 2B CRM/Sales authoritative readback closure.
-- Forward-only. Restores the canonical R70 Sales/Delivery/Invoice/Payment
-- projection while preserving the per-user R84 record-scope contract.
begin;

create or replace function public.erp_r84_list_opportunities(p_company_id uuid)
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

  select slug into v_slug
  from public.companies
  where id=p_company_id and is_active
  limit 1;
  if v_slug is null then
    raise exception 'membership_not_found' using errcode='42501';
  end if;

  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'customer_service.view') then
    raise exception 'permission_denied:customer_service.view' using errcode='42501';
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
      'paidAmount',case
        when i.id is null then 0
        else public.erp_try_numeric(i.payload->>'paidAmount',0)
      end,
      'remainingAmount',case
        when i.id is null then 0
        else greatest(
          0,
          public.erp_try_numeric(
            i.payload->>'remainingAmount',
            public.erp_try_numeric(i.payload->>'totalAmount',0)
              - public.erp_try_numeric(i.payload->>'paidAmount',0)
          )
        )
      end,
      'paymentStatus',case
        when i.id is null then 'not_invoiced'
        when greatest(
          0,
          public.erp_try_numeric(
            i.payload->>'remainingAmount',
            public.erp_try_numeric(i.payload->>'totalAmount',0)
              - public.erp_try_numeric(i.payload->>'paidAmount',0)
          )
        )<=0.001 then 'paid'
        when public.erp_try_numeric(i.payload->>'paidAmount',0)>0 then 'partial'
        else 'unpaid'
      end,
      'workflowLinked',o.id is not null,
      'workflowCanOpen',o.id is not null,
      'workflowCompleted',
        i.id is not null
        and lower(coalesce(i.status,'')) in ('approved','paid','completed')
        and greatest(
          0,
          public.erp_try_numeric(
            i.payload->>'remainingAmount',
            public.erp_try_numeric(i.payload->>'totalAmount',0)
              - public.erp_try_numeric(i.payload->>'paidAmount',0)
          )
        )<=0.001,
      'maintenanceOrderId',case when m.id is null then null else m.id::text end,
      'maintenanceOrderNumber',m.order_number,
      'maintenanceOrderStatus',coalesce(nullif(m.workflow_stage,''),m.status),
      'updatedAt',greatest(r.updated_at,coalesce(o.updated_at,r.updated_at),coalesce(d.updated_at,r.updated_at),coalesce(i.updated_at,r.updated_at),coalesce(m.updated_at,r.updated_at)),
      '_cloudUpdatedAt',greatest(r.updated_at,coalesce(o.updated_at,r.updated_at),coalesce(d.updated_at,r.updated_at),coalesce(i.updated_at,r.updated_at),coalesce(m.updated_at,r.updated_at))
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
    and r.deleted_at is null
    and not r.is_deleted
    and public.erp_r84_record_visible(
      p_company_id,
      'customer_service',
      null,
      coalesce(r.payload->>'createdByUserId',r.payload->>'createdBy','')
    )
  order by greatest(
    r.updated_at,
    coalesce(o.updated_at,r.updated_at),
    coalesce(d.updated_at,r.updated_at),
    coalesce(i.updated_at,r.updated_at),
    coalesce(m.updated_at,r.updated_at)
  ) desc
  limit 500;
end;
$$;

revoke all on function public.erp_r84_list_opportunities(uuid) from public,anon;
grant execute on function public.erp_r84_list_opportunities(uuid)
  to authenticated,service_role;

notify pgrst,'reload schema';
commit;
