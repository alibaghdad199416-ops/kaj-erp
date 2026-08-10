-- V7.1: make product transfers visibly document-centric, preserve partner
-- payments when deleting operational documents, purge complete recycle batches,
-- and keep product accounting assignments usable from lazy-loaded screens.

alter table public.erp_maintenance_payments
  add column if not exists detached_from_order_id uuid,
  add column if not exists partner_type text,
  add column if not exists partner_id text,
  add column if not exists is_unapplied boolean not null default false,
  add column if not exists detached_at timestamptz;

-- Mark all current and historical product transfers as one source-to-destination
-- document. The two stock movements remain audit rows but are no longer the UI
-- representation of the transfer.
update public.erp_warehouse_transfers as t
set data=t.data||jsonb_build_object(
  'sourceAndDestinationInOneDocument',true,
  'displayMode','unified_document',
  'updatedAt',now()
)
where not t.is_deleted
  and coalesce(t.data->>'sourceAndDestinationInOneDocument','false')<>'true';

update public.erp_warehouse_transfer_items as i
set data=i.data||jsonb_build_object(
  'fromWarehouseId',coalesce(i.data->>'fromWarehouseId',t.data->>'fromWarehouseId',t.data->>'from_warehouse_id'),
  'toWarehouseId',coalesce(i.data->>'toWarehouseId',t.data->>'toWarehouseId',t.data->>'to_warehouse_id'),
  'displayMode','unified_document'
)
from public.erp_warehouse_transfers as t
where i.company_id=t.company_id
  and coalesce(i.data->>'transferId',i.data->>'transfer_id')=t.id
  and not i.is_deleted
  and not t.is_deleted;

update public.erp_inventory_movements as m
set data=m.data||jsonb_build_object(
  'transferDocumentId',coalesce(m.data->>'referenceId',m.data->>'reference_id'),
  'displayMode','audit_child_of_unified_transfer',
  'hideFromStandaloneMovementList',true
)
where not m.is_deleted
  and lower(coalesce(m.data->>'referenceType',m.data->>'reference_type',''))='warehouse_transfer'
  and lower(coalesce(m.data->>'movementType',m.data->>'movement_type','')) in ('transfer_in','transfer_out');

