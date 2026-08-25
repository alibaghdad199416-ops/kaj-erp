-- Quality Line ERP 18.9.28 / V7.5.8
-- Resilient invoice-draft creation and web blob-frame CSP compatibility.
begin;

create or replace function public.erp_v758_active_logistics(
  p_company_id uuid,p_order_id uuid,p_module text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_type text;
  v_result jsonb;
begin
  v_type:=case
    when p_module='sales' then 'delivery'
    when p_module='purchases' then 'receipt'
    else null
  end;
  if v_type is null then raise exception 'invalid_workflow_module'; end if;

  select jsonb_build_object(
    'id',d.id::text,
    'number',d.document_number,
    'allocations',coalesce(d.payload->'allocations','[]'::jsonb),
    'effectiveAt',coalesce(d.effective_at,d.created_at),
    'warehouseIds',coalesce(d.payload->'warehouseIds','[]'::jsonb)
  ) into v_result
  from public.erp_commercial_workflow_documents d
  where d.company_id=p_company_id
    and d.parent_id=p_order_id
    and d.module=p_module
    and d.document_type=v_type
    and lower(coalesce(d.status,'')) in ('approved','posted','completed','confirmed')
    and not d.is_deleted
    and (
      d.payload ? 'inventoryPostedAt'
      or d.payload ? 'inventory_posted_at'
      or lower(coalesce(d.status,'')) in ('posted','completed','confirmed')
    )
  order by coalesce(d.updated_at,d.created_at) desc
  limit 1;

  if v_result is null then
    raise exception 'approved_inventory_document_required';
  end if;
  return v_result;
end;
$$;

create or replace function public.erp_create_cloud_sales_workflow_invoice(
  p_company_id uuid,p_order_id uuid
) returns uuid
language plpgsql security definer set search_path=public as $$
declare
  v_id uuid:=gen_random_uuid();
  v_existing uuid;
  o public.erp_sales_orders_cloud%rowtype;
  l jsonb;
  v_number text;
  v_preflight_warning text;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['sales.create','sales.update','sales.approve']
  );
  perform pg_advisory_xact_lock(hashtextextended(p_company_id::text||':sales-invoice:'||p_order_id::text,0));

  select * into o
  from public.erp_sales_orders_cloud
  where company_id=p_company_id and id=p_order_id
    and lower(coalesce(status,'')) in ('approved','partially_executed','completed','confirmed')
    and not is_deleted
  for update;
  if not found then raise exception 'approved_sales_order_required'; end if;

  select id into v_existing
  from public.erp_commercial_workflow_documents
  where company_id=p_company_id and parent_id=p_order_id
    and module='sales' and document_type='invoice'
    and not is_deleted and lower(coalesce(status,'')) not in ('cancelled','deleted')
  order by created_at desc limit 1;
  if v_existing is not null then return v_existing; end if;

  l:=public.erp_v758_active_logistics(p_company_id,p_order_id,'sales');

  begin
    perform public.erp_v749_prepare_order_invoice_accounts(
      p_company_id,'sales',p_order_id,o.currency
    );
  exception when others then
    -- Draft creation must not be blocked by legacy account definitions.
    -- Approval reruns the strict repair/preflight before posting.
    v_preflight_warning:=sqlstate||':'||sqlerrm;
  end;

  v_number:=public.erp_next_document_number(
    p_company_id,'sales_invoice','SI',coalesce(o.effective_at,o.created_at)
  );
  insert into public.erp_commercial_workflow_documents(
    id,company_id,module,document_type,parent_id,document_number,payload,effective_at
  ) values(
    v_id,p_company_id,'sales','invoice',p_order_id,v_number,
    jsonb_strip_nulls(jsonb_build_object(
      'currency',upper(o.currency),'totalAmount',o.total,
      'paidAmount',0,'remainingAmount',o.total,'paymentStatus','unpaid',
      'payments','[]'::jsonb,'createdBy',auth.uid(),
      'logisticsDocumentId',l->>'id',
      'logisticsDocumentNumber',l->>'number',
      'allocations',l->'allocations','warehouseIds',l->'warehouseIds',
      'accountingOwner','invoice','currencyPreparedAt',now(),
      'accountPreflightWarning',v_preflight_warning
    )),coalesce(o.effective_at,o.created_at)
  );
  perform public.erp_commercial_audit(
    p_company_id,'sales',p_order_id,v_id,v_number,
    'create_invoice',null,'draft','resilient invoice draft creation'
  );
  return v_id;
