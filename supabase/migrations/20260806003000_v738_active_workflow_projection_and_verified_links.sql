-- Quality Line ERP 18.9.8 / V7.3.8
-- Active commercial workflow projection, invoice-owned accounting indicators,
-- and resilient opportunity lifecycle links.
begin;

create or replace function public.erp_list_cloud_sales_workflow_orders(p_company_id uuid)
returns setof jsonb
language sql
security definer
set search_path=public
as $$
  select jsonb_build_object(
    'id',o.id::text,
    'documentType','salesOrder','documentTitle','أمر بيع',
    'orderNumber',o.order_number,
    'customerId',o.customer_id,
    'customerName',coalesce(c.data->>'name',''),
    'opportunityId',o.opportunity_id,
    'status',o.status,
    'currency',upper(o.currency),
    'exchangeRate',o.exchange_rate,
    'subtotal',o.subtotal,'discount',o.discount,'total',o.total,
    'notes',o.notes,'createdAt',o.created_at::text,'updatedAt',o.updated_at::text,
    'deliveryId',d.id::text,
    'deliveryNumber',d.document_number,
    'deliveryTitle','إذن تجهيز مخزني للبيع',
    'deliveryStatus',d.status,
    'deliveryAccountingOwner',coalesce(d.payload->>'accountingOwner','invoice'),
    'deliveryValuationPendingInvoice',public.erp_try_boolean(d.payload->>'valuationPendingInvoice',true),
    'invoiceId',i.id::text,
    'invoiceNumber',i.document_number,
    'invoiceTitle','فاتورة بيع',
    'invoiceStatus',i.status,
    'invoicePaid',public.erp_try_numeric(i.payload->>'paidAmount',0),
    'invoiceRemaining',public.erp_try_numeric(i.payload->>'remainingAmount',public.erp_try_numeric(i.payload->>'totalAmount',0)),
    'paymentStatus',coalesce(i.payload->>'paymentStatus',case
      when i.id is null then 'not_invoiced'
      when public.erp_try_numeric(i.payload->>'remainingAmount',public.erp_try_numeric(i.payload->>'totalAmount',0))<=0 then 'paid'
      else 'unpaid' end),
    'journalEntryId',i.payload->>'journalEntryId',
    'journalEntryNumber',j.data->>'entryNumber',
    'costJournalEntries',coalesce(i.payload->'costJournalEntries','[]'::jsonb),
    'accountingOwner',case when i.id is null then null else coalesce(i.payload->>'accountingOwner','invoice') end,
    'accountingReference',coalesce(i.payload->>'journalEntryId',i.id::text,o.id::text),
    'canCreateDelivery',lower(coalesce(o.status,''))='approved' and d.id is null,
    'canApproveDelivery',lower(coalesce(d.status,''))='draft',
    'canCancelDelivery',lower(coalesce(d.status,'')) in ('draft','approved'),
    'canCreateInvoice',lower(coalesce(o.status,''))='approved' and lower(coalesce(d.status,''))='approved' and i.id is null,
    'canApproveInvoice',lower(coalesce(i.status,''))='draft',
    'canRecordPayment',lower(coalesce(i.status,''))='approved'
      and public.erp_try_numeric(i.payload->>'remainingAmount',public.erp_try_numeric(i.payload->>'totalAmount',0))>0.001,
    'canCancelInvoice',lower(coalesce(i.status,'')) in ('draft','approved')
  )
  from public.erp_sales_orders_cloud o
  left join public.erp_customers c
    on c.id=o.customer_id and c.company_id=o.company_id and not c.is_deleted
  left join lateral (
    select x.* from public.erp_commercial_workflow_documents x
    where x.company_id=o.company_id and x.module='sales'
      and x.document_type='delivery' and x.parent_id=o.id and not x.is_deleted
      and lower(coalesce(x.status,'')) not in ('cancelled','canceled','voided')
    order by x.updated_at desc,x.created_at desc,x.id desc limit 1
  ) d on true
  left join lateral (
    select x.* from public.erp_commercial_workflow_documents x
    where x.company_id=o.company_id and x.module='sales'
      and x.document_type='invoice' and x.parent_id=o.id and not x.is_deleted
      and lower(coalesce(x.status,'')) not in ('cancelled','canceled','voided')
    order by x.updated_at desc,x.created_at desc,x.id desc limit 1
  ) i on true
  left join lateral (
    select je.* from public.erp_journal_entries je
    where je.company_id=o.company_id and not je.is_deleted
      and je.id=i.payload->>'journalEntryId'
    limit 1
  ) j on true
  where o.company_id=p_company_id and not o.is_deleted
    and public.erp_is_company_member(p_company_id)
  order by o.created_at desc,o.id desc;