create or replace function public.erp_detach_cloud_workflow_invoice_payments(
  p_company_id uuid,
  p_invoice_id uuid,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_doc public.erp_commercial_workflow_documents%rowtype;
  v_payment jsonb;
  v_payments jsonb;
  v_detached jsonb:='[]'::jsonb;
  v_cash_id text;
  v_journal_id text;
  v_payment_id text;
  v_partner_id text;
  v_partner_type text;
  v_now timestamptz:=now();
begin
  if not public.erp_is_company_member(p_company_id) then
    raise exception 'access_denied';
  end if;

  select d.* into v_doc
  from public.erp_commercial_workflow_documents as d
  where d.company_id=p_company_id
    and d.id=p_invoice_id
    and d.document_type='invoice'
    and not d.is_deleted
  for update;
  if not found then
    raise exception 'invoice_not_found';
  end if;

  if v_doc.module='sales' then
    select o.customer_id into v_partner_id
    from public.erp_sales_orders_cloud as o
    where o.company_id=p_company_id and o.id=v_doc.parent_id;
    v_partner_type:='customer';
  elsif v_doc.module='purchases' then
    select o.supplier_id into v_partner_id
    from public.erp_purchase_orders_cloud as o
    where o.company_id=p_company_id and o.id=v_doc.parent_id;
    v_partner_type:='supplier';
  else
    raise exception 'invalid_workflow_module';
  end if;

  v_payments:=coalesce(v_doc.payload->'payments','[]'::jsonb);
  if jsonb_typeof(v_payments)<>'array' then
    v_payments:='[]'::jsonb;
  end if;

  for v_payment in select value from jsonb_array_elements(v_payments)
  loop
    v_cash_id:=nullif(coalesce(v_payment->>'cashTransactionId',v_payment->>'cash_transaction_id'),'');
    v_journal_id:=nullif(coalesce(v_payment->>'journalEntryId',v_payment->>'journal_entry_id'),'');
    v_payment_id:=nullif(coalesce(v_payment->>'paymentId',v_payment->>'payment_id'),'');

    if v_cash_id is not null then
      update public.erp_cash_transactions as ct
      set data=(
            ct.data
            - 'invoiceId' - 'invoice_id'
            - 'orderId' - 'order_id'
            - 'referenceId' - 'reference_id'
            - 'referenceType' - 'reference_type'
          )||jsonb_build_object(
            'referenceType','partner_advance',
            'referenceId',coalesce(v_partner_id,v_payment_id,v_cash_id),
            'partyType',v_partner_type,
            'partyId',v_partner_id,
            'unapplied',true,
            'detachedFromInvoiceId',p_invoice_id::text,
            'detachedFromOrderId',v_doc.parent_id::text,
            'detachedAt',v_now,
            'detachmentReason',coalesce(p_reason,'Operational document deleted; partner payment preserved')
          ),
          updated_at=v_now,
          updated_by=auth.uid()
      where ct.company_id=p_company_id
        and ct.id=v_cash_id
        and not ct.is_deleted;
    end if;

    if v_journal_id is not null then
      update public.erp_journal_entries as je
      set data=(
            je.data
            - 'invoiceId' - 'invoice_id'
            - 'orderId' - 'order_id'
            - 'referenceId' - 'reference_id'
            - 'referenceType' - 'reference_type'
          )||jsonb_build_object(
            'referenceType','partner_advance',
            'referenceId',coalesce(v_payment_id,v_cash_id,v_journal_id),
            'partyType',v_partner_type,
            'partyId',v_partner_id,
            'unapplied',true,
            'detachedFromInvoiceId',p_invoice_id::text,
            'detachedFromOrderId',v_doc.parent_id::text,
            'detachedAt',v_now,
            'detachmentReason',coalesce(p_reason,'Operational document deleted; partner payment preserved')
          ),
          updated_at=v_now,
          updated_by=auth.uid()
      where je.company_id=p_company_id
        and je.id=v_journal_id
        and not je.is_deleted;
    end if;

    v_detached:=v_detached||jsonb_build_array(
      v_payment||jsonb_build_object(
        'unapplied',true,
        'partyType',v_partner_type,
        'partyId',v_partner_id,
        'detachedFromInvoiceId',p_invoice_id::text,
        'detachedFromOrderId',v_doc.parent_id::text,
        'detachedAt',v_now
      )
    );
  end loop;

  update public.erp_commercial_workflow_documents as d
  set payload=jsonb_set(
        jsonb_set(
          jsonb_set(
            jsonb_set(
              d.payload||jsonb_build_object(
                'detachedPayments',v_detached,
                'paymentsDetachedAt',v_now,
                'paymentsDetachmentReason',p_reason
              ),
              '{payments}','[]'::jsonb,true
            ),
            '{paidAmount}','0'::jsonb,true
          ),
          '{remainingAmount}',to_jsonb(public.erp_try_numeric(d.payload->>'totalAmount',0)),true
        ),
        '{paymentStatus}',to_jsonb('unpaid'::text),true
      ),
      updated_at=v_now,
      updated_by=auth.uid()
  where d.company_id=p_company_id and d.id=p_invoice_id;

  perform public.erp_commercial_audit(
    p_company_id,v_doc.module,v_doc.parent_id,v_doc.id,v_doc.document_number,
    'detach_invoice_payments',v_doc.status,v_doc.status,
    coalesce(p_reason,'Partner payment preserved as unapplied balance')
  );

  return v_detached;
end;
$$;

create or replace function public.erp_prepare_commercial_order_delete_keep_payments(
  p_company_id uuid,
  p_order_id uuid,
  p_module text,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_order_status text;
  v_documents jsonb;
  v_detached_payments jsonb:='[]'::jsonb;
  v_doc record;
  v_detached jsonb;
begin
  if p_module='sales' then
    select o.status into v_order_status
    from public.erp_sales_orders_cloud as o
    where o.company_id=p_company_id and o.id=p_order_id and not o.is_deleted
    for update;
  elsif p_module='purchases' then
    select o.status into v_order_status
    from public.erp_purchase_orders_cloud as o
    where o.company_id=p_company_id and o.id=p_order_id and not o.is_deleted
    for update;
  else
    raise exception 'invalid_workflow_module';
  end if;
  if not found then raise exception 'order_not_found'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',d.id,
    'documentType',d.document_type,
    'documentNumber',d.document_number,
    'status',d.status,
    'warehouseId',d.warehouse_id,
    'payload',d.payload
  ) order by d.created_at,d.id),'[]'::jsonb)
  into v_documents
  from public.erp_commercial_workflow_documents as d
  where d.company_id=p_company_id
    and d.parent_id=p_order_id
    and d.module=p_module
    and not d.is_deleted;

  for v_doc in
    select d.id
    from public.erp_commercial_workflow_documents as d
    where d.company_id=p_company_id
      and d.parent_id=p_order_id
      and d.module=p_module
      and d.document_type='invoice'
      and not d.is_deleted
      and d.status<>'cancelled'
    order by d.created_at desc,d.id desc
  loop
    v_detached:=public.erp_detach_cloud_workflow_invoice_payments(
      p_company_id,v_doc.id,coalesce(p_reason,'Delete order but keep partner payments')
    );
    v_detached_payments:=v_detached_payments||coalesce(v_detached,'[]'::jsonb);
    perform public.erp_cancel_cloud_workflow_invoice(
      p_company_id,v_doc.id,p_module,coalesce(p_reason,'Delete order and cancel invoice posting')
    );
  end loop;

  for v_doc in
    select d.id
    from public.erp_commercial_workflow_documents as d
    where d.company_id=p_company_id
      and d.parent_id=p_order_id
      and d.module=p_module
      and d.document_type=case when p_module='sales' then 'delivery' else 'receipt' end
      and not d.is_deleted
      and d.status<>'cancelled'
    order by d.created_at desc,d.id desc
  loop
    if p_module='sales' then
      perform public.erp_cancel_cloud_sales_delivery(p_company_id,v_doc.id);
    else
      perform public.erp_cancel_cloud_purchase_receipt(p_company_id,v_doc.id);
    end if;
  end loop;

  return jsonb_build_object(
    'orderStatus',v_order_status,
    'documents',v_documents,
    'detachedPayments',v_detached_payments,
    'paymentsPreserved',true
  );
