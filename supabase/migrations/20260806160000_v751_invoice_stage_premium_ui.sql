-- Quality Line ERP 18.9.21 / V7.5.1
-- Final invoice-stage eligibility and premium workflow consistency.
begin;

create or replace function public.erp_create_cloud_sales_workflow_invoice(
  p_company_id uuid,p_order_id uuid
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id uuid:=gen_random_uuid();
  o public.erp_sales_orders_cloud%rowtype;
  l jsonb;
  v_number text;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['sales.create','sales.update','sales.approve']
  );
  select * into o
  from public.erp_sales_orders_cloud
  where company_id=p_company_id and id=p_order_id
    and lower(status) in ('approved','partially_executed') and not is_deleted
  for update;
  if not found then raise exception 'approved_sales_order_required'; end if;

  l:=public.erp_v736_active_logistics(p_company_id,p_order_id,'sales');
  if exists(
    select 1 from public.erp_commercial_workflow_documents
    where company_id=p_company_id and parent_id=p_order_id
      and module='sales' and document_type='invoice'
      and not is_deleted and status<>'cancelled'
  ) then
    raise exception 'active_sales_invoice_exists';
  end if;

  perform public.erp_v749_prepare_order_invoice_accounts(
    p_company_id,'sales',p_order_id,o.currency
  );

  v_number:=public.erp_next_document_number(
    p_company_id,'sales_invoice','SI',coalesce(o.effective_at,o.created_at)
  );
  insert into public.erp_commercial_workflow_documents(
    id,company_id,module,document_type,parent_id,document_number,payload,effective_at
  ) values(
    v_id,p_company_id,'sales','invoice',p_order_id,v_number,
    jsonb_build_object(
      'currency',upper(o.currency),'totalAmount',o.total,
      'paidAmount',0,'remainingAmount',o.total,'paymentStatus','unpaid',
      'payments','[]'::jsonb,'createdBy',auth.uid(),
      'logisticsDocumentId',l->>'id',
      'logisticsDocumentNumber',l->>'number',
      'allocations',l->'allocations','warehouseIds',l->'warehouseIds',
      'accountingOwner','invoice','currencyPreparedAt',now()
    ),coalesce(o.effective_at,o.created_at)
  );
  perform public.erp_commercial_audit(
    p_company_id,'sales',p_order_id,v_id,v_number,
    'create_invoice',null,'draft',
    'order currency independent from item cost currency'
  );
  return v_id;
end;
$$;

create or replace function public.erp_create_cloud_purchase_workflow_invoice(
  p_company_id uuid,p_order_id uuid
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id uuid:=gen_random_uuid();
  o public.erp_purchase_orders_cloud%rowtype;
  l jsonb;
  v_number text;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['purchases.create','purchases.update','purchases.approve']
  );
  select * into o
  from public.erp_purchase_orders_cloud
  where company_id=p_company_id and id=p_order_id
    and lower(status) in ('approved','partially_executed') and not is_deleted
  for update;
  if not found then raise exception 'approved_purchase_order_required'; end if;

  l:=public.erp_v736_active_logistics(p_company_id,p_order_id,'purchases');
  if exists(
    select 1 from public.erp_commercial_workflow_documents
    where company_id=p_company_id and parent_id=p_order_id
      and module='purchases' and document_type='invoice'
      and not is_deleted and status<>'cancelled'
  ) then
    raise exception 'active_purchase_invoice_exists';
  end if;

  perform public.erp_v749_prepare_order_invoice_accounts(
    p_company_id,'purchases',p_order_id,o.currency
  );

  v_number:=public.erp_next_document_number(
    p_company_id,'purchase_invoice','PI',coalesce(o.effective_at,o.created_at)
  );
  insert into public.erp_commercial_workflow_documents(
    id,company_id,module,document_type,parent_id,document_number,payload,effective_at
  ) values(
    v_id,p_company_id,'purchases','invoice',p_order_id,v_number,
    jsonb_build_object(
      'currency',upper(o.currency),'totalAmount',o.total,
      'paidAmount',0,'remainingAmount',o.total,'paymentStatus','unpaid',
      'payments','[]'::jsonb,'createdBy',auth.uid(),
      'logisticsDocumentId',l->>'id',
      'logisticsDocumentNumber',l->>'number',
      'allocations',l->'allocations','warehouseIds',l->'warehouseIds',
      'accountingOwner','invoice','currencyPreparedAt',now()
    ),coalesce(o.effective_at,o.created_at)
  );
  perform public.erp_commercial_audit(
    p_company_id,'purchases',p_order_id,v_id,v_number,
    'create_invoice',null,'draft',
    'order currency independent from item cost currency'
  );
  return v_id;
end;
$$;

-- Keep the large invoice posting engine unchanged, but always run the repair
-- preflight immediately before it. This repairs old partner/item bindings and
-- makes same-currency and cross-currency item orders follow one path.

create or replace function public.erp_approve_cloud_sales_workflow_invoice(
  p_company_id uuid,p_invoice_id uuid
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_v750_approve_workflow_invoice_resilient(p_company_id,p_invoice_id,'sales');
end;
$$;

create or replace function public.erp_approve_cloud_purchase_workflow_invoice(
  p_company_id uuid,p_invoice_id uuid
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_v750_approve_workflow_invoice_resilient(p_company_id,p_invoice_id,'purchases');
end;
$$;

revoke all on function public.erp_create_cloud_sales_workflow_invoice(uuid,uuid) from public,anon;
revoke all on function public.erp_create_cloud_purchase_workflow_invoice(uuid,uuid) from public,anon;
revoke all on function public.erp_approve_cloud_sales_workflow_invoice(uuid,uuid) from public,anon;
revoke all on function public.erp_approve_cloud_purchase_workflow_invoice(uuid,uuid) from public,anon;
grant execute on function public.erp_create_cloud_sales_workflow_invoice(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_create_cloud_purchase_workflow_invoice(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_approve_cloud_sales_workflow_invoice(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_approve_cloud_purchase_workflow_invoice(uuid,uuid) to authenticated,service_role;
notify pgrst,'reload schema';
commit;