end;
$$;

create or replace function public.erp_create_cloud_purchase_workflow_invoice(
  p_company_id uuid,p_order_id uuid
) returns uuid
language plpgsql security definer set search_path=public as $$
declare
  v_id uuid:=gen_random_uuid();
  v_existing uuid;
  o public.erp_purchase_orders_cloud%rowtype;
  l jsonb;
  v_number text;
  v_preflight_warning text;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['purchases.create','purchases.update','purchases.approve']
  );
  perform pg_advisory_xact_lock(hashtextextended(p_company_id::text||':purchase-invoice:'||p_order_id::text,0));

  select * into o
  from public.erp_purchase_orders_cloud
  where company_id=p_company_id and id=p_order_id
    and lower(coalesce(status,'')) in ('approved','partially_executed','completed','confirmed')
    and not is_deleted
  for update;
  if not found then raise exception 'approved_purchase_order_required'; end if;

  select id into v_existing
  from public.erp_commercial_workflow_documents
  where company_id=p_company_id and parent_id=p_order_id
    and module='purchases' and document_type='invoice'
    and not is_deleted and lower(coalesce(status,'')) not in ('cancelled','deleted')
  order by created_at desc limit 1;
  if v_existing is not null then return v_existing; end if;

  l:=public.erp_v758_active_logistics(p_company_id,p_order_id,'purchases');

  begin
    perform public.erp_v749_prepare_order_invoice_accounts(
      p_company_id,'purchases',p_order_id,o.currency
    );
  exception when others then
    v_preflight_warning:=sqlstate||':'||sqlerrm;
  end;

  v_number:=public.erp_next_document_number(
    p_company_id,'purchase_invoice','PI',coalesce(o.effective_at,o.created_at)
  );
  insert into public.erp_commercial_workflow_documents(
    id,company_id,module,document_type,parent_id,document_number,payload,effective_at
  ) values(
    v_id,p_company_id,'purchases','invoice',p_order_id,v_number,
    jsonb_strip_nulls(jsonb_build_object(
      'currency',upper(o.currency),'totalAmount',o.total,
      'paidAmount',0,'remainingAmount',o.total,'paymentStatus','unpaid',
      'payments','[]'::jsonb,'createdBy',auth.uid(),
      'logisticsDocumentId',l->>'id',
      'logisticsDocumentNumber',l->>'number',
      'allocations',l->'allocations','warehouseIds',l->'warehouseIds',
      'accountingOwner','invoice','currencyPreparedAt',now(),
      'accountPreflightWarning',v_preflight_warning
    )),coalesce(o.effective_at,o.created_at)
  );
  perform public.erp_commercial_audit(
    p_company_id,'purchases',p_order_id,v_id,v_number,
    'create_invoice',null,'draft','resilient invoice draft creation'
  );
  return v_id;
end;
$$;

revoke all on function public.erp_v758_active_logistics(uuid,uuid,text) from public,anon;
revoke all on function public.erp_create_cloud_sales_workflow_invoice(uuid,uuid) from public,anon;
revoke all on function public.erp_create_cloud_purchase_workflow_invoice(uuid,uuid) from public,anon;
grant execute on function public.erp_v758_active_logistics(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.erp_create_cloud_sales_workflow_invoice(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_create_cloud_purchase_workflow_invoice(uuid,uuid) to authenticated,service_role;
notify pgrst,'reload schema';
commit;