end;
$$;

create or replace function public.erp_delete_cloud_sales_order(
  p_company_id uuid,
  p_order_id uuid
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_snapshot jsonb;
  v_number text;
  v_batch uuid:=gen_random_uuid();
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['sales.delete']);
  select o.order_number into v_number
  from public.erp_sales_orders_cloud as o
  where o.company_id=p_company_id and o.id=p_order_id and not o.is_deleted
  for update;
  if not found then return; end if;

  perform set_config('qualityline.deletion_batch_id',v_batch::text,true);
  perform set_config('qualityline.deletion_root_table','erp_sales_orders_cloud',true);
  perform set_config('qualityline.deletion_root_id',p_order_id::text,true);
  perform set_config('qualityline.deletion_reason','Delete sales order, reverse operational links, preserve customer payment',true);

  v_snapshot:=public.erp_prepare_commercial_order_delete_keep_payments(
    p_company_id,p_order_id,'sales',
    'Delete sales order, reverse stock/invoice links, preserve customer payment as unapplied credit'
  );

  update public.erp_commercial_workflow_documents
  set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid()
  where company_id=p_company_id and parent_id=p_order_id and module='sales' and not is_deleted;

  update public.erp_sales_order_items_cloud
  set is_deleted=true,deleted_at=now(),updated_at=now()
  where company_id=p_company_id and order_id=p_order_id and not is_deleted;

  update public.erp_sales_orders_cloud
  set is_deleted=true,deleted_at=now(),updated_at=now()
  where company_id=p_company_id and id=p_order_id and not is_deleted;

  perform public.erp_commercial_audit(
    p_company_id,'sales',p_order_id,null,v_number,'delete_order_keep_payment',
    v_snapshot->>'orderStatus','deleted',
    'Operational links removed; customer payment retained as unapplied account credit'
  );

  update public.erp_universal_recycle_bin
  set relation_context=relation_context||jsonb_build_object(
    'commercialModule','sales',
    'commercialSnapshot',v_snapshot,
    'paymentsPreserved',true,
    'paymentDisposition','customer_unapplied_credit'
  )
  where company_id=p_company_id and deletion_batch_id=v_batch;
end;
$$;