$$;

create or replace function public.erp_list_cloud_purchase_workflow_orders(p_company_id uuid)
returns setof jsonb
language sql
security definer
set search_path=public
as $$
  select jsonb_build_object(
    'id',o.id::text,
    'documentType','purchaseOrder','documentTitle','أمر شراء',
    'orderNumber',o.order_number,
    'supplierId',o.supplier_id,
    'supplierName',coalesce(s.data->>'name',''),
    'status',o.status,
    'currency',upper(o.currency),
    'exchangeRate',o.exchange_rate,
    'subtotal',o.subtotal,'discount',o.discount,'total',o.total,
    'notes',o.notes,'createdAt',o.created_at::text,'updatedAt',o.updated_at::text,
    'receiptId',r.id::text,
    'receiptNumber',r.document_number,
    'receiptTitle','إشعار استلام مخزني للشراء',
    'receiptStatus',r.status,
    'receiptAccountingOwner',coalesce(r.payload->>'accountingOwner','invoice'),
    'receiptValuationPendingInvoice',public.erp_try_boolean(r.payload->>'valuationPendingInvoice',true),
    'invoiceId',i.id::text,
    'invoiceNumber',i.document_number,
    'invoiceTitle','فاتورة شراء',
    'invoiceStatus',i.status,
    'invoicePaid',public.erp_try_numeric(i.payload->>'paidAmount',0),
    'invoiceRemaining',public.erp_try_numeric(i.payload->>'remainingAmount',public.erp_try_numeric(i.payload->>'totalAmount',0)),
    'paymentStatus',coalesce(i.payload->>'paymentStatus',case
      when i.id is null then 'not_invoiced'
      when public.erp_try_numeric(i.payload->>'remainingAmount',public.erp_try_numeric(i.payload->>'totalAmount',0))<=0 then 'paid'
      else 'unpaid' end),
    'journalEntryId',i.payload->>'journalEntryId',
    'journalEntryNumber',j.data->>'entryNumber',
    'costJournalEntries',coalesce(i.payload->'costJournalEntries','[]'::jsonb),
    'accountingOwner',case when i.id is null then null else coalesce(i.payload->>'accountingOwner','invoice') end,
    'accountingReference',coalesce(i.payload->>'journalEntryId',i.id::text,o.id::text),
    'canCreateReceipt',lower(coalesce(o.status,''))='approved' and r.id is null,
    'canApproveReceipt',lower(coalesce(r.status,''))='draft',
    'canCancelReceipt',lower(coalesce(r.status,'')) in ('draft','approved'),
    'canCreateInvoice',lower(coalesce(o.status,''))='approved' and lower(coalesce(r.status,''))='approved' and i.id is null,
    'canApproveInvoice',lower(coalesce(i.status,''))='draft',
    'canRecordPayment',lower(coalesce(i.status,''))='approved'
      and public.erp_try_numeric(i.payload->>'remainingAmount',public.erp_try_numeric(i.payload->>'totalAmount',0))>0.001,
    'canCancelInvoice',lower(coalesce(i.status,'')) in ('draft','approved')
  )
  from public.erp_purchase_orders_cloud o
  left join public.erp_suppliers s
    on s.id=o.supplier_id and s.company_id=o.company_id and not s.is_deleted
  left join lateral (
    select x.* from public.erp_commercial_workflow_documents x
    where x.company_id=o.company_id and x.module='purchases'
      and x.document_type='receipt' and x.parent_id=o.id and not x.is_deleted
      and lower(coalesce(x.status,'')) not in ('cancelled','canceled','voided')
    order by x.updated_at desc,x.created_at desc,x.id desc limit 1
  ) r on true
  left join lateral (
    select x.* from public.erp_commercial_workflow_documents x
    where x.company_id=o.company_id and x.module='purchases'
      and x.document_type='invoice' and x.parent_id=o.id and not x.is_deleted
      and lower(coalesce(x.status,'')) not in ('cancelled','canceled','voided')
    order by x.updated_at desc,x.created_at desc,x.id desc limit 1
  ) i on true
  left join lateral (
    select je.* from public.erp_journal_entries je
    where je.company_id=o.company_id and not je.is_deleted
      and je.id=i.payload->>'journalEntryId'
    limit 1
  ) j on true
  where o.company_id=p_company_id and not o.is_deleted
    and public.erp_is_company_member(p_company_id)
  order by o.created_at desc,o.id desc;