create or replace function public.erp_delete_cloud_purchase_order(
  p_company_id uuid,
  p_order_id uuid
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_snapshot jsonb;
  v_number text;
  v_batch uuid:=gen_random_uuid();
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['purchases.delete']);
  select o.order_number into v_number
  from public.erp_purchase_orders_cloud as o
  where o.company_id=p_company_id and o.id=p_order_id and not o.is_deleted
  for update;
  if not found then return; end if;

  perform set_config('qualityline.deletion_batch_id',v_batch::text,true);
  perform set_config('qualityline.deletion_root_table','erp_purchase_orders_cloud',true);
  perform set_config('qualityline.deletion_root_id',p_order_id::text,true);
  perform set_config('qualityline.deletion_reason','Delete purchase order, reverse operational links, preserve supplier payment',true);

  v_snapshot:=public.erp_prepare_commercial_order_delete_keep_payments(
    p_company_id,p_order_id,'purchases',
    'Delete purchase order, reverse stock/invoice links, preserve supplier payment as unapplied debit'
  );

  update public.erp_commercial_workflow_documents
  set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid()
  where company_id=p_company_id and parent_id=p_order_id and module='purchases' and not is_deleted;

  update public.erp_purchase_order_items_cloud
  set is_deleted=true,deleted_at=now(),updated_at=now()
  where company_id=p_company_id and order_id=p_order_id and not is_deleted;

  update public.erp_purchase_orders_cloud
  set is_deleted=true,deleted_at=now(),updated_at=now()
  where company_id=p_company_id and id=p_order_id and not is_deleted;

  perform public.erp_commercial_audit(
    p_company_id,'purchases',p_order_id,null,v_number,'delete_order_keep_payment',
    v_snapshot->>'orderStatus','deleted',
    'Operational links removed; supplier payment retained as unapplied account debit'
  );

  update public.erp_universal_recycle_bin
  set relation_context=relation_context||jsonb_build_object(
    'commercialModule','purchases',
    'commercialSnapshot',v_snapshot,
    'paymentsPreserved',true,
    'paymentDisposition','supplier_unapplied_debit'
  )
  where company_id=p_company_id and deletion_batch_id=v_batch;
end;
$$;

create or replace function public.erp_delete_cloud_maintenance_order(
  p_company_id uuid,
  p_order_id uuid,
  p_reason text default null
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_order public.erp_maintenance_orders%rowtype;
  v_cash record;
  v_reason text:=coalesce(nullif(btrim(p_reason),''),'Delete maintenance order and preserve customer payment');
  v_batch uuid:=gen_random_uuid();
  v_now timestamptz:=now();
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['maintenance.delete']
  );

  select o.* into v_order
  from public.erp_maintenance_orders as o
  where o.company_id=p_company_id and o.id=p_order_id
  for update;
  if not found then raise exception 'maintenance_order_not_found'; end if;
  if v_order.is_deleted then return; end if;

  perform set_config('qualityline.deletion_batch_id',v_batch::text,true);
  perform set_config('qualityline.deletion_root_table','erp_maintenance_orders',true);
  perform set_config('qualityline.deletion_root_id',p_order_id::text,true);
  perform set_config('qualityline.deletion_reason',v_reason,true);

  for v_cash in
    select
      ct.id,
      coalesce(
        nullif(ct.data->>'journalEntryId',''),
        nullif(ct.data->>'journal_entry_id',''),
        nullif(ct.data->>'entryId',''),
        nullif(ct.data->>'entry_id','')
      ) as journal_id
    from public.erp_cash_transactions as ct
    where ct.company_id=p_company_id
      and not ct.is_deleted
      and coalesce(
        ct.data->>'maintenanceOrderId',
        ct.data->>'maintenance_order_id',
        ct.data->>'referenceId',
        ct.data->>'reference_id'
      )=p_order_id::text
    for update
  loop
    update public.erp_cash_transactions as ct
    set data=(
          ct.data
          - 'maintenanceOrderId' - 'maintenance_order_id'
          - 'invoiceId' - 'invoice_id'
          - 'orderId' - 'order_id'
          - 'referenceId' - 'reference_id'
          - 'referenceType' - 'reference_type'
        )||jsonb_build_object(
          'referenceType','partner_advance',
          'referenceId',coalesce(v_order.customer_id::text,v_cash.id),
          'partyType','customer',
          'partyId',v_order.customer_id::text,
          'unapplied',true,
          'detachedFromMaintenanceOrderId',p_order_id::text,
          'detachedAt',v_now,
          'detachmentReason',v_reason
        ),
        updated_at=v_now,
        updated_by=auth.uid()
    where ct.company_id=p_company_id and ct.id=v_cash.id and not ct.is_deleted;

    if v_cash.journal_id is not null then
      update public.erp_journal_entries as je
      set data=(
            je.data
            - 'maintenanceOrderId' - 'maintenance_order_id'
            - 'invoiceId' - 'invoice_id'
            - 'orderId' - 'order_id'
            - 'referenceId' - 'reference_id'
            - 'referenceType' - 'reference_type'
          )||jsonb_build_object(
            'referenceType','partner_advance',
            'referenceId',coalesce(v_order.customer_id::text,v_cash.journal_id),
            'partyType','customer',
            'partyId',v_order.customer_id::text,
            'unapplied',true,
            'detachedFromMaintenanceOrderId',p_order_id::text,
            'detachedAt',v_now,
            'detachmentReason',v_reason
          ),
          updated_at=v_now,
          updated_by=auth.uid()
      where je.company_id=p_company_id
        and je.id=v_cash.journal_id
        and not je.is_deleted;
    end if;
  end loop;

  update public.erp_maintenance_payments as p
  set detached_from_order_id=p_order_id,
      partner_type='customer',
      partner_id=v_order.customer_id::text,
      is_unapplied=true,
      detached_at=v_now,
      notes=concat_ws(
        E'\n',
        nullif(p.notes,''),
        'Payment preserved after maintenance order deletion: '||v_reason
      )
  where p.company_id=p_company_id
    and p.maintenance_order_id=p_order_id
    and not p.is_deleted;

  perform public.erp_v66_reverse_maintenance_stock(
    p_company_id,p_order_id,v_reason
  );

  update public.erp_maintenance_parts
  set is_deleted=true,deleted_at=v_now,updated_at=v_now
  where company_id=p_company_id
    and maintenance_order_id=p_order_id
    and not is_deleted;

  update public.erp_maintenance_orders
  set paid_amount=0,
      status='cancelled',
      workflow_stage='cancelled',
      cancel_reason=v_reason,
      cancelled_at=coalesce(cancelled_at,v_now),
      is_deleted=true,
      deleted_at=v_now,
      deleted_by=auth.uid(),
      deleted_reason=v_reason,
      updated_at=v_now
  where company_id=p_company_id and id=p_order_id;

  update public.erp_universal_recycle_bin
  set relation_context=relation_context||jsonb_build_object(
    'maintenanceWorkflowStage',v_order.workflow_stage,
    'maintenanceOrderNumber',v_order.order_number,
    'linkedInventoryReversed',true,
    'paymentsPreserved',true,
    'paymentDisposition','customer_unapplied_credit',
    'customerId',v_order.customer_id
  )
  where company_id=p_company_id and deletion_batch_id=v_batch;
end;
$$;