$$;

-- Cancelled downstream documents must never keep an opportunity visually stuck
-- in an old delivery/invoice stage. Only the active workflow is synchronized.
create or replace function public.erp_sync_opportunity_sales_lifecycle(
  p_company_id uuid,p_opportunity_id text
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_slug text; o public.erp_sales_orders_cloud%rowtype;
  d public.erp_commercial_workflow_documents%rowtype;
  i public.erp_commercial_workflow_documents%rowtype;
  v_status text:='pending'; v_closed timestamptz;
  v_paid numeric:=0; v_remaining numeric:=0;
begin
  if nullif(btrim(coalesce(p_opportunity_id,'')),'') is null then return; end if;
  select slug into v_slug from public.companies where id=p_company_id;
  if v_slug is null then return; end if;

  select * into o from public.erp_sales_orders_cloud
  where company_id=p_company_id and opportunity_id=p_opportunity_id and not is_deleted
  order by updated_at desc,created_at desc,id desc limit 1;

  if found then
    if lower(coalesce(o.status,'draft'))='approved' then
      v_status:='won'; v_closed:=now();
    end if;
    select * into d from public.erp_commercial_workflow_documents
    where company_id=p_company_id and parent_id=o.id and module='sales'
      and document_type='delivery' and not is_deleted
      and lower(coalesce(status,'')) not in ('cancelled','canceled','voided')
    order by updated_at desc,created_at desc,id desc limit 1;
    select * into i from public.erp_commercial_workflow_documents
    where company_id=p_company_id and parent_id=o.id and module='sales'
      and document_type='invoice' and not is_deleted
      and lower(coalesce(status,'')) not in ('cancelled','canceled','voided')
    order by updated_at desc,created_at desc,id desc limit 1;
    if i.id is not null then
      v_paid:=public.erp_try_numeric(i.payload->>'paidAmount',0);
      v_remaining:=public.erp_try_numeric(
        i.payload->>'remainingAmount',public.erp_try_numeric(i.payload->>'totalAmount',0)
      );
    end if;
  end if;

  update public.erp_records set payload=payload||jsonb_build_object(
    'status',v_status,'closedAt',v_closed,
    'salesOrderId',case when o.id is null then null else o.id::text end,
    'saleId',case when o.id is null then null else o.id::text end,
    'salesOrderNumber',o.order_number,'salesOrderStatus',o.status,
    'deliveryId',case when d.id is null then null else d.id::text end,
    'deliveryNumber',d.document_number,'deliveryStatus',d.status,
    'invoiceId',case when i.id is null then null else i.id::text end,
    'invoiceNumber',i.document_number,'invoiceStatus',i.status,
    'invoiceCurrency',i.payload->>'currency',
    'paidAmount',v_paid,'remainingAmount',v_remaining,
    'paymentStatus',case
      when i.id is null then 'not_invoiced'
      when v_remaining<=0 then 'paid'
      when v_paid>0 then 'partial'
      else 'unpaid' end,
    'workflowLinked',o.id is not null,
    'workflowAccountingOwner',case when i.id is null then null else 'invoice' end,
    'opportunityStatusSource','sales_workflow','updatedAt',now()
  ),updated_at=now()
  where company_id=v_slug and entity_type='opportunities'
    and record_id=p_opportunity_id and deleted_at is null;
end;
$$;

revoke all on function public.erp_list_cloud_sales_workflow_orders(uuid) from public,anon;
revoke all on function public.erp_list_cloud_purchase_workflow_orders(uuid) from public,anon;
revoke all on function public.erp_sync_opportunity_sales_lifecycle(uuid,text) from public,anon;
grant execute on function public.erp_list_cloud_sales_workflow_orders(uuid) to authenticated,service_role;
grant execute on function public.erp_list_cloud_purchase_workflow_orders(uuid) to authenticated,service_role;
grant execute on function public.erp_sync_opportunity_sales_lifecycle(uuid,text) to authenticated,service_role;

commit;