create or replace function public.erp_recycle_bin_purge(
  p_company_id uuid,
  p_entity_type text,
  p_record_id text
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_deleted integer:=0;
  v_legacy integer:=0;
  v_archive public.erp_universal_recycle_bin%rowtype;
  v_row record;
  v_pk text;
  v_has_company_id boolean;
  v_has_company_camel boolean;
  v_batch uuid;
begin
  if not public.is_company_member(p_company_id) then
    raise exception 'access_denied';
  end if;
  if not public.erp_cloud_user_has_permission(
    p_company_id,'settings.recycle_bin.purge'
  ) then
    raise exception 'permanent_delete_permission_required';
  end if;

  delete from public.erp_records
  where company_id=p_company_id::text
    and entity_type=btrim(p_entity_type)
    and record_id=btrim(p_record_id)
    and deleted_at is not null;
  get diagnostics v_legacy=row_count;
  if v_legacy>0 then
    return jsonb_build_object(
      'purged',true,
      'entityType',btrim(p_entity_type),
      'recordId',btrim(p_record_id),
      'deletedRows',v_legacy,
      'batchPurged',false
    );
  end if;

  select u.* into v_archive
  from public.erp_universal_recycle_bin as u
  where u.source_table=btrim(p_entity_type)
    and u.record_id=btrim(p_record_id)
    and (u.company_id=p_company_id or u.company_id is null)
    and u.restored_at is null
    and u.purged_at is null
  order by u.deleted_at desc
  limit 1
  for update;
  if not found then raise exception 'deleted_record_not_found'; end if;

  v_batch:=v_archive.deletion_batch_id;
  perform set_config('qualityline.recycle_purge','on',true);

  for v_row in
    select u.*
    from public.erp_universal_recycle_bin as u
    where (u.company_id=p_company_id or u.company_id is null)
      and u.restored_at is null
      and u.purged_at is null
      and (
        (v_batch is not null and u.deletion_batch_id=v_batch)
        or (v_batch is null and u.id=v_archive.id)
      )
    order by
      case
        when u.source_table in ('erp_journal_lines','erp_inventory_fifo_consumptions') then 10
        when u.source_table in ('erp_maintenance_payments','erp_maintenance_parts','erp_sales_order_items_cloud','erp_purchase_order_items_cloud','erp_warehouse_transfer_items') then 20
        when u.source_table in ('erp_inventory_movements','erp_inventory_cost_layers','erp_cash_transactions') then 30
        when u.source_table='erp_commercial_workflow_documents' then 40
        else 50
      end,
      u.deleted_at desc
  loop
    if to_regclass(format('public.%I',v_row.source_table)) is not null then
      select case
        when exists(
          select 1 from information_schema.columns
          where table_schema='public' and table_name=v_row.source_table and column_name='id'
        ) then 'id'
        when exists(
          select 1 from information_schema.columns
          where table_schema='public' and table_name=v_row.source_table and column_name='record_id'
        ) then 'record_id'
        else null
      end into v_pk;

      select exists(
        select 1 from information_schema.columns
        where table_schema='public' and table_name=v_row.source_table and column_name='company_id'
      ) into v_has_company_id;
      select exists(
        select 1 from information_schema.columns
        where table_schema='public' and table_name=v_row.source_table and column_name='companyId'
      ) into v_has_company_camel;

      if v_pk is not null then
        if v_has_company_id then
          execute format(
            'delete from public.%I where %I::text=$1 and company_id::text=$2',
            v_row.source_table,v_pk
          ) using v_row.record_id,p_company_id::text;
        elsif v_has_company_camel then
          execute format(
            'delete from public.%I where %I::text=$1 and "companyId"::text=$2',
            v_row.source_table,v_pk
          ) using v_row.record_id,p_company_id::text;
        else
          execute format(
            'delete from public.%I where %I::text=$1',
            v_row.source_table,v_pk
          ) using v_row.record_id;
        end if;
        v_deleted:=v_deleted+1;
      end if;
    end if;
  end loop;

  delete from public.erp_universal_recycle_bin as u
  where (u.company_id=p_company_id or u.company_id is null)
    and u.restored_at is null
    and u.purged_at is null
    and (
      (v_batch is not null and u.deletion_batch_id=v_batch)
      or (v_batch is null and u.id=v_archive.id)
    );

  return jsonb_build_object(
    'purged',true,
    'entityType',btrim(p_entity_type),
    'recordId',btrim(p_record_id),
    'deletedRows',v_deleted,
    'batchPurged',v_batch is not null,
    'deletionBatchId',v_batch
  );
end;
$$;

revoke all on function public.erp_detach_cloud_workflow_invoice_payments(uuid,uuid,text) from public,anon;
revoke all on function public.erp_prepare_commercial_order_delete_keep_payments(uuid,uuid,text,text) from public,anon;
revoke all on function public.erp_delete_cloud_sales_order(uuid,uuid) from public,anon;
revoke all on function public.erp_delete_cloud_purchase_order(uuid,uuid) from public,anon;
revoke all on function public.erp_delete_cloud_maintenance_order(uuid,uuid,text) from public,anon;
revoke all on function public.erp_recycle_bin_purge(uuid,text,text) from public,anon;

grant execute on function public.erp_detach_cloud_workflow_invoice_payments(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.erp_prepare_commercial_order_delete_keep_payments(uuid,uuid,text,text) to authenticated,service_role;
grant execute on function public.erp_delete_cloud_sales_order(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_delete_cloud_purchase_order(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_delete_cloud_maintenance_order(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.erp_recycle_bin_purge(uuid,text,text) to authenticated,service_role;
